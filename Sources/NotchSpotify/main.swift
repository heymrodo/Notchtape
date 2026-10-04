import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = Player()
    private let drawer = ThemeDrawer()
    private var notch: DynamicNotch<ExpandedView, CompactLeadingView, CompactTrailingView>?
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        let snapshot = Snapshot.requested
        if let snapshot { player.track = snapshot.track } else { player.start() }

        let player = player
        let drawer = drawer
        let notch = DynamicNotch(hoverBehavior: .all) {
            ExpandedView(player: player)
        } compactLeading: {
            CompactLeadingView(player: player)
        } compactTrailing: {
            CompactTrailingView(player: player)
        }
        notch.accessory = AnyView(ThemeTab(drawer: drawer, player: player))
        self.notch = notch

        // Snapshots drive the notch themselves. With the hover sink attached, wherever the real
        // pointer sits on screen would open and close the notch mid-capture.
        if let snapshot {
            if CommandLine.arguments.contains("--drawer") { drawer.open() }
            if CommandLine.arguments.contains("--sequence") {
                Task { await snapshot.captureSequence(notch) { drawer.toggle() } }
            } else if CommandLine.arguments.contains("--switch-sequence") {
                // Same write the tab's switcher makes, under the same animation.
                Task {
                    await snapshot.captureSequence(
                        notch, crop: .init(x: -200, y: 0, width: 400, height: 440), scale: 0.5
                    ) {
                        let defaults = UserDefaults.standard
                        let current = PlayerStyle.resolved(defaults.string(forKey: PlayerStyle.storageKey) ?? "")
                        let next: PlayerStyle = current == .cassette ? .turntable : .cassette
                        withAnimation(ThemeDrawer.slide) { defaults.set(next.rawValue, forKey: PlayerStyle.storageKey) }
                    }
                }
            } else if CommandLine.arguments.contains("--arm-sequence") {
                // Play, then pause: the tonearm swings on, then back to its rest.
                Task {
                    await snapshot.captureSequence(
                        notch, crop: .init(x: -200, y: 20, width: 400, height: 300), scale: 0.5, frames: 22
                    ) { player.track?.isPlaying.toggle() }
                }
            } else if CommandLine.arguments.contains("--hover-probe") {
                Task { await snapshot.probeHover(notch) }
            } else if CommandLine.arguments.contains("--open-sequence") {
                Task { await snapshot.captureOpenSequence(notch) }
            } else {
                Task { await snapshot.capture(notch) }
            }
            return
        }

        // The kit reports hover but doesn't change state on its own.
        cancellable = notch.$isHovering
            .removeDuplicates()
            .sink { hovering in
                Task {
                    guard !hovering else { return await notch.expand() }
                    await notch.compact()
                    // A notch that reopens should show the player, not a picker left open.
                    // Only once it's gone, so the tab doesn't fold shut on its way out.
                    if !notch.isHovering { drawer.close(animated: false) }
                }
            }


        Task { await notch.compact() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Notch Spotify")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Notch Spotify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}

/// `--snapshot out.png [artworkURL] [--drawer]`: opens the real notch, expanded, and writes what its
/// window draws. The app rendering its own views needs no Screen Recording permission,
/// unlike `screencapture`, so this is how the notch itself gets checked.
@MainActor
struct Snapshot {
    let path: String
    let track: Track

    static var requested: Snapshot? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), args.count > index + 1 else { return nil }
        let url = args.count > index + 2 ? URL(string: args[index + 2]) : nil
        if let url, let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            CassetteView.seed(url, image)
        }
        return Snapshot(
            path: args[index + 1],
            track: Track(
                title: "Dontmakemefallinlove", artist: "Cuco", artworkURL: url,
                isPlaying: false, position: 18, duration: 208
            )
        )
    }

    /// `--sequence`: toggles the finish strip open, then closed, and writes a contact sheet of
    /// frames through each move — the tab's black and its content should travel together.
    /// `crop` is relative to the window's horizontal centre; by default it frames the tab.
    func captureSequence<A, B, C>(
        _ notch: DynamicNotch<A, B, C>,
        crop: CGRect = .init(x: -170, y: 270, width: 340, height: 140),
        scale: CGFloat = 1,
        frames: Int = 10,
        toggle: () -> Void
    ) async {
        await notch.expand()
        try? await Task.sleep(for: .seconds(1.2))
        guard let view = notch.windowController?.window?.contentView else { exit(1) }

        let crop = crop.offsetBy(dx: view.bounds.midX, dy: 0)
        var columns: [[CGImage]] = []
        for _ in 0 ..< 2 {
            toggle()
            columns.append(await Self.frames(of: view, cropping: crop, count: frames))
            try? await Task.sleep(for: .seconds(0.6))
        }
        write(sheet: columns, cell: crop.size, scale: scale)
    }

    /// `--hover-probe [--expanded] [--map | --transition]`: sends synthetic mouse-moves to the
    /// notch's hosting view at points on and around the notch, and prints which the notch counts
    /// as hovered — in-process, so the real pointer is never moved. `--map` prints a grid around
    /// the panel's bottom edge; `--transition` crosses from the panel onto the tab and reports
    /// any hover change on the way.
    func probeHover<A, B, C>(_ notch: DynamicNotch<A, B, C>) async {
        let expanded = CommandLine.arguments.contains("--expanded")
        if expanded { await notch.expand() } else { await notch.compact() }
        // Generous: on the first launch after a build the window can still be fading in, and a
        // window mid-fade reads as not hovered anywhere.
        try? await Task.sleep(for: .seconds(2.5))
        guard let window = notch.windowController?.window, let view = window.contentView else { exit(1) }
        let midX = view.bounds.midX

        func move(to topLeft: CGPoint, exiting: Bool = false) {
            let flippedY = view.isFlipped ? topLeft.y : view.bounds.height - topLeft.y
            let location = view.convert(CGPoint(x: topLeft.x, y: flippedY), to: nil)
            let event = NSEvent.mouseEvent(
                with: .mouseMoved, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            )!
            // Straight to the hosting view: the window doesn't route synthetic moves to the
            // tracking area SwiftUI's hover listens on.
            if exiting {
                view.mouseMoved(with: event)
                view.mouseExited(with: event)
            } else {
                view.mouseEntered(with: event)
                view.mouseMoved(with: event)
            }
        }

        // Offsets from the top-centre of the window, in points, top-left origin.
        var probes: [(String, CGFloat, CGFloat)] = [
            ("on the notch, centre", 0, 16),
            ("on the notch, over the art", -110, 16),
            ("5pt below the notch", 0, 37),
            ("20pt below", 0, 52),
            ("40pt below", 0, 72),
            ("60pt below", 0, 92),
            ("100pt below", 0, 132),
            ("20pt below, off to the left", -150, 52),
            ("far away", -300, 300),
        ]
        if expanded {
            // Edges found from what the window actually draws: the panel's bottom at a column
            // the tab doesn't cover, and the tab's bottom at the centre.
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            let px = CGFloat(rep.pixelsWide) / view.bounds.width
            func lastOpaque(atX x: CGFloat) -> CGFloat {
                var last = 0
                for row in 0 ..< rep.pixelsHigh where (rep.colorAt(x: Int(x * px), y: row)?.alphaComponent ?? 0) > 0.5 { last = row }
                return CGFloat(last) / px
            }
            let panelBottom = lastOpaque(atX: midX - 140), tabBottom = lastOpaque(atX: midX)
            print(String(format: "panel bottom %.0fpt, tab bottom %.0fpt", panelBottom, tabBottom))
            if CommandLine.arguments.contains("--transition") {
                // Panel straight onto the tab, logging every hover change: none may read false.
                move(to: CGPoint(x: midX - 300, y: 460), exiting: true)
                try? await Task.sleep(for: .milliseconds(200))
                move(to: CGPoint(x: midX - 140, y: panelBottom - 6))
                try? await Task.sleep(for: .milliseconds(200))
                var log: [Bool] = []
                let watch = notch.$isHovering.dropFirst().sink { log.append($0) }
                for step in 1 ... 6 { // drift down across the seam in 6 steps
                    move(to: CGPoint(x: midX - 140 + CGFloat(step) * 23, y: panelBottom - 6 + CGFloat(step) * 4))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                try? await Task.sleep(for: .milliseconds(300))
                watch.cancel()
                print("hover changes while crossing panel → tab: \(log.isEmpty ? "none" : log.map { $0 ? "true" : "FALSE" }.joined(separator: ", "))")
                print("hovering at the end: \(notch.isHovering)")
                exit(0)
            }
            if CommandLine.arguments.contains("--map") {
                // Hover map around the panel's bottom edge and the tab: H hovered, x untrusted.
                // With the strip open, go deeper and coarser: it hangs ~100pt below the panel.
                let open = CommandLine.arguments.contains("--drawer")
                let step = open ? 20 : 10
                print(open ? "dx:        -190 .... -100 .... 0 .... +100 .... +190"
                           : "dx:        -190 ......... -100 ......... 0 ......... +100 ......... +190")
                for y in stride(from: panelBottom - 8, through: panelBottom + (open ? 112 : 36), by: open ? 8 : 4) {
                    var row = ""
                    for dx in stride(from: -190, through: 190, by: step) {
                        move(to: CGPoint(x: midX - 300, y: 460), exiting: true)
                        try? await Task.sleep(for: .milliseconds(100))
                        let reset = notch.isHovering
                        move(to: CGPoint(x: midX + CGFloat(dx), y: y))
                        try? await Task.sleep(for: .milliseconds(100))
                        row += reset ? "x" : (notch.isHovering ? "H" : ".")
                    }
                    print(String(format: "y %+5.0f  ", y - panelBottom) + row)
                }
                exit(0)
            }
            probes = [
                ("inside the panel, empty black", -140, panelBottom - 6),
                ("on the tab", 0, (panelBottom + tabBottom) / 2),
                ("beside the tab, under panel", -140, panelBottom + 8),
                ("5pt below the tab", 0, tabBottom + 5),
                ("30pt below the tab", 0, tabBottom + 30),
                ("far away", -300, 460),
            ]
        }
        window.acceptsMouseMovedEvents = true
        for (name, dx, y) in probes {
            move(to: CGPoint(x: midX - 300, y: 400), exiting: true) // reset: start each probe from outside
            try? await Task.sleep(for: .milliseconds(150))
            let reset = notch.isHovering
            move(to: CGPoint(x: midX + dx, y: y))
            try? await Task.sleep(for: .milliseconds(150))
            print(String(format: "%-30@ hover=%@%@", name as NSString,
                         notch.isHovering ? "YES" : "no ", reset ? "  (reset didn't take: untrusted)" : ""))
        }
        exit(0)
    }

    /// `--open-sequence`: from compact, opens the notch and then closes it again, writing a
    /// contact sheet of each — the finish tab should stay attached to the notch's bottom edge.
    func captureOpenSequence<A, B, C>(_ notch: DynamicNotch<A, B, C>) async {
        await notch.compact()
        try? await Task.sleep(for: .seconds(1.2)) // compact settles
        guard let view = notch.windowController?.window?.contentView else { exit(1) }

        let crop = CGRect(x: view.bounds.midX - 200, y: 0, width: 400, height: 350)
        let opening = Task { await notch.expand() }
        let open = await Self.frames(of: view, cropping: crop, count: 22)
        await opening.value
        try? await Task.sleep(for: .seconds(0.8))

        let closing = Task { await notch.compact() }
        let close = await Self.frames(of: view, cropping: crop, count: 14)
        await closing.value
        write(sheet: [open, close], cell: crop.size, scale: 0.5)
    }

    private static func frames(of view: NSView, cropping crop: CGRect, count: Int) async -> [CGImage] {
        var frames: [CGImage] = []
        for _ in 0 ..< count {
            if let frame = frame(of: view, cropping: crop) { frames.append(frame) }
            try? await Task.sleep(for: .milliseconds(35))
        }
        return frames
    }

    /// One column per sequence, frames top to bottom, each cell outlined.
    private func write(sheet columns: [[CGImage]], cell: CGSize, scale: CGFloat) -> Never {
        let cell = CGSize(width: cell.width * scale, height: cell.height * scale)
        let rows = columns.map(\.count).max() ?? 0
        let size = CGSize(width: cell.width * CGFloat(columns.count), height: cell.height * CGFloat(rows))
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { exit(1) }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        for (x, column) in columns.enumerated() {
            for (y, image) in column.enumerated() {
                let rect = CGRect(
                    x: CGFloat(x) * cell.width, y: size.height - CGFloat(y + 1) * cell.height,
                    width: cell.width, height: cell.height
                )
                context.draw(image, in: rect)
                context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.35))
                context.stroke(rect)
            }
        }
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }

    private static func frame(of view: NSView, cropping crop: CGRect) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let pixels = CGRect(
            x: crop.minX * scale, y: crop.minY * scale,
            width: crop.width * scale, height: crop.height * scale
        )
        return rep.cgImage?.cropping(to: pixels)
    }

    func capture<A, B, C>(_ notch: DynamicNotch<A, B, C>) async {
        await notch.expand()
        try? await Task.sleep(for: .seconds(1.2)) // let the spring settle
        guard let view = notch.windowController?.window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }
}

if CommandLine.arguments.contains("--self-check") {
    selfCheck()
    exit(0)
}

// Draws the deck controls alone at a few positions, for checking the groove and counters.
if let index = CommandLine.arguments.firstIndex(of: "--render-controls"), CommandLine.arguments.count > index + 1 {
    let path = CommandLine.arguments[index + 1]
    MainActor.assumeIsolated {
        let theme = Theme.named(CommandLine.arguments.count > index + 2 ? CommandLine.arguments[index + 2] : nil)
        let sheet = VStack(spacing: 12) {
            ForEach([0.0, 18, 104, 208], id: \.self) { position in
                DeckControls(
                    track: Track(title: "", artist: "", artworkURL: nil, isPlaying: position == 18, position: position, duration: 208),
                    theme: theme, seek: { _ in }, previous: {}, playPause: {}, next: {}
                )
                .frame(width: 292)
            }
        }
        .padding(12)
        .background(.black)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
    exit(0)
}

// Renders every theme in one sheet, for comparing finishes.
if let index = CommandLine.arguments.firstIndex(of: "--render-themes"), CommandLine.arguments.count > index + 2 {
    let path = CommandLine.arguments[index + 1]
    let url = URL(string: CommandLine.arguments[index + 2])!
    MainActor.assumeIsolated {
        if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            CassetteView.seed(url, image)
        }
        let track = Track(
            title: "Side A", artist: "Notch Tape", artworkURL: url,
            isPlaying: true, position: 18, duration: 208
        )
        let style = CommandLine.arguments.count > index + 3
            ? PlayerStyle(rawValue: CommandLine.arguments[index + 3]) ?? .cassette
            : .cassette
        let pairs = stride(from: 0, to: Theme.all.count, by: 2).map { Array(Theme.all[$0 ..< min($0 + 2, Theme.all.count)]) }
        let sheet = Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(pairs, id: \.first!.id) { pair in
                GridRow {
                    ForEach(pair) { theme in
                        var named = track
                        let _ = named.title = theme.name
                        PlayerView(track: named, style: style, theme: theme, width: 300)
                    }
                }
            }
        }
        .padding(10)
        .background(.black)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
    exit(0)
}

// Renders the cassette offscreen to a PNG, for eyeballing layout without launching the app.
if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
    let path = CommandLine.arguments[index + 1]
    MainActor.assumeIsolated {
        var track: Track?
        if CommandLine.arguments.count > index + 2,
           let url = URL(string: CommandLine.arguments[index + 2]) {
            if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                CassetteView.seed(url, image)
            }
            track = Track(
                title: CommandLine.arguments.count > index + 3 ? CommandLine.arguments[index + 3] : "Dontmakemefallinlove",
                artist: "Cuco", artworkURL: url,
                isPlaying: true, position: 18, duration: 208
            )
        }
        let renderer = ImageRenderer(content: CassetteView(track: track).padding(8).background(.black))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
    exit(0)
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
