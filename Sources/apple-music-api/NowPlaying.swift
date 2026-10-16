import Foundation

/// Encodes as the mode ("songs", "albums", "groupings") when shuffle is on, or `false` when off.
/// Home Assistant checks for the string "songs", so this must not be a plain bool.
struct Shuffle: Codable {
    var mode: String?

    init(mode: String?) { self.mode = mode }

    init(from decoder: Decoder) throws {
        mode = try? decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let mode { try c.encode(mode) } else { try c.encode(false) }
    }
}

struct NowPlaying: Codable {
    var player_state: String
    var id: String?
    var name: String?
    var artist: String?
    var album: String?
    var year: Int?
    var playlist: String?
    var volume: Int?
    var muted: Bool?
    var repeatMode: String?
    var shuffle: Shuffle?

    enum CodingKeys: String, CodingKey {
        case player_state, id, name, artist, album, year, playlist, volume, muted, shuffle
        case repeatMode = "repeat"
    }
}

// One Apple Event round trip, asking only for the fields we actually need.
private let nowPlayingScript = """
tell application "Music"
    set ps to player state as text
    if ps is "stopped" then return {ps}
    set pl to ""
    try
        set pl to name of current playlist
    end try
    try
        set t to current track
    on error
        return {ps}
    end try
    return {ps, persistent ID of t, name of t, artist of t, album of t, year of t, sound volume, mute, song repeat as text, shuffle enabled, shuffle mode as text, pl}
end tell
"""

extension NowPlaying {
    /// Builds the response from the list returned by `nowPlayingScript`. `emulatedMuteVolume` is the
    /// volume to restore while mute is emulated (see `MusicScript.setMuted`), nil when not muted.
    init(descriptor d: NSAppleEventDescriptor, emulatedMuteVolume: Int?) {
        func s(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        let state = s(1)
        guard d.numberOfItems > 1 else {
            self.init(player_state: state)
            return
        }

        let year = d.atIndex(6)?.int32Value ?? 0
        let pl = s(12)
        self.init(
            player_state: state,
            id: s(2), name: s(3), artist: s(4), album: s(5), year: year > 0 ? Int(year) : nil,
            playlist: (pl == "Music" || pl == "Library") ? "" : pl,
            volume: emulatedMuteVolume ?? Int(d.atIndex(7)?.int32Value ?? 0),
            muted: emulatedMuteVolume != nil || (d.atIndex(8)?.booleanValue ?? false),
            repeatMode: s(9),
            shuffle: Shuffle(mode: (d.atIndex(10)?.booleanValue ?? false) && !s(11).isEmpty ? s(11) : nil)
        )
    }
}

extension MusicScript {
    func nowPlaying() async throws -> NowPlaying {
        let d = try await run(nowPlayingScript)
        return NowPlaying(descriptor: d, emulatedMuteVolume: mutedVolume.withLock { $0 })
    }
}
