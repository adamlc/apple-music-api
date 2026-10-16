import Foundation

struct ArtworkImage: Sendable {
    var data: Data
    var contentType: String
}

struct TrackIdentity: Sendable {
    var persistentID: String
    var name: String
    var artist: String
    var album: String
}

extension MusicScript {
    /// Which track is current, or nil when there isn't one.
    func currentTrackIdentity() async throws -> TrackIdentity? {
        let d: NSAppleEventDescriptor
        do {
            d = try await tell("return {persistent ID, name, artist, album} of current track")
        } catch is MusicNotRunning {
            throw MusicNotRunning()
        } catch {
            return nil  // no current track
        }
        guard d.numberOfItems == 4 else { return nil }
        func s(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        return TrackIdentity(persistentID: s(1), name: s(2), artist: s(3), album: s(4))
    }

    /// The artwork embedded in the current track, which library tracks have. Streamed Apple Music
    /// tracks that aren't in your library report no artwork to AppleScript at all.
    func embeddedArtwork() async throws -> ArtworkImage? {
        let d: NSAppleEventDescriptor
        do {
            d = try await tell("return data of artwork 1 of current track")
        } catch is MusicNotRunning {
            throw MusicNotRunning()
        } catch {
            return nil
        }
        let data = d.data
        guard data.count > 8 else { return nil }
        return ArtworkImage(data: data, contentType: ArtworkSearch.contentType(for: data))
    }
}

// MARK: - Fallback: Apple's public iTunes Search API

enum ArtworkSearch {
    struct Response: Decodable { var results: [Result] }
    struct Result: Decodable {
        var artistName: String?
        var trackName: String?
        var collectionName: String?
        var artworkUrl100: String?
    }

    /// Picks the search result that best matches the playing track, preferring the right album, and
    /// returns its artwork URL at a larger size (the API only lists a 100px thumbnail).
    static func bestArtworkURL(in results: [Result], for track: TrackIdentity, size: Int = 600) -> URL? {
        func same(_ a: String?, _ b: String) -> Bool {
            a?.caseInsensitiveCompare(b) == .orderedSame
        }
        let candidates = results.filter { same($0.trackName, track.name) && same($0.artistName, track.artist) && $0.artworkUrl100 != nil }
        let match = candidates.first { same($0.collectionName, track.album) } ?? candidates.first
        guard let thumbnail = match?.artworkUrl100 else { return nil }
        return URL(string: thumbnail.replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb"))
    }

    static func searchURL(for track: TrackIdentity) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.name) \(track.album)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        return components?.url
    }

    static func contentType(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        return "application/octet-stream"
    }

    static func fetch(for track: TrackIdentity) async -> ArtworkImage? {
        guard let searchURL = searchURL(for: track) else { return nil }
        var request = URLRequest(url: searchURL)
        request.timeoutInterval = 5
        guard let (body, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(Response.self, from: body),
              let imageURL = bestArtworkURL(in: response.results, for: track)
        else { return nil }

        var imageRequest = URLRequest(url: imageURL)
        imageRequest.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: imageRequest), data.count > 8 else { return nil }
        return ArtworkImage(data: data, contentType: contentType(for: data))
    }
}

/// Finds artwork for the current track: embedded artwork first, then Apple's search API for tracks
/// streamed from the Apple Music catalog. Results (including "none") are remembered per track.
actor ArtworkLookup {
    private let music: MusicScript
    private var cache: [String: ArtworkImage?] = [:]
    private var order: [String] = []
    private let limit = 20

    init(music: MusicScript) { self.music = music }

    func artwork() async throws -> ArtworkImage? {
        guard let track = try await music.currentTrackIdentity() else { return nil }
        if let cached = cache[track.persistentID] { return cached }

        var image = try await music.embeddedArtwork()
        if image == nil { image = await ArtworkSearch.fetch(for: track) }

        remember(image, for: track.persistentID)
        return image
    }

    private func remember(_ image: ArtworkImage?, for id: String) {
        cache[id] = .some(image)
        order.append(id)
        if order.count > limit { cache[order.removeFirst()] = nil }
    }
}
