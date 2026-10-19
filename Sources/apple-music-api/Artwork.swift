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
        guard let thumbnail = match?.artworkUrl100,
              let url = URL(string: thumbnail.replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb")),
              isSafeArtworkURL(url)
        else { return nil }
        return url
    }

    /// The artwork link comes from a network response, so only follow HTTPS links to Apple's image hosts.
    static func isSafeArtworkURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "mzstatic.com" || host.hasSuffix(".mzstatic.com")
            || host == "apple.com" || host.hasSuffix(".apple.com")
    }

    private static let maxTermLength = 120
    private static let maxSearchBytes = 1 * 1024 * 1024
    private static let maxImageBytes = 5 * 1024 * 1024

    /// Percent-encodes everything except unreserved characters. URLQueryItem leaves `+` as it is, and
    /// the search service then reads it as a space ("Florence + the Machine" would lose its plus).
    private static func encode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static func searchURL(for track: TrackIdentity) -> URL? {
        // Metadata can be arbitrarily long, so cap each part.
        let term = [track.artist, track.name, track.album].map { String($0.prefix(maxTermLength)) }.joined(separator: " ")
        return URL(string: "https://itunes.apple.com/search?term=\(encode(term))&entity=song&limit=10")
    }

    static func contentType(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        return "application/octet-stream"
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    /// GET `url`, accepting only a 200 response within `maxBytes`.
    private static func download(_ url: URL, maxBytes: Int) async -> (data: Data, mimeType: String)? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= maxBytes
        else { return nil }
        return (data, http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? "")
    }

    static func fetch(for track: TrackIdentity) async -> ArtworkImage? {
        guard let searchURL = searchURL(for: track),
              let search = await download(searchURL, maxBytes: maxSearchBytes),
              let response = try? JSONDecoder().decode(Response.self, from: search.data),
              let imageURL = bestArtworkURL(in: response.results, for: track),
              let image = await download(imageURL, maxBytes: maxImageBytes),
              image.mimeType.hasPrefix("image/"), image.data.count > 8
        else { return nil }
        return ArtworkImage(data: image.data, contentType: contentType(for: image.data))
    }
}

/// Finds artwork for the current track: embedded artwork first, then Apple's search API for tracks
/// streamed from the Apple Music catalog. Results (including "none") are remembered per track.
actor ArtworkLookup {
    private let music: MusicScript
    private var cache: [String: ArtworkImage?] = [:]
    private var order: [String] = []
    private let limit = 50

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
