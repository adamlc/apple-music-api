import Foundation

struct NowPlaying: Codable {
    var player_state: String
    var id: String?
    var name: String?
    var artist: String?
    var album: String?
    var playlist: String?
    var volume: Int?
    var muted: Bool?
    var repeatMode: String?
    var shuffle: Bool?

    enum CodingKeys: String, CodingKey {
        case player_state, id, name, artist, album, playlist, volume, muted, shuffle
        case repeatMode = "repeat"
    }
}

// One Apple Event round trip, asking only for the fields we actually need.
private let nowPlayingScript = """
tell application "Music"
    set ps to player state as text
    if ps is "stopped" then return {ps}
    set t to current track
    set pl to ""
    try
        set pl to name of current playlist
    end try
    return {ps, persistent ID of t, name of t, artist of t, album of t, year of t, sound volume, mute, song repeat as text, shuffle enabled, shuffle mode as text, pl}
end tell
"""

extension MusicScript {
    func nowPlaying() async throws -> NowPlaying {
        let d = try await run(nowPlayingScript)
        func s(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        let state = s(1)
        guard d.numberOfItems > 1 else { return NowPlaying(player_state: state) }

        let year = d.atIndex(6)?.int32Value ?? 0
        let album = year > 0 ? "\(s(5)) (\(year))" : s(5)
        let pl = s(12)
        return NowPlaying(
            player_state: state,
            id: s(2), name: s(3), artist: s(4), album: album,
            playlist: (pl == "Music" || pl == "Library") ? "" : pl,
            volume: Int(d.atIndex(7)?.int32Value ?? 0),
            muted: d.atIndex(8)?.booleanValue ?? false,
            repeatMode: s(9),
            shuffle: (d.atIndex(10)?.booleanValue ?? false) && !s(11).isEmpty
        )
    }
}
