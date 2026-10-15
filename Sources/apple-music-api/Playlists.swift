import Foundation

struct Playlist: Codable {
    var id: String
    var name: String
    var loved: Bool
    var duration_in_seconds: Int
    var time: String

    /// Numeric Music id, used to play the playlist. Not exposed over the API.
    var musicID: Int { _musicID }
    fileprivate var _musicID: Int = 0

    enum CodingKeys: String, CodingKey { case id, name, loved, duration_in_seconds, time }
}

/// "Outkast: The '90s" -> "outkast-the-90s"
func parameterize(_ s: String) -> String {
    let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    var out = ""
    var lastDash = true
    for ch in folded {
        if ch.isASCII && (ch.isLetter || ch.isNumber) {
            out.append(ch); lastDash = false
        } else if !lastDash {
            out.append("-"); lastDash = true
        }
    }
    if out.hasSuffix("-") { out.removeLast() }
    return out
}

extension MusicScript {
    func playlists(launch: Bool = false) async throws -> [Playlist] {
        // Bulk property fetch: one Apple Event per property, not per playlist.
        let d = try await tell("return {id, name, favorited, duration, time} of every playlist", launch: launch)
        guard d.numberOfItems == 5, let ids = d.atIndex(1), let names = d.atIndex(2),
              let loved = d.atIndex(3), let durations = d.atIndex(4), let times = d.atIndex(5)
        else { return [] }

        return (0..<ids.numberOfItems).map { i in
            let name = names.atIndex(i + 1)?.stringValue ?? ""
            var p = Playlist(
                id: parameterize(name),
                name: name,
                loved: loved.atIndex(i + 1)?.booleanValue ?? false,
                duration_in_seconds: Int(durations.atIndex(i + 1)?.int32Value ?? 0),
                time: times.atIndex(i + 1)?.stringValue ?? ""
            )
            p._musicID = Int(ids.atIndex(i + 1)?.int32Value ?? 0)
            return p
        }
    }

    /// Returns false if no playlist has that parameterized name.
    func playPlaylist(id: String) async throws -> Bool {
        try await ensureRunning()
        guard let playlist = try await playlists(launch: true).first(where: { $0.id == id }) else { return false }
        try await tell("play (first playlist whose id is \(playlist.musicID))", launch: true)
        return true
    }
}
