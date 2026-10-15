import Foundation

struct Playlist: Encodable {
    var id: String
    var name: String
    var loved: Bool
    var duration_in_seconds: Int
    var time: String

    // Used to play the playlist; not part of the JSON.
    var musicID = 0
    var persistentID = ""

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

/// Gives each playlist a URL-friendly id from its name. The first playlist with a given name keeps the
/// plain id (so existing setups don't break); later ones with the same name get a suffix from their
/// persistent id, which stays the same even if playlists are reordered.
func playlistIDs(names: [String], persistentIDs: [String]) -> [String] {
    var seen = Set<String>()
    return zip(names, persistentIDs).map { name, persistentID in
        let slug = parameterize(name)
        let unique = persistentID.lowercased()
        var id = slug.isEmpty ? unique : slug
        if !seen.insert(id).inserted {
            id = slug.isEmpty ? unique : "\(slug)-\(unique.suffix(6))"
            seen.insert(id)
        }
        return id
    }
}

extension MusicScript {
    func playlists(launch: Bool = false) async throws -> [Playlist] {
        // Bulk property fetch: one Apple Event per property, not per playlist.
        let d = try await tell("return {id, name, favorited, duration, time, persistent ID} of every playlist", launch: launch)
        guard d.numberOfItems == 6, let ids = d.atIndex(1), let names = d.atIndex(2),
              let loved = d.atIndex(3), let durations = d.atIndex(4), let times = d.atIndex(5),
              let persistent = d.atIndex(6)
        else { return [] }

        let count = ids.numberOfItems
        let nameList = (0..<count).map { names.atIndex($0 + 1)?.stringValue ?? "" }
        let persistentList = (0..<count).map { persistent.atIndex($0 + 1)?.stringValue ?? "" }
        let slugs = playlistIDs(names: nameList, persistentIDs: persistentList)

        return (0..<count).map { i in
            Playlist(
                id: slugs[i],
                name: nameList[i],
                loved: loved.atIndex(i + 1)?.booleanValue ?? false,
                duration_in_seconds: Int(durations.atIndex(i + 1)?.int32Value ?? 0),
                time: times.atIndex(i + 1)?.stringValue ?? "",
                musicID: Int(ids.atIndex(i + 1)?.int32Value ?? 0),
                persistentID: persistentList[i]
            )
        }
    }

    /// Plays the playlist with this id, or this persistent id. Returns false if there isn't one.
    func playPlaylist(id: String) async throws -> Bool {
        try await ensureRunning()
        let all = try await playlists(launch: true)
        guard let playlist = all.first(where: { $0.id == id })
            ?? all.first(where: { !$0.persistentID.isEmpty && $0.persistentID.caseInsensitiveCompare(id) == .orderedSame })
        else { return false }
        try await tell("play (first playlist whose id is \(playlist.musicID))", launch: true)
        return true
    }
}
