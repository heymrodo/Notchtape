import AppKit
import SwiftUI

/// A cassette finish. Everything a theme changes is colour and band treatment — the deck and
/// reel geometry is shared, so themes stay cheap to add.
struct Theme: Identifiable, Hashable {
    enum Band: Hashable {
        /// Thin horizontal bars carrying a vertical gradient.
        case stripes([Color])
        /// One solid block behind the tape window.
        case block(Color)
        case none
    }

    let id: String
    let name: String

    /// Tinting the shell: painted through the deck's own alpha, so the plastic keeps its
    /// moulding and shadows. `.color` keeps luminance and swaps hue; `.screen` lightens.
    let shellTint: Color?
    let shellBlend: BlendMode
    let shellLift: Double
    /// How strongly the tint is laid over the dark plastic. Bold colours hold up at the
    /// default; light ones need more, or they come out dusty — pastels went mauve at 55%.
    var shellStrength: Double = 0.55

    /// The cover art always shows through; a theme decides how far it is pushed towards
    /// the label colour.
    let artSaturation: Double
    let labelTint: Color
    let labelOpacity: Double
    /// Extra tint behind the lettering only, so the poster can stay bright everywhere else.
    let scrim: Double

    let ink: Color
    let subInk: Color
    let band: Band
    /// The deck's lit colour — tape counter, play key, scrubber — picked to glow on the
    /// black notch, which the band colour doesn't always do (Blue Hour's cobalt vanishes).
    let accent: Color

    static let storageKey = "cassetteTheme"

    /// The record player's pressing: the band's colours, run from the label out to the rim,
    /// or the shell colour for a finish without a band.
    var vinyl: [Color] {
        switch band {
        case let .stripes(colors): colors
        case let .block(color): [color]
        case .none: [shellTint ?? labelTint]
        }
    }

    /// The cassette shell as it lands on screen: the tint screened over the dark plastic
    /// (#2C292C) at `shellStrength`, then lifted — the same maths the cassette's layers do,
    /// so the record player's plinth can be painted to match.
    var shellColor: (red: Double, green: Double, blue: Double) {
        let plastic = (0.173, 0.161, 0.173)
        func channel(_ base: Double, _ tint: Double?) -> Double {
            guard let tint else { return min(1, base + shellLift) }
            let screened = 1 - (1 - base) * (1 - tint)
            return min(1, base + shellStrength * (screened - base) + shellLift)
        }
        let tint = shellTint.flatMap { NSColor($0).usingColorSpace(.sRGB) }
        return (
            channel(plastic.0, tint.map { Double($0.redComponent) }),
            channel(plastic.1, tint.map { Double($0.greenComponent) }),
            channel(plastic.2, tint.map { Double($0.blueComponent) })
        )
    }

    /// Dark enough that type on the shell needs to be light.
    var shellIsDark: Bool {
        let c = shellColor
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue < 0.45
    }

    /// Fill for the scrubber's groove: the band's own ramp where it has one.
    var progress: [Color] {
        if case let .stripes(colors) = band { return colors }
        return [accent.opacity(0.7), accent]
    }

    /// A few colours that identify the finish at a glance, for small swatches.
    var swatch: [Color] {
        switch band {
        case let .stripes(colors): colors
        case let .block(color): [labelTint, color]
        // No band to go on, so the shell carries the finish — Ultraviolet is its violet plastic.
        case .none: [shellTint ?? labelTint, ink]
        }
    }

    static let `default` = all[0]

    static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? .default
    }

    static let all: [Theme] = [
        Theme(
            id: "afterglow", name: "Afterglow",
            shellTint: nil, shellBlend: .normal, shellLift: 0,
            artSaturation: 0.95, labelTint: .black, labelOpacity: 0.42, scrim: 0.8,
            ink: .white, subInk: .white.opacity(0.6),
            band: .stripes([
                Color(red: 0.40, green: 0.31, blue: 0.92),
                Color(red: 0.55, green: 0.33, blue: 0.90),
                Color(red: 0.76, green: 0.32, blue: 0.78),
                Color(red: 0.93, green: 0.35, blue: 0.53),
                Color(red: 0.96, green: 0.55, blue: 0.33),
            ]),
            accent: Color(red: 0.98, green: 0.45, blue: 0.62)
        ),
        Theme(
            id: "lagoon", name: "Lagoon",
            shellTint: Color(red: 0.10, green: 0.45, blue: 0.50), shellBlend: .screen, shellLift: 0,
            artSaturation: 0.85, labelTint: Color(red: 0.04, green: 0.08, blue: 0.09), labelOpacity: 0.55, scrim: 0.82,
            ink: Color(red: 0.45, green: 0.95, blue: 0.90),
            subInk: Color(red: 0.45, green: 0.95, blue: 0.90).opacity(0.7),
            band: .stripes([
                Color(red: 0.35, green: 0.90, blue: 0.85),
                Color(red: 0.15, green: 0.65, blue: 0.70),
                Color(red: 0.08, green: 0.40, blue: 0.50),
            ]),
            accent: Color(red: 0.45, green: 0.95, blue: 0.90)
        ),
        Theme(
            id: "harvestgold", name: "Harvest Gold",
            shellTint: Color(red: 0.85, green: 0.80, blue: 0.68), shellBlend: .screen, shellLift: 0.08,
            artSaturation: 0.75, labelTint: Color(red: 0.42, green: 0.36, blue: 0.16), labelOpacity: 0.55, scrim: 0.78,
            ink: Color(red: 0.97, green: 0.95, blue: 0.88),
            subInk: Color(red: 0.90, green: 0.55, blue: 0.25),
            band: .stripes([
                Color(red: 0.97, green: 0.95, blue: 0.88),
                Color(red: 0.90, green: 0.86, blue: 0.72),
                Color(red: 0.90, green: 0.55, blue: 0.25),
            ]),
            accent: Color(red: 0.95, green: 0.62, blue: 0.28)
        ),
        Theme(
            id: "lavender", name: "Lavender",
            shellTint: Color(red: 0.75, green: 0.65, blue: 1.0), shellBlend: .screen, shellLift: 0.04,
            shellStrength: 0.8,
            artSaturation: 0.8, labelTint: Color(red: 0.97, green: 0.96, blue: 0.99), labelOpacity: 0.58, scrim: 0.8,
            ink: Color(red: 0.25, green: 0.15, blue: 0.45),
            subInk: Color(red: 0.50, green: 0.38, blue: 0.78),
            band: .block(Color(red: 0.62, green: 0.50, blue: 0.92)),
            accent: Color(red: 0.72, green: 0.62, blue: 1.0)
        ),
        Theme(
            id: "bluehour", name: "Blue Hour",
            shellTint: Color(red: 0.42, green: 0.52, blue: 0.70), shellBlend: .screen, shellLift: 0.02,
            artSaturation: 0.8, labelTint: Color(red: 0.93, green: 0.95, blue: 0.98), labelOpacity: 0.58, scrim: 0.82,
            ink: Color(red: 0.07, green: 0.13, blue: 0.36),
            subInk: Color(red: 0.28, green: 0.42, blue: 0.78),
            band: .block(Color(red: 0.18, green: 0.32, blue: 0.86)),
            accent: Color(red: 0.45, green: 0.62, blue: 1.0)
        ),
        Theme(
            id: "heatwave", name: "Heatwave",
            shellTint: nil, shellBlend: .normal, shellLift: 0,
            artSaturation: 0.85, labelTint: Color(red: 0.88, green: 0.36, blue: 0.28), labelOpacity: 0.48, scrim: 0.78,
            ink: Color(red: 0.09, green: 0.07, blue: 0.07),
            subInk: Color(red: 0.28, green: 0.20, blue: 0.18),
            band: .stripes([
                Color(red: 0.89, green: 0.34, blue: 0.27),
                Color(red: 0.93, green: 0.55, blue: 0.25),
                Color(red: 0.95, green: 0.75, blue: 0.42),
                Color(red: 0.96, green: 0.93, blue: 0.85),
            ]),
            accent: Color(red: 1.0, green: 0.45, blue: 0.28)
        ),
        Theme(
            id: "ultraviolet", name: "Ultraviolet",
            shellTint: Color(red: 0.55, green: 0.30, blue: 1.0), shellBlend: .screen, shellLift: 0.06,
            artSaturation: 0.85, labelTint: Color(red: 0.06, green: 0.04, blue: 0.10), labelOpacity: 0.55, scrim: 0.82,
            ink: Color(red: 0.78, green: 1.0, blue: 0.30),
            subInk: Color(red: 0.78, green: 1.0, blue: 0.30).opacity(0.7),
            band: .none,
            accent: Color(red: 0.78, green: 1.0, blue: 0.30)
        ),
    ]
}

/// Which machine the notch shows.
enum PlayerStyle: String, CaseIterable, Identifiable {
    case cassette
    case turntable

    static let storageKey = "playerStyle"

    /// Machines offered in the UI; a stored choice that isn't offered falls back to the
    /// cassette. Drop one from here to hide it without deleting it.
    static let offered: [PlayerStyle] = [.cassette, .turntable]

    static func resolved(_ rawValue: String) -> PlayerStyle {
        let style = PlayerStyle(rawValue: rawValue) ?? .cassette
        return offered.contains(style) ? style : .cassette
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cassette: "Cassette"
        case .turntable: "Record Player"
        }
    }

    /// There is no turntable symbol; a disc reads as a record at switcher size.
    var symbol: String {
        switch self {
        case .cassette: "recordingtape"
        case .turntable: "opticaldisc"
        }
    }

}
