import SwiftUI

/// Whether the finish picker is open. Shared because the tab lives in the notch kit's
/// view tree, and the app has to close it again when the notch collapses.
@MainActor
final class ThemeDrawer: ObservableObject {
    @Published private(set) var isOpen = false
    /// Whether the strip is laid out at all. A laid-out strip counts as hover even folded to
    /// nothing — clipped, transparent, ignoring the pointer — so a closed strip's thumbnails
    /// held the notch open beside the tab. Mounted just before it opens, and dropped only
    /// once the closing slide has finished, so the slide itself looks the same.
    @Published private(set) var stripMounted = false

    static let slide = Animation.snappy(duration: 0.32)

    func toggle() {
        isOpen ? close(animated: true) : open()
    }

    /// Opening and closing run inside `withAnimation`. The tab's black backing and its
    /// notch-shaped mask belong to the kit, above the tab's own views, so an `.animation`
    /// modifier inside the tab can't reach them: they'd snap while the strip chased them.
    func open() {
        // Both in one transaction. Mounting first, outside it, made SwiftUI flush that change
        // the moment the animation began — mid-way through setting `isOpen` — so the tab
        // rendered with the old value, used up the change notice, and never opened.
        withAnimation(Self.slide) {
            stripMounted = true
            isOpen = true
        }
    }

    func close(animated: Bool) {
        guard animated else {
            isOpen = false
            stripMounted = false
            return
        }
        withAnimation(Self.slide, completionCriteria: .logicallyComplete) {
            isOpen = false
        } completion: {
            if !self.isOpen { self.stripMounted = false }
        }
    }
}

/// The tab hanging under the expanded notch. Closed, it reads like a notch live activity —
/// the finish in bold, a swatch where the weather icon would be. Open, it drops down into
/// a strip of every finish, scrolling sideways.
struct ThemeTab: View {
    @ObservedObject var drawer: ThemeDrawer
    @ObservedObject var player: Player
    @AppStorage(Theme.storageKey) private var themeID = Theme.default.id
    @AppStorage(PlayerStyle.storageKey) private var styleID = PlayerStyle.cassette.rawValue

    private var theme: Theme { Theme.named(themeID) }
    private var style: PlayerStyle { PlayerStyle.resolved(styleID) }

    /// The widest the tab can get and still hang from the flat part of the notch's bottom
    /// edge: past this its shoulders would reach round the notch's rounded corners.
    private static let stripWidth: CGFloat = 276
    private static let thumbnailWidth: CGFloat = 76
    /// Both machines' thumbnails share the cassette's height, so the strip never resizes:
    /// the square record player is drawn that tall.
    private static let thumbnailHeight = CassetteView.height(forWidth: thumbnailWidth)
    private var thumbnailWidth: CGFloat { style == .turntable ? Self.thumbnailHeight : Self.thumbnailWidth }
    /// Square record players sit in narrower columns than cassettes, so a fourth one peeks in
    /// at the edge of the strip and says it scrolls. Still wide enough for "Harvest Gold".
    private var columnWidth: CGFloat { style == .turntable ? 62 : Self.thumbnailWidth }
    private static let labelHeight: CGFloat = 12
    private static let bottomInset: CGFloat = 10
    /// Fixed rather than measured, so the first open already knows how far to slide.
    private static let stripHeight = thumbnailHeight + 4 + labelHeight + bottomInset

    @State private var headerWidth: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { headerWidth = $0 }

                // Pinned to the bottom of a frame that grows from nothing, the thumbnails slide
                // down out from under the header. The frame is always here; the strip inside it
                // only while open or closing (see `ThemeDrawer.stripMounted`).
                Group {
                    if drawer.stripMounted {
                        strip
                            // Centre on the current finish while still folded, so it never jumps.
                            .onAppear { proxy.scrollTo(themeID, anchor: .center) }
                    }
                }
                .frame(
                    width: drawer.isOpen ? Self.stripWidth : headerWidth,
                    height: drawer.isOpen ? Self.stripHeight : 0,
                    alignment: .bottom
                )
                .clipped()
                .opacity(drawer.isOpen ? 1 : 0)
                .allowsHitTesting(drawer.isOpen)
            }
        }
        // Never stretch to the width the notch offers — the tab hugs its content.
        .fixedSize()
        .animation(.snappy(duration: 0.25), value: themeID)
    }

    private var header: some View {
        HStack(spacing: 0) {
            if PlayerStyle.offered.count > 1 {
                MachineSwitch(style: style) { choice in
                    // Animated, so the notch grows or shrinks to the other machine smoothly.
                    withAnimation(ThemeDrawer.slide) { styleID = choice.rawValue }
                }
                .padding(.leading, 5)

                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1, height: 14)
                    .padding(.leading, 8)
            }

            HoverButton(label: drawer.isOpen ? "Hide finishes" : "Change finish") {
                drawer.toggle()
            } content: { hovering in
                HStack(spacing: 8) {
                    Text(theme.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Swatch(colors: theme.swatch)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.35))
                        .rotationEffect(.degrees(drawer.isOpen ? 180 : 0))
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .opacity(hovering ? 1 : 0.92)
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Theme.all) { option in
                    thumbnail(option).id(option.id)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: Self.stripWidth, height: Self.stripHeight - Self.bottomInset)
        // Soft edges say "there's more" without a scroll bar.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.bottom, Self.bottomInset)
    }

    private func thumbnail(_ option: Theme) -> some View {
        let selected = option.id == themeID
        return Button {
            themeID = option.id
        } label: {
            VStack(spacing: 4) {
                PlayerView(track: stillTrack, style: style, theme: option, width: thumbnailWidth)
                    .overlay(
                        // The plinth's corners are ~16% of its width; the cassette's are tight.
                        RoundedRectangle(cornerRadius: style == .turntable ? 7 : 4, style: .continuous)
                            .strokeBorder(
                                .white.opacity(selected ? 0.9 : 0.14),
                                lineWidth: selected ? 1.5 : 0.5
                            )
                    )
                Text(option.name)
                    .font(.system(size: 9, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(selected ? 0.95 : 0.5))
                    .lineLimit(1)
                    .frame(height: Self.labelHeight)
            }
            .frame(width: columnWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.name)
    }

    /// Thumbnails hold still — seven sets of spinning reels in a picker is wasted motion. The
    /// position is zeroed too, so the once-a-second poll leaves the thumbnails' input equal
    /// and SwiftUI skips redrawing them.
    private var stillTrack: Track? {
        guard var track = player.track else { return nil }
        track.isPlaying = false
        track.position = 0
        return track
    }
}

/// The weather-icon slot: a small disc painted with the finish's own colours.
private struct Swatch: View {
    let colors: [Color]

    var body: some View {
        Circle()
            .fill(AngularGradient(colors: colors + [colors.first ?? .clear], center: .center))
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .frame(width: 13, height: 13)
    }
}

/// Cassette or record player, as two icons in a capsule, like a segmented control.
private struct MachineSwitch: View {
    let style: PlayerStyle
    let select: (PlayerStyle) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PlayerStyle.offered) { option in
                let selected = option == style
                HoverButton(label: option.name) {
                    select(option)
                } content: { hovering in
                    Image(systemName: option.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : hovering ? 0.75 : 0.4))
                        .frame(width: 26, height: 19)
                        .background(Capsule().fill(.white.opacity(selected ? 0.18 : 0)))
                }
                .help(option.name)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
        .animation(.snappy(duration: 0.2), value: style)
    }
}

/// A plain button that hands its content the hover state.
private struct HoverButton<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content(hovering).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(label)
    }
}
