import SwiftUI

/// The turntable: `turntable.svg` is the plinth, `Tonearm` is the arm that has to sit
/// above the record, and the record itself is drawn between them so it can spin.
struct TurntableView: View {
    let track: Track?
    var width: CGFloat = 250
    var theme: Theme = .default

    /// `turntable.svg` is cropped to the plinth, so its viewBox has a non-zero origin.
    private static let origin = CGPoint(x: 2, y: 2)
    private static let viewBox = CGSize(width: 569, height: 569)

    /// Raised from the plinth's centre (286), and the lettering lowered, to make room for a
    /// record this size between the plinth's top edge and the title.
    private static let centre = CGPoint(x: 286.084, y: 265)
    private static let recordRadius: CGFloat = 195
    private static let labelRadius: CGFloat = 77
    private static let spindleRadius: CGFloat = 9

    private static let titleBox = CGRect(x: 60, y: 476, width: 452, height: 34)
    private static let artistBox = CGRect(x: 60, y: 511, width: 452, height: 20)

    private var scale: CGFloat { width / Self.viewBox.width }
    private func x(_ value: CGFloat) -> CGFloat { (value - Self.origin.x) * scale }
    private func y(_ value: CGFloat) -> CGFloat { (value - Self.origin.y) * scale }
    private var height: CGFloat { Self.viewBox.height * scale }
    private var isPlaying: Bool { track?.isPlaying == true }

    @State private var cover: NSImage?
    /// Degrees about the pivot, 0 on the record; and 0…1 for how far it's raised.
    @State private var armAngle: Double
    @State private var armLift: Double = 0
    @State private var armMove: Task<Void, Never>?

    init(track: Track?, width: CGFloat = 250, theme: Theme = .default) {
        self.track = track
        self.width = width
        self.theme = theme
        // Start where the arm belongs, so it never swings in on first appearance.
        _armAngle = State(initialValue: track?.isPlaying == true ? 0 : Tonearm.restAngle)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            plinth
            record
            Tonearm(origin: Self.origin, scale: scale, angle: armAngle, lift: armLift)
                .frame(width: width, height: height)
            if width >= 80 { lettering }
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .onChange(of: isPlaying) { _, playing in moveArm(onRecord: playing) }
        .task(id: track?.artworkURL) { cover = await CassetteView.cover(for: track?.artworkURL) }
    }

    /// Like an automatic turntable: lift, swing about the pivot, lower. Interrupting a move
    /// (play again mid-swing) starts the next one from wherever the arm is.
    private func moveArm(onRecord: Bool) {
        armMove?.cancel()
        armMove = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.18)) { armLift = 1 }
            try? await Task.sleep(for: .seconds(0.18))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.7)) { armAngle = onRecord ? 0 : Tonearm.restAngle }
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.22)) { armLift = 0 }
        }
    }

    /// Painted the colour of this finish's cassette shell: multiplied by it, normalised by
    /// the plinth's own mean brightness (0.903), so it reads as the same plastic and keeps its
    /// seams and shading. Afterglow and Heatwave go dark like their cassettes.
    ///
    /// A multiply blend over a masked fill rather than `.colorMultiply`: that's a colour filter,
    /// and the window's layer rendering skipped it, leaving the plinth untinted.
    private var plinth: some View {
        let shell = theme.shellColor
        let gain = 1 / 0.903
        let paint = Color(
            red: min(1, shell.red * gain),
            green: min(1, shell.green * gain),
            blue: min(1, shell.blue * gain)
        )
        return ZStack {
            image("turntable").frame(width: width, height: height)
            Rectangle()
                .fill(paint)
                .frame(width: width, height: height)
                .blendMode(.multiply)
                .mask(image("turntable").frame(width: width, height: height))
        }
        .compositingGroup()
    }

    private var ink: Color { theme.shellIsDark ? Color(white: 0.96) : Color(red: 0.11, green: 0.10, blue: 0.11) }
    private var subInk: Color { theme.shellIsDark ? Color(white: 0.96).opacity(0.6) : Color(red: 0.42, green: 0.41, blue: 0.42) }

    // MARK: - Record

    /// 33⅓ rpm is 200°/s, which reads as a blur at this size; half speed still says "spinning".
    private var record: some View {
        Spinner(isPlaying: isPlaying, degreesPerSecond: 100) { vinyl }
            .frame(width: Self.recordRadius * 2 * scale, height: Self.recordRadius * 2 * scale)
            .offset(
                x: x(Self.centre.x - Self.recordRadius),
                y: y(Self.centre.y - Self.recordRadius)
            )
    }

    private var vinyl: some View {
        ZStack {
            Circle().fill(Color(red: 0.06, green: 0.06, blue: 0.07))
            // A coloured pressing in the finish's colours, a little translucent over black so
            // it keeps the depth of vinyl, and darkened towards the rim.
            Circle()
                .fill(
                    RadialGradient(
                        colors: theme.vinyl.count > 1 ? theme.vinyl : theme.vinyl + theme.vinyl,
                        center: .center,
                        startRadius: Self.labelRadius * scale,
                        endRadius: Self.recordRadius * scale
                    )
                )
                .opacity(0.8)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.35)],
                        center: .center,
                        startRadius: Self.recordRadius * 0.6 * scale,
                        endRadius: Self.recordRadius * scale
                    )
                )

            // Grooves, plus a highlight that sweeps as the record turns.
            ForEach(0 ..< 9, id: \.self) { ring in
                Circle()
                    .strokeBorder(.white.opacity(0.05), lineWidth: 0.6 * scale)
                    .padding(CGFloat(ring) * 7 * scale + 8 * scale)
            }
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.clear, .white.opacity(0.12), .clear, .white.opacity(0.06), .clear],
                        center: .center
                    )
                )

            label
            Circle()
                .fill(Color(red: 0.06, green: 0.06, blue: 0.07))
                .frame(
                    width: Self.spindleRadius * 2 * scale,
                    height: Self.spindleRadius * 2 * scale
                )
        }
    }

    @ViewBuilder
    private var label: some View {
        let diameter = Self.labelRadius * 2 * scale
        ZStack {
            if let cover = cover ?? track?.artworkURL.flatMap(CassetteView.cached) {
                Image(nsImage: cover).resizable().scaledToFill()
            } else {
                theme.labelTint
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1 * scale))
    }

    // MARK: - Lettering

    /// Centred on the plinth below the record, light or dark to suit the plinth's colour.
    private var lettering: some View {
        ZStack(alignment: .topLeading) {
            Marquee(
                width: Self.titleBox.width * scale,
                gap: 26 * scale,
                speed: 20 * scale
            ) {
                Text(track?.title ?? "No record")
                    .font(.system(size: 21 * scale, weight: .bold))
                    .foregroundStyle(ink)
            }
            .frame(width: Self.titleBox.width * scale, height: Self.titleBox.height * scale)
            .offset(x: x(Self.titleBox.minX), y: y(Self.titleBox.minY))

            Text(track?.artist ?? "")
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(subInk)
                .lineLimit(1)
                .frame(
                    width: Self.artistBox.width * scale,
                    height: Self.artistBox.height * scale,
                    alignment: .center
                )
                .offset(x: x(Self.artistBox.minX), y: y(Self.artistBox.minY))
        }
    }

    private func image(_ name: String) -> some View {
        Image(nsImage: CassetteView.svg(name)).resizable()
    }
}

/// A white tonearm: a round two-tier base at the lower left, an S-curved arm rising from it
/// with a short tail below, and a slotted headshell resting on the record's outer grooves.
/// Drawn in the plinth's artboard coordinates. `Animatable`, so SwiftUI interpolates the swing
/// and the lift frame by frame; a raised arm casts a longer, softer shadow.
private struct Tonearm: View, Animatable {
    let origin: CGPoint
    let scale: CGFloat
    var angle: Double
    var lift: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, lift) }
        set {
            angle = newValue.first
            lift = newValue.second
        }
    }

    /// Parked: swung out about the pivot until the headshell is clear of the record.
    static let restAngle: Double = -20

    private static let pivot = CGPoint(x: 92, y: 412)
    private static let tail = CGPoint(x: 84, y: 456)
    /// Headshell centre on the record, and its tilt clockwise from upright.
    private static let head = CGPoint(x: 109, y: 233)
    private static let tilt = Angle.degrees(35)
    private static let headSize = CGSize(width: 27, height: 48)

    private static let white = Color(white: 0.97)
    private static let edge = Color(white: 0.80)

    var body: some View {
        Canvas { context, _ in
            var fixed = context
            fixed.addFilter(.shadow(color: .black.opacity(0.18), radius: 2 * scale, x: 0.5 * scale, y: scale))
            fixed.drawLayer { layer in
                artboard(&layer)
                drawBase(in: &layer)
            }

            var arm = context
            arm.addFilter(.shadow(
                color: .black.opacity(0.22 + 0.1 * lift),
                radius: (3 + 5 * lift) * scale,
                x: (1 + 2 * lift) * scale,
                y: (2 + 6 * lift) * scale
            ))
            arm.drawLayer { layer in
                artboard(&layer)
                // Swing about the pivot, and grow a touch while raised: nearer to the eye.
                layer.translateBy(x: Self.pivot.x, y: Self.pivot.y)
                layer.rotate(by: .degrees(angle))
                layer.scaleBy(x: 1 + 0.03 * lift, y: 1 + 0.03 * lift)
                layer.translateBy(x: -Self.pivot.x, y: -Self.pivot.y)
                drawArm(in: &layer)
            }

            var cap = context
            cap.drawLayer { layer in
                artboard(&layer)
                let circle = Circle().path(in: Self.square(Self.pivot, radius: 19))
                layer.fill(circle, with: .color(Self.white))
                layer.stroke(circle, with: .color(Self.edge), lineWidth: 0.8)
            }
        }
    }

    private func artboard(_ layer: inout GraphicsContext) {
        layer.scaleBy(x: scale, y: scale)
        layer.translateBy(x: -origin.x, y: -origin.y)
    }

    private func drawBase(in context: inout GraphicsContext) {
        let plate = Circle().path(in: Self.square(Self.pivot, radius: 36))
        context.fill(plate, with: .color(Color(white: 0.92)))
        context.stroke(plate, with: .color(Self.edge), lineWidth: 0.8)
    }

    private func drawArm(in context: inout GraphicsContext) {
        let arm = armPath
        context.stroke(arm, with: .color(Self.edge), style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))
        context.stroke(arm, with: .color(Self.white), style: StrokeStyle(lineWidth: 12.5, lineCap: .round, lineJoin: .round))

        var head = context
        head.translateBy(x: Self.head.x, y: Self.head.y)
        head.rotate(by: Self.tilt)
        let shell = RoundedRectangle(cornerRadius: 5.5, style: .continuous).path(in: CGRect(
            x: -Self.headSize.width / 2, y: -Self.headSize.height / 2,
            width: Self.headSize.width, height: Self.headSize.height
        ))
        head.fill(shell, with: .color(Self.white))
        head.stroke(shell, with: .color(Self.edge), lineWidth: 1)
        for x in [-6.0, 6.0] {
            let slot = RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: x - 2.25, y: -19, width: 4.5, height: 11))
            head.fill(slot, with: .color(Color(white: 0.6)))
        }
    }

    private static var axis: CGPoint { CGPoint(x: sin(tilt.radians), y: -cos(tilt.radians)) }

    private static var neck: CGPoint {
        CGPoint(x: head.x - axis.x * headSize.height / 2, y: head.y - axis.y * headSize.height / 2)
    }

    /// Tail → pivot → a rise that bends to meet the headshell along its own axis.
    private var armPath: Path {
        var path = Path()
        path.move(to: Self.tail)
        path.addLine(to: Self.pivot)
        path.addCurve(
            to: Self.neck,
            control1: CGPoint(x: 90, y: 350),
            control2: CGPoint(x: Self.neck.x - Self.axis.x * 34, y: Self.neck.y - Self.axis.y * 34)
        )
        return path
    }

    private static func square(_ centre: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}
