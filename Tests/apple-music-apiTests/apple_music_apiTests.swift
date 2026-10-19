import AppKit
import Foundation
import Testing
@testable import apple_music_api

// MARK: - Helpers

/// A descriptor shaped like the list returned by the now-playing script.
private func playingList(
    state: String = "playing", year: Int32 = 2013, playlist: String = "Summer Jams",
    volume: Int32 = 60, muted: Bool = false, repeatMode: String = "all",
    shuffleEnabled: Bool = true, shuffleMode: String = "songs"
) -> NSAppleEventDescriptor {
    let list = NSAppleEventDescriptor.list()
    let items: [NSAppleEventDescriptor] = [
        .init(string: state), .init(string: "AC4FFD2271422B47"), .init(string: "Forever"),
        .init(string: "HAIM"), .init(string: "Days Are Gone"), .init(int32: year),
        .init(int32: volume), .init(boolean: muted), .init(string: repeatMode),
        .init(boolean: shuffleEnabled), .init(string: shuffleMode), .init(string: playlist),
    ]
    for (i, item) in items.enumerated() { list.insert(item, at: i + 1) }
    return list
}

private func json(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: - parameterize

@Suite struct ParameterizeTests {
    @Test(arguments: [
        ("Outkast: The '90s", "outkast-the-90s"),
        ("Music Videos", "music-videos"),
        ("  Rock & Roll!! ", "rock-roll"),
        ("Café Del Mar", "cafe-del-mar"),
        ("2000s Hits Essentials", "2000s-hits-essentials"),
        ("", ""),
    ])
    func producesPlaylistIDs(name: String, expected: String) {
        #expect(parameterize(name) == expected)
    }
}

@Suite struct PlaylistIDTests {
    @Test func uniqueNamesGetPlainIDs() {
        let ids = playlistIDs(names: ["Chill", "Get Up"], persistentIDs: ["AAAA", "BBBB"])
        #expect(ids == ["chill", "get-up"])
    }

    @Test func firstDuplicateKeepsThePlainID() {
        let ids = playlistIDs(names: ["Music Videos", "Music Videos"], persistentIDs: ["C0FFEE0011223344", "ABCDEF5566778899"])
        #expect(ids[0] == "music-videos")
        #expect(ids[1] == "music-videos-778899")
    }

    @Test func suffixesDontDependOnOrder() {
        // Reordering must not change a playlist's suffixed id.
        let a = playlistIDs(names: ["X", "X"], persistentIDs: ["1111111111AAAAAA", "2222222222BBBBBB"])
        let b = playlistIDs(names: ["X", "X"], persistentIDs: ["2222222222BBBBBB", "1111111111AAAAAA"])
        #expect(a[1] == "x-bbbbbb")
        #expect(b[1] == "x-aaaaaa")
    }

    @Test func threeWayDuplicatesAllDiffer() {
        let ids = playlistIDs(names: ["X", "X", "X"], persistentIDs: ["AA000001", "AA000002", "AA000003"])
        #expect(Set(ids).count == 3)
    }

    @Test func nameWithNoLettersFallsBackToPersistentID() {
        let ids = playlistIDs(names: ["!!!"], persistentIDs: ["ABCDEF0123456789"])
        #expect(ids == ["abcdef0123456789"])
    }
}

// MARK: - Request parsing

@Suite struct FormTests {
    @Test func parsesBodyFields() {
        #expect(parseForm("level=20&mode=songs") == ["level": "20", "mode": "songs"])
    }

    @Test func decodesPercentEscapesAndPlus() {
        #expect(parseForm("name=a%20b+c") == ["name": "a b c"])
    }

    @Test func bodyWinsOverQuery() {
        let values = requestValues(body: "level=20", query: "level=99&mode=off")
        #expect(values == ["level": "20", "mode": "off"])
    }

    @Test func emptyInputGivesNoValues() {
        #expect(requestValues(body: "", query: nil).isEmpty)
    }

    @Test(arguments: [("true", true), ("1", true), ("ON", true), ("false", false), ("off", false)])
    func parsesBooleans(text: String, expected: Bool) {
        #expect(parseBool(text) == expected)
    }

    @Test func rejectsUnknownBooleans() {
        #expect(parseBool("maybe") == nil)
        #expect(parseBool(nil) == nil)
    }
}

// MARK: - /now_playing response

@Suite struct NowPlayingTests {
    // Home Assistant only treats shuffle as on when this is the string "songs".
    @Test func shuffleIsTheModeStringWhenOn() throws {
        let np = NowPlaying(descriptor: playingList(), emulatedMuteVolume: nil)
        #expect(try json(np)["shuffle"] as? String == "songs")
    }

    @Test func shuffleIsFalseWhenOff() throws {
        let np = NowPlaying(descriptor: playingList(shuffleEnabled: false), emulatedMuteVolume: nil)
        #expect(try json(np)["shuffle"] as? Bool == false)
    }

    @Test func albumIsTheNameAloneWithTheYearSeparate() throws {
        let np = NowPlaying(descriptor: playingList(), emulatedMuteVolume: nil)
        #expect(np.album == "Days Are Gone")
        #expect(try json(np)["year"] as? Int == 2013)
    }

    @Test func omitsYearWhenZero() throws {
        let np = NowPlaying(descriptor: playingList(year: 0), emulatedMuteVolume: nil)
        #expect(np.album == "Days Are Gone")
        #expect(try json(np)["year"] == nil)
    }

    @Test(arguments: ["Music", "Library"])
    func blanksTheDefaultPlaylists(name: String) {
        let np = NowPlaying(descriptor: playingList(playlist: name), emulatedMuteVolume: nil)
        #expect(np.playlist == "")
    }

    @Test func keepsOtherPlaylistNames() {
        let np = NowPlaying(descriptor: playingList(), emulatedMuteVolume: nil)
        #expect(np.playlist == "Summer Jams")
    }

    @Test func stoppedPlayerHasOnlyAState() throws {
        let list = NSAppleEventDescriptor.list()
        list.insert(.init(string: "stopped"), at: 1)
        let object = try json(NowPlaying(descriptor: list, emulatedMuteVolume: nil))
        #expect(object["player_state"] as? String == "stopped")
        #expect(object.count == 1)
    }

    @Test func emulatedMuteReportsMutedAndTheRealVolume() {
        // While muted we've set Music's volume to 0, but clients should still see the user's volume.
        let np = NowPlaying(descriptor: playingList(volume: 0), emulatedMuteVolume: 60)
        #expect(np.muted == true)
        #expect(np.volume == 60)
    }

    @Test func notMutedByDefault() {
        let np = NowPlaying(descriptor: playingList(), emulatedMuteVolume: nil)
        #expect(np.muted == false)
        #expect(np.volume == 60)
    }
}

// MARK: - Command validation (rejected before Music is contacted)

@Suite struct CommandValidationTests {
    @Test func rejectsUnknownShuffleModes() async {
        await #expect(throws: CommandError.self) { try await MusicScript().setShuffle("bogus") }
    }

    @Test func rejectsUnknownRepeatModes() async {
        await #expect(throws: CommandError.self) { try await MusicScript().setRepeat("bogus") }
    }
}

// MARK: - Artwork search fallback

@Suite struct ArtworkSearchTests {
    private let track = TrackIdentity(persistentID: "ID", name: "Headlights", artist: "Moyka", album: "BULLSEYE")

    private func result(_ artist: String, _ name: String, _ album: String, _ url: String = "https://is1-ssl.mzstatic.com/a/100x100bb.jpg") -> ArtworkSearch.Result {
        .init(artistName: artist, trackName: name, collectionName: album, artworkUrl100: url)
    }

    @Test func prefersTheMatchingAlbum() {
        let results = [
            result("Moyka", "Headlights", "Ultraviolet - Single", "https://is1-ssl.mzstatic.com/single/100x100bb.jpg"),
            result("Moyka", "Headlights", "BULLSEYE", "https://is1-ssl.mzstatic.com/bullseye/100x100bb.jpg"),
        ]
        #expect(ArtworkSearch.bestArtworkURL(in: results, for: track)?.absoluteString == "https://is1-ssl.mzstatic.com/bullseye/600x600bb.jpg")
    }

    @Test func fallsBackToTheFirstMatchingTrack() {
        let results = [result("Moyka", "Headlights", "Some Compilation", "https://is1-ssl.mzstatic.com/comp/100x100bb.jpg")]
        #expect(ArtworkSearch.bestArtworkURL(in: results, for: track)?.absoluteString == "https://is1-ssl.mzstatic.com/comp/600x600bb.jpg")
    }

    @Test func ignoresDifferentTracksAndArtists() {
        let results = [result("Someone Else", "Headlights", "BULLSEYE"), result("Moyka", "Other Song", "BULLSEYE")]
        #expect(ArtworkSearch.bestArtworkURL(in: results, for: track) == nil)
    }

    @Test func matchesCaseInsensitively() {
        let results = [result("MOYKA", "headlights", "bullseye")]
        #expect(ArtworkSearch.bestArtworkURL(in: results, for: track) != nil)
    }

    @Test func searchURLEncodesTheTrack() throws {
        let url = try #require(ArtworkSearch.searchURL(for: TrackIdentity(persistentID: "ID", name: "Rock & Roll", artist: "A B", album: "C")))
        #expect(url.absoluteString.hasPrefix("https://itunes.apple.com/search?"))
        #expect(!url.absoluteString.contains(" "))
        #expect(url.absoluteString.contains("Rock%20%26%20Roll"))
    }

    @Test func searchURLKeepsPlusSigns() throws {
        let url = try #require(ArtworkSearch.searchURL(for: TrackIdentity(persistentID: "ID", name: "Song", artist: "Florence + the Machine", album: "A")))
        #expect(url.absoluteString.contains("Florence%20%2B%20the%20Machine"))
    }

    @Test func searchURLCapsLongMetadata() throws {
        let long = String(repeating: "a", count: 5000)
        let url = try #require(ArtworkSearch.searchURL(for: TrackIdentity(persistentID: "ID", name: long, artist: long, album: long)))
        #expect(url.absoluteString.count < 1000)
    }

    @Test(arguments: [
        "https://is1-ssl.mzstatic.com/image/a.jpg",
        "https://mzstatic.com/a.jpg",
        "https://music.apple.com/a.jpg",
    ])
    func allowsAppleImageHosts(link: String) throws {
        #expect(ArtworkSearch.isSafeArtworkURL(try #require(URL(string: link))))
    }

    @Test(arguments: [
        "http://is1-ssl.mzstatic.com/a.jpg",
        "file:///etc/passwd",
        "https://evil.example/a.jpg",
        "https://evilmzstatic.com/a.jpg",
        "https://mzstatic.com.evil.example/a.jpg",
    ])
    func rejectsOtherHostsAndSchemes(link: String) throws {
        #expect(!ArtworkSearch.isSafeArtworkURL(try #require(URL(string: link))))
    }

    @Test func unsafeResultsAreNotFollowed() {
        let track = TrackIdentity(persistentID: "ID", name: "S", artist: "A", album: "B")
        let results = [ArtworkSearch.Result(artistName: "A", trackName: "S", collectionName: "B", artworkUrl100: "https://evil.example/100x100bb.jpg")]
        #expect(ArtworkSearch.bestArtworkURL(in: results, for: track) == nil)
    }

    @Test func sniffsImageTypes() {
        #expect(ArtworkSearch.contentType(for: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
        #expect(ArtworkSearch.contentType(for: Data([0x89, 0x50, 0x4E, 0x47])) == "image/png")
    }
}
