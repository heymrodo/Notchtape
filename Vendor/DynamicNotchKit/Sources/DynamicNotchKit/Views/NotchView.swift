//
//  NotchView.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2023-08-24.
//

import SwiftUI

struct NotchView<Expanded, CompactLeading, CompactTrailing>: View where Expanded: View, CompactLeading: View, CompactTrailing: View {
    @ObservedObject private var dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>
    @State private var compactLeadingWidth: CGFloat = 0
    @State private var compactTrailingWidth: CGFloat = 0
    @State private var overNotch = false
    @State private var overAccessory = false
    @State private var leaving: Task<Void, Never>?
    private let safeAreaInset: CGFloat = 15

    init(dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>) {
        self.dynamicNotch = dynamicNotch
    }

    private var expandedNotchCornerRadii: (top: CGFloat, bottom: CGFloat) {
        if case let .notch(topCornerRadius, bottomCornerRadius) = dynamicNotch.style {
            (top: topCornerRadius, bottom: bottomCornerRadius)
        } else {
            (top: 15, bottom: 20)
        }
    }

    private var compactNotchCornerRadii: (top: CGFloat, bottom: CGFloat) {
        (top: 6, bottom: 14)
    }

    private var minWidth: CGFloat {
        dynamicNotch.notchSize.width + (topCornerRadius * 2)
    }

    private var topCornerRadius: CGFloat {
        dynamicNotch.state == .expanded ? expandedNotchCornerRadii.top : compactNotchCornerRadii.top
    }

    private var bottomCornerRadius: CGFloat {
        dynamicNotch.state == .expanded ? expandedNotchCornerRadii.bottom : compactNotchCornerRadii.bottom
    }

    private var xOffset: CGFloat {
        if dynamicNotch.state != .compact {
            0
        } else {
            compactXOffset
        }
    }

    private var compactXOffset: CGFloat {
        (compactTrailingWidth - compactLeadingWidth) / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            notchContent()
                // The visible notch is the hover target, empty black included — without this
                // only its drawn content would count, and the notch would collapse under a
                // pointer resting on blank space inside it.
                .contentShape(Rectangle())
                .background {
                    Rectangle()
                        .foregroundStyle(.black)
                        .padding(-50) // The opening/closing animation can overshoot, so this makes sure that it's still black
                        // Paint only. The mask hides this overshoot but doesn't stop it being hit,
                        // so it made the notch open with the pointer up to 50pt away from it.
                        .allowsHitTesting(false)
                }
                .mask {
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                    .padding(.horizontal, 0.5)
                    .frame(
                        width: dynamicNotch.state != .hidden ? nil : minWidth,
                        height: dynamicNotch.state != .hidden ? nil : dynamicNotch.notchSize.height
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .onHover { overNotch = $0; reportHover() }

            if let accessory = dynamicNotch.accessory {
                let shown = dynamicNotch.state == .expanded && dynamicNotch.accessoryShown
                // Always laid out, never inserted: an inserted view appears at its final spot,
                // so the tab floated in below a notch that was still growing. Folded to nothing
                // while hidden, so compact has no hover area below it.
                //
                // It comes out only after the notch has settled (see `accessoryShown`): pinned
                // to the bottom of a frame that grows from the notch's edge, it slides out from
                // under it. Going away, it fades on its own fast clock, gone before the closing
                // notch has moved far enough for the two to part.
                accessoryTab(accessory)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: shown ? 0.2 : 0.1), value: shown)
                    .frame(height: shown ? nil : 0, alignment: .bottom)
                    .clipped()
                    .allowsHitTesting(shown)
                    // Outside the clip, so the 1pt tuck under the notch survives it.
                    .padding(.top, -1)
                    .onHover { overAccessory = $0; reportHover() }
            }
        }
        .offset(x: xOffset)
        .animation(.smooth, value: [compactLeadingWidth, compactTrailingWidth])
    }

    /// One hover state for the notch and its accessory together. Each tracks its own area —
    /// one `.onHover` around both would follow the rectangle enclosing them, so the empty
    /// desktop beside the accessory would hold the notch open. Moving from one onto the
    /// other arrives as an exit then an enter, so leaving is reported a beat late and
    /// cancelled if the pointer lands on the other part.
    private func reportHover() {
        leaving?.cancel()
        if overNotch || overAccessory {
            dynamicNotch.updateHoverState(true)
        } else {
            leaving = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                dynamicNotch.updateHoverState(false)
            }
        }
    }

    /// The same concave shoulders as the notch itself, so panel and tab read as one piece
    /// of black. The caller tucks it 1pt up under the panel so the two antialiased edges
    /// leave no seam.
    private func accessoryTab(_ content: AnyView) -> some View {
        let shoulder: CGFloat = 12
        return content
            .padding(.horizontal, shoulder)
            .background(Color.black)
            .mask(NotchShape(topCornerRadius: shoulder, bottomCornerRadius: 14))
    }

    private func notchContent() -> some View {
        ZStack {
            compactContent()
                .fixedSize()
                .offset(x: dynamicNotch.state == .compact ? 0 : compactXOffset)
                .frame(
                    width: dynamicNotch.state == .compact ? nil : dynamicNotch.notchSize.width,
                    height: (dynamicNotch.state == .compact && dynamicNotch.isHovering) ? dynamicNotch.menubarHeight : dynamicNotch.notchSize.height
                )

            expandedContent()
                .fixedSize()
                .frame(
                    maxWidth: dynamicNotch.state == .expanded ? nil : 0,
                    maxHeight: dynamicNotch.state == .expanded ? nil : 0
                )
                .offset(x: dynamicNotch.state == .compact ? -compactXOffset : 0)
        }
        .padding(.horizontal, topCornerRadius)
        .fixedSize()
        .frame(minWidth: minWidth, minHeight: dynamicNotch.notchSize.height)
    }

    func compactContent() -> some View {
        HStack(spacing: 0) {
            if dynamicNotch.state == .compact, !dynamicNotch.disableCompactLeading {
                dynamicNotch.compactLeadingContent
                    .environment(\.notchSection, .compactLeading)
                    .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 8) }
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { compactLeadingWidth = $0 }
                    .transition(.blur(intensity: 10).combined(with: .scale(x: 0, anchor: .trailing)).combined(with: .opacity))
            }

            Spacer()
                .frame(width: dynamicNotch.notchSize.width)

            if dynamicNotch.state == .compact, !dynamicNotch.disableCompactTrailing {
                dynamicNotch.compactTrailingContent
                    .environment(\.notchSection, .compactTrailing)
                    .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: 8) }
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { compactTrailingWidth = $0 }
                    .transition(.blur(intensity: 10).combined(with: .scale(x: 0, anchor: .leading)).combined(with: .opacity))
            }
        }
        .frame(height: dynamicNotch.notchSize.height)
        .onChange(of: dynamicNotch.disableCompactLeading) { _ in
            if dynamicNotch.disableCompactLeading {
                compactLeadingWidth = 0
            }
        }
        .onChange(of: dynamicNotch.disableCompactTrailing) { _ in
            if dynamicNotch.disableCompactTrailing {
                compactTrailingWidth = 0
            }
        }
    }

    func expandedContent() -> some View {
        HStack(spacing: 0) {
            if dynamicNotch.state == .expanded {
                dynamicNotch.expandedContent
                    .transition(.blur(intensity: 10).combined(with: .scale(y: 0.6, anchor: .top)).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: dynamicNotch.notchSize.height) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: safeAreaInset) }
        .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
        .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
        .frame(minWidth: dynamicNotch.notchSize.width)
    }
}
