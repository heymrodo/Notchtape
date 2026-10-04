import SwiftUI

@MainActor
final class Player: ObservableObject {
    @Published var track: Track?

    private var timer: Timer?

    func start() {
        refresh()
        // ponytail: 1s AppleScript poll on the main thread (NSAppleScript requires it, ~10ms).
        // If it ever stutters, move to a serial queue with an NSAppleScript per queue.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    func refresh() {
        let new = Spotify.state()
        if new != track { track = new }
    }

    func act(_ command: () -> Void) {
        command()
        refresh()
    }
}

private struct Artwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "music.note")
                .foregroundStyle(.white)
                .font(.system(size: size * 0.4))
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: size * 0.15))
    }
}

struct CompactLeadingView: View {
    @ObservedObject var player: Player

    var body: some View {
        Artwork(url: player.track?.artworkURL, size: 20)
            .padding(.leading, 4)
    }
}

struct CompactTrailingView: View {
    @ObservedObject var player: Player

    var body: some View {
        Image(systemName: player.track?.isPlaying == true ? "waveform" : "pause.fill")
            .symbolEffect(.variableColor.iterative, isActive: player.track?.isPlaying == true)
            .foregroundStyle(.white)
            .frame(width: 20)
            .padding(.trailing, 4)
    }
}

struct ExpandedView: View {
    @ObservedObject var player: Player
    @AppStorage(Theme.storageKey) private var themeID = Theme.default.id
    @AppStorage(PlayerStyle.storageKey) private var styleID = PlayerStyle.cassette.rawValue

    private var style: PlayerStyle { PlayerStyle.resolved(styleID) }

    private let notchWidth: CGFloat = 316

    var body: some View {
        playerStack
            .padding(.horizontal, 12)
            .padding(.top, 8)
            // Nothing below: the kit already insets 15pt under the content, which puts the
            // controls ~16pt above the notch's edge and the finish tab hanging from it.
            .frame(width: notchWidth)
            .foregroundStyle(.white)
    }

    private var playerStack: some View {
        VStack(spacing: 10) {
            PlayerView(
                track: player.track,
                style: style,
                theme: Theme.named(themeID)
            )

            if let track = player.track {
                controls(track)
            } else {
                Text(Spotify.isRunning ? "Open a track in Spotify" : "Spotify isn\u{2019}t running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
            }
        }
    }

    private func controls(_ track: Track) -> some View {
        DeckControls(
            track: track,
            theme: Theme.named(themeID),
            seek: { seconds in player.act { Spotify.seek(to: seconds) } },
            previous: { player.act { Spotify.previous() } },
            playPause: { player.act { Spotify.playPause() } },
            next: { player.act { Spotify.next() } }
        )
    }
}


/// Draws whichever machine is selected.
struct PlayerView: View {
    let track: Track?
    let style: PlayerStyle
    let theme: Theme
    var width: CGFloat?

    var body: some View {
        switch style {
        case .cassette:
            CassetteView(track: track, width: width ?? 292, theme: theme)
        case .turntable:
            TurntableView(track: track, width: width ?? 236, theme: theme)
        }
    }
}
