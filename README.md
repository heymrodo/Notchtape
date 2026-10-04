# Notchtape

A retro cassette and record player for Spotify, living in your MacBook notch.

Notchtape turns your MacBook notch into a retro player for Spotify. Hover it and a cassette drops down, reels turning as the song plays, or switch to a record player whose tonearm lifts away when you pause. Pick from seven finishes, and the tape counters, play ring and progress bar light up to match. Native Swift and SwiftUI, macOS 14+.

## Features

- **Lives in the notch.** Hover the notch to open the player; move away and it tucks back in.
- **Cassette or record player.** Reels spin while the song plays and stop dead on pause. On the record player, the tonearm lifts, swings onto the record on play and back to its rest on pause.
- **Seven finishes.** Afterglow, Lagoon, Harvest Gold, Lavender, Blue Hour, Heatwave and Ultraviolet. Each one colours the shell, the label and the controls.
- **Tape-deck controls.** Tape counters, a glowing play ring and a progress groove, all lit in the finish's colour. Drag the groove to seek.
- **Switch from the notch.** The tab under the notch switches between cassette and record player, and drops down into a strip of every finish.

## Requirements

- A MacBook with a notch, on macOS 14 or later
- The Spotify desktop app. Notchtape controls it over AppleScript, so there is no sign-in and it works on the free tier.
- Xcode 16 or later (Swift 6 toolchain) to build

## Build and run

```bash
./bundle.sh
open NotchSpotify.app
```

`bundle.sh` builds a release binary and wraps it in an ad-hoc signed app bundle. On first launch, macOS asks for permission to control Spotify. Quit from the music-note icon in the menu bar.

## Project layout

- `Sources/NotchSpotify/Spotify.swift`: the AppleScript bridge to the Spotify app.
- `Sources/NotchSpotify/Cassette.swift`, `Turntable.swift`: the two players. The shells are SVGs in `Resources/`, rendered natively through `NSImage`; reels, vinyl and tonearm are drawn in SwiftUI.
- `Sources/NotchSpotify/Controls.swift`: tape counters, progress groove and transport buttons.
- `Sources/NotchSpotify/Theme.swift`: the seven finishes and the player style.
- `Sources/NotchSpotify/ThemeTab.swift`: the tab under the notch and its finish strip.
- `Sources/NotchSpotify/Motion.swift`: the shared marquee and spinner.
- `Sources/NotchSpotify/main.swift`: the app, the hover wiring, and the development tools below.
- `Vendor/DynamicNotchKit`: notch geometry and animation (see Credits).

## Development

The binary has a few tools for checking changes without clicking through the app. Build with `swift build -c release`, then run `.build/release/NotchSpotify` with:

- `--self-check`: runs the AppleScript-parsing checks.
- `--render out.png [artworkURL] [title]`, `--render-themes out.png artworkURL [turntable]`, `--render-controls out.png [finish]`: draw players and controls offscreen.
- `--snapshot out.png [artworkURL] [--drawer]`: opens the real notch and writes what it draws. Add `--sequence`, `--open-sequence`, `--switch-sequence` or `--arm-sequence` for frame-by-frame contact sheets of each animation.
- `--snapshot /dev/null --hover-probe [--expanded] [--map | --transition]`: maps where the notch counts as hovered, from synthetic in-process mouse moves.

## Credits

Notch geometry and animation come from [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) by Kai Azim (MIT, licence in `Vendor/DynamicNotchKit/LICENSE`), vendored with a small change that adds the tab under the notch and its hover handling.

Notchtape is not affiliated with or endorsed by Spotify.
