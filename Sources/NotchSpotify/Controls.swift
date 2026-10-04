import SwiftUI

/// The transport, dressed as a cassette deck: a tape counter either side of a groove, and
/// bare skip glyphs around a glowing play ring. Everything lit takes the finish's accent.
struct DeckControls: View {
    let track: Track
    let theme: Theme
    let seek: (Double) -> Void
    let previous: () -> Void
    let playPause: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                TapeCounter(seconds: track.position, accent: theme.accent)
                TapeGroove(
                    position: track.position,
                    duration: track.duration,
                    fill: theme.progress,
                    seek: seek
                )
                TapeCounter(seconds: track.duration, accent: theme.accent)
            }

            HStack(spacing: 26) {
                Skip(symbol: "backward.fill", action: previous)
                PlayRing(isPlaying: track.isPlaying, accent: theme.accent, action: playPause)
                Skip(symbol: "forward.fill", action: next)
            }
        }
    }
}

/// A tape-deck counter: glowing digits over the faint, unlit segments of "88:88".
private struct TapeCounter: View {
    let seconds: Double
    let accent: Color

    var body: some View {
        let time = Self.clock(seconds)
        ZStack {
            Text(String(time.map { $0.isNumber ? "8" : $0 }))
                .foregroundStyle(accent.opacity(0.1))
            Text(time)
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.55), radius: 3)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// A recessed groove, filled with the finish's colours up to a fader-cap thumb. Seeks on
/// release — the system slider seeked Spotify on every pixel of a drag.
private struct TapeGroove: View {
    let position: Double
    let duration: Double
    let fill: [Color]
    let seek: (Double) -> Void

    @State private var scrubbing: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = CGFloat(min(max((scrubbing ?? position) / max(duration, 1), 0), 1))
            let active = hovering || scrubbing != nil

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.6))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                    .frame(height: 5)

                // Each colour keeps its place along the whole track, rather than the ramp
                // squeezing into the filled part: the capsule is only as wide as the progress,
                // and its gradient runs past its own right edge to where the track ends. No
                // mask or clip — the window's layer rendering drew those as one stretched colour.
                let filled = max(5, width * progress)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: fill,
                            startPoint: .leading,
                            endPoint: UnitPoint(x: width / filled, y: 0.5)
                        )
                    )
                    .frame(width: filled, height: 5)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.white)
                    .frame(width: 4, height: active ? 14 : 11)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
                    .offset(x: min(max(width * progress - 2, 0), width - 4))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { scrubbing = time(at: $0.location.x, in: width) }
                    .onEnded {
                        seek(time(at: $0.location.x, in: width))
                        scrubbing = nil
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 18)
        .animation(.snappy(duration: 0.15), value: hovering)
    }

    private func time(at x: CGFloat, in width: CGFloat) -> Double {
        Double(min(max(x / max(width, 1), 0), 1)) * duration
    }
}

/// A bare skip glyph that brightens under the pointer.
private struct Skip: View {
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.75))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Play/pause as a thin glowing ring in the finish's accent, filling faintly on hover.
private struct PlayRing: View {
    let isPlaying: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(Circle().fill(accent.opacity(hovering ? 0.22 : 0.12)))
                .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
                .shadow(color: accent.opacity(hovering ? 0.7 : 0.5), radius: hovering ? 6 : 4)
                .contentShape(Circle())
        }
        .buttonStyle(Pressable())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Dips slightly while held.
private struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
