import SwiftUI

/// Scrolls its content when it is wider than `width`, otherwise centres it.
struct Marquee<Content: View>: View {
    let width: CGFloat
    let gap: CGFloat
    /// Points per second.
    let speed: CGFloat
    let content: Content

    init(width: CGFloat, gap: CGFloat, speed: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.gap = gap
        self.speed = speed
        self.content = content()
    }

    @State private var contentWidth: CGFloat = 0
    @State private var run = false
    @State private var starter: Task<Void, Never>?

    private var overflows: Bool { contentWidth > width + 0.5 }
    private var distance: CGFloat { contentWidth + gap }

    var body: some View {
        ZStack(alignment: .leading) {
            // A hidden copy measures one run of the content; the visible stack holds two.
            content
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { contentWidth = proxy.size.width }
                    }
                )

            HStack(spacing: gap) {
                content.fixedSize()
                if overflows { content.fixedSize() }
            }
            .offset(x: run ? -distance : 0)
        }
        // Declared here rather than via `withAnimation`, so a re-render (the player polls
        // every second) re-attaches the animation instead of dropping it and leaving the
        // title parked at the end of its travel.
        .animation(
            run ? .linear(duration: Double(distance / speed)).repeatForever(autoreverses: false)
                : nil,
            value: run
        )
        .frame(width: width, alignment: overflows ? .leading : .center)
        .clipped()
        .onAppear { restart() }
        .onDisappear { stop() }
        .onChange(of: contentWidth) { restart() }
    }

    private func stop() {
        starter?.cancel()
        run = false
    }

    /// Shows the content still and fully readable, then scrolls. The notch keeps this view
    /// alive while closed, so every appearance starts a fresh pass.
    private func restart() {
        stop()
        guard overflows else { return }
        starter = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            run = true
        }
    }
}

/// Spins while playing and freezes where it stopped. A `repeatForever` rotation can't do
/// this: pausing animates the angle back to its start, so the reel visibly unwinds.
struct Spinner<Content: View>: View {
    let isPlaying: Bool
    let degreesPerSecond: Double
    let content: Content

    init(isPlaying: Bool, degreesPerSecond: Double = 90, @ViewBuilder content: () -> Content) {
        self.isPlaying = isPlaying
        self.degreesPerSecond = degreesPerSecond
        self.content = content()
    }

    /// Degrees banked from previous spins; the live angle adds the time since `since`.
    @State private var banked: Double = 0
    @State private var since: Date = .now
    @State private var onScreen = false

    private var spinning: Bool { isPlaying && onScreen }

    var body: some View {
        Group {
            if spinning {
                TimelineView(.animation) { context in
                    content.rotationEffect(.degrees(angle(at: context.date)))
                }
            } else {
                content.rotationEffect(.degrees(banked))
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: spinning) { _, isSpinning in
            if isSpinning {
                since = .now
            } else {
                // Fold the elapsed spin in, so it holds where it stopped.
                banked = angle(at: .now).truncatingRemainder(dividingBy: 360)
            }
        }
    }

    private func angle(at date: Date) -> Double {
        banked + date.timeIntervalSince(since) * degreesPerSecond
    }
}
