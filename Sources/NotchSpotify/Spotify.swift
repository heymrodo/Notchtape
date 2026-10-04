import AppKit
import Foundation

struct Track: Equatable {
    var title: String
    var artist: String
    var artworkURL: URL?
    var isPlaying: Bool
    var position: Double // seconds
    var duration: Double // seconds
}

/// Talks to the Spotify desktop app over AppleScript. No auth, no network, works on the free tier.
enum Spotify {
    /// Tab-separated so a track title containing a newline can't shift the fields.
    /// Tab-separated so a track title containing a newline can't shift the fields.
    /// Every field is guarded: Spotify hands back `missing value` whenever no track is loaded,
    /// and concatenating that into the reply aborts the whole script.
    private static let stateScript = """
    if application "Spotify" is not running then return "notrunning"
    tell application "Spotify"
        try
            set t to name of current track
            set a to artist of current track
            set u to artwork url of current track
            set p to player position
            set d to duration of current track
        on error
            return "notrunning"
        end try
        if t is missing value then return "notrunning"
        if a is missing value then set a to ""
        if u is missing value then set u to ""
        if p is missing value then set p to 0
        if d is missing value then set d to 0
        return t & tab & a & tab & u & tab & (player state as text) & tab \
    & ((p as integer) as text) & tab & ((d as integer) as text)
    end tell
    """

    @discardableResult
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("AppleScript error: \(error)")
            return nil
        }
        return result?.stringValue
    }

    static func state() -> Track? { parse(run(stateScript)) }

    static var isRunning: Bool {
        !NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.spotify.client" }.isEmpty
    }

    static func parse(_ raw: String?) -> Track? {
        guard let raw, raw != "notrunning" else { return nil }
        let f = raw.components(separatedBy: "\t")
        guard f.count == 6, let position = Double(f[4]), let ms = Double(f[5]) else { return nil }
        return Track(
            title: f[0],
            artist: f[1],
            artworkURL: URL(string: f[2]),
            isPlaying: f[3] == "playing",
            position: position,
            duration: ms / 1000 // Spotify reports track duration in milliseconds
        )
    }

    static func playPause() { run(#"tell application "Spotify" to playpause"#) }
    static func next() { run(#"tell application "Spotify" to next track"#) }
    static func previous() { run(#"tell application "Spotify" to previous track"#) }
    static func seek(to seconds: Double) {
        run(#"tell application "Spotify" to set player position to \#(Int(seconds))"#)
    }
}

func selfCheck() {
    precondition(Spotify.parse("notrunning") == nil)
    precondition(Spotify.parse(nil) == nil)
    precondition(Spotify.parse("too\tfew\tfields") == nil)
    precondition(Spotify.parse("a\tb\thttps://i.co/x\tplaying\tnope\t1000") == nil)

    let t = Spotify.parse("Song\tBand\thttps://i.scdn.co/x\tplaying\t42\t215000")!
    precondition(t.title == "Song" && t.artist == "Band")
    precondition(t.isPlaying)
    precondition(t.position == 42)
    precondition(t.duration == 215)
    precondition(t.artworkURL?.host == "i.scdn.co")

    let paused = Spotify.parse("S\tB\t\tpaused\t0\t1000")!
    precondition(!paused.isPlaying)
    precondition(paused.artworkURL == nil || paused.artworkURL?.absoluteString == "")

    print("self-check OK")
}
