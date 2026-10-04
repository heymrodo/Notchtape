import SwiftUI

/// The cassette, assembled from the SVGs in `Resources` plus a label drawn on top in the
/// style of a C60 mixtape. Constants are in the original 547x374 artboard's coordinates and
/// are mapped through `x()`/`y()`, which subtract the cropped viewBox origin and scale.
struct CassetteView: View {
    let track: Track?
    var width: CGFloat = 292
    var theme: Theme = .default

    /// `deck.svg` is cropped to the cassette body, so its viewBox has a non-zero origin.
    private static let origin = CGPoint(x: 38, y: 26)
    private static let viewBox = CGSize(width: 471, height: 298)

    /// The label's bounding box, and the stripe band that runs behind the tape window.
    private static let label = CGRect(x: 70, y: 55, width: 406, height: 180)
    private static let band = CGRect(x: 70, y: 121, width: 406, height: 70)

    /// Reel centres, and the size of `reel.svg` (a 68x68 viewBox drawn around one reel).
    private static let reelCentres: [CGFloat] = [196.25, 351.25]
    private static let reelCentreY: CGFloat = 156.25
    private static let reelSize: CGFloat = 68

    static func height(forWidth width: CGFloat) -> CGFloat {
        width * viewBox.height / viewBox.width
    }

    private var scale: CGFloat { width / Self.viewBox.width }
    private func x(_ value: CGFloat) -> CGFloat { (value - Self.origin.x) * scale }
    private func y(_ value: CGFloat) -> CGFloat { (value - Self.origin.y) * scale }
    private var height: CGFloat { Self.viewBox.height * scale }
    private var isPlaying: Bool { track?.isPlaying == true }

    @State private var cover: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            shell

            printedLabel

            ForEach(Self.reelCentres, id: \.self) { reel(centredAt: $0) }

            if width >= 80 { lettering }
        }
        .frame(width: width, height: height)
        .compositingGroup()
    }

    /// The moulded plastic. A tint is painted through the deck's own alpha so it colours the
    /// shell without spilling into the transparent corners.
    private var shell: some View {
        ZStack {
            image("deck").frame(width: width, height: height)
            if let tint = theme.shellTint {
                Rectangle()
                    .fill(tint)
                    .frame(width: width, height: height)
                    .blendMode(theme.shellBlend)
                    .mask(image("deck").frame(width: width, height: height))
                    .opacity(theme.shellStrength)
            }
        }
        .brightness(theme.shellLift)
        .compositingGroup()
    }

    // MARK: - Label

    /// Cover art darkened almost to black, with the stripe band over it. `label.svg` masks
    /// this to the label shape and punches out the tape window.
    private var printedLabel: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ZStack {
                artwork.saturation(theme.artSaturation)
                theme.labelTint.opacity(theme.labelOpacity)
            }
            .frame(width: Self.label.width * scale, height: Self.label.height * scale)
            .clipped()
            .offset(x: x(Self.label.minX), y: y(Self.label.minY))

            scrim(height: 66, from: Self.label.minY, flipped: false)
            scrim(height: 46, from: Self.label.maxY - 46, flipped: true)

            bandFill
                .frame(width: Self.band.width * scale, height: Self.band.height * scale)
                .offset(x: x(Self.band.minX), y: y(Self.band.minY))
        }
        .frame(width: width, height: height)
        .mask(image("label").frame(width: width, height: height))
        .task(id: track?.artworkURL) { cover = await Self.cover(for: track?.artworkURL) }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover = cover ?? track?.artworkURL.flatMap(Self.cached) {
            Image(nsImage: cover).resizable().scaledToFill()
        } else {
            Color(red: 0.09, green: 0.08, blue: 0.09)
        }
    }

    /// Darkens only the strips the lettering sits on, so the poster reads through the rest.
    private func scrim(height: CGFloat, from top: CGFloat, flipped: Bool) -> some View {
        LinearGradient(
            colors: [theme.labelTint.opacity(theme.scrim), theme.labelTint.opacity(0)],
            startPoint: flipped ? .bottom : .top,
            endPoint: flipped ? .top : .bottom
        )
        .frame(width: Self.label.width * scale, height: height * scale)
        .offset(x: x(Self.label.minX), y: y(top))
    }

    @ViewBuilder
    private var bandFill: some View {
        switch theme.band {
        case let .stripes(colors):
            stripes(colors)
        case let .block(color):
            color
        case .none:
            Color.clear
        }
    }

    /// Horizontal bars carrying a vertical gradient — the gradient is masked by the bars
    /// rather than coloured per-bar, so the ramp stays continuous across the band.
    @ViewBuilder
    private func stripes(_ colors: [Color]) -> some View {
        let gradient = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        // The bars are ~3pt in the artboard. Below that they vanish, so a thumbnail
        // keeps the same ramp as a solid band.
        if 3.4 * scale < 1 {
            gradient
        } else {
            gradient.mask(
                VStack(spacing: 2.6 * scale) {
                    ForEach(0 ..< 12, id: \.self) { _ in
                        Rectangle().frame(height: 3.4 * scale)
                    }
                }
            )
        }
    }

    // MARK: - Lettering

    private var lettering: some View {
        ZStack(alignment: .topLeading) {
            text(track?.artist ?? "", size: 6.5, weight: .semibold, tracking: 2.2,
                 in: CGRect(x: 150, y: 66, width: 246, height: 10), align: .center)
                .foregroundStyle(theme.subInk)

            title

            badge("A", caption: "SIDE", at: 82)
            badge("C60", caption: "LOW NOISE", at: 428)

            text("COMPACT CASSETTE", size: 6, weight: .medium, tracking: 2.6,
                 in: CGRect(x: 150, y: 200, width: 246, height: 10), align: .center)
                .foregroundStyle(theme.subInk.opacity(0.8))
        }
    }

    /// The title always prints at the same size; anything too long for the label scrolls.
    private var title: some View {
        let box = CGRect(x: 148, y: 76, width: 250, height: 36)
        return Marquee(width: box.width * scale, gap: 26 * scale, speed: 20 * scale) {
            Text((track?.title ?? "No tape").uppercased())
                .font(.system(size: 27 * scale, weight: .black))
                .tracking(0.5 * scale)
                .foregroundStyle(theme.ink)
        }
        .frame(width: box.width * scale, height: box.height * scale)
        .offset(x: x(box.minX), y: y(box.minY))
        .id(track?.title)
    }

    /// A boxed mark in a corner of the label: "A / SIDE" on the left, tape length on the right.
    private func badge(_ mark: String, caption: String, at left: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5 * scale)
                .strokeBorder(theme.ink.opacity(0.85), lineWidth: 1.4 * scale)
                .frame(width: 36 * scale, height: 32 * scale)
                .offset(x: x(left), y: y(72))

            text(mark, size: 14, weight: .bold, tracking: 0,
                 in: CGRect(x: left, y: 79, width: 36, height: 20), align: .center)
                .foregroundStyle(theme.ink)

            text(caption, size: 5.5, weight: .semibold, tracking: 1.2,
                 in: CGRect(x: left - 12, y: 106, width: 60, height: 8), align: .center)
                .foregroundStyle(theme.subInk)
        }
    }

    private func text(
        _ string: String, size: CGFloat, weight: Font.Weight, tracking: CGFloat,
        in box: CGRect, align: Alignment
    ) -> some View {
        Text(string.uppercased())
            .font(.system(size: size * scale, weight: weight))
            .tracking(tracking * scale)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: box.width * scale, height: box.height * scale, alignment: align)
            .offset(x: x(box.minX), y: y(box.minY))
    }

    // MARK: - Reels

    private func reel(centredAt centre: CGFloat) -> some View {
        Spinner(isPlaying: isPlaying) { image("reel") }
            .frame(width: Self.reelSize * scale, height: Self.reelSize * scale)
            .offset(
                x: x(centre - Self.reelSize / 2),
                y: y(Self.reelCentreY - Self.reelSize / 2)
            )
    }

    // MARK: - Resources

    private func image(_ name: String) -> some View {
        Image(nsImage: Self.svg(name)).resizable()
    }

    private static var covers: [URL: NSImage] = [:]

    /// Cover art is fetched once per URL and kept, so re-opening the notch doesn't refetch.
    static func cover(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let hit = covers[url] { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        covers[url] = image
        return image
    }

    static func cached(_ url: URL) -> NSImage? { covers[url] }

    /// Used by `--render` to draw real cover art without waiting on the network.
    static func seed(_ url: URL, _ image: NSImage) { covers[url] = image }

    private static var cache: [String: NSImage] = [:]

    /// macOS renders SVG natively through NSImage, so the files ship as-is.
    static func svg(_ name: String) -> NSImage {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            NSLog("\(name).svg missing from bundle")
            return NSImage(size: viewBox)
        }
        cache[name] = image
        return image
    }
}
