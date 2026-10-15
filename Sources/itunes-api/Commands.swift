import Foundation

enum CommandError: Error { case badRequest(String) }

extension MusicScript {
    /// Run one or more statements inside `tell application "Music"`.
    @discardableResult
    func tell(_ statements: String) async throws -> NSAppleEventDescriptor {
        try await run("tell application \"Music\"\n\(statements)\nend tell")
    }

    func play() async throws { try await tell("play") }
    func pause() async throws { try await tell("pause") }
    func playPause() async throws { try await tell("playpause") }
    func stop() async throws { try await tell("stop") }
    func previous() async throws { try await tell("previous track") }
    func next() async throws { try await tell("next track") }

    func setVolume(_ level: Int) async throws {
        try await tell("set sound volume to \(min(max(level, 0), 100))")
    }

    func setMuted(_ muted: Bool) async throws {
        try await tell("set mute to \(muted)")
    }

    /// `mode` is "songs", "albums", "groupings", or "off"/"false" to disable.
    func setShuffle(_ mode: String) async throws {
        if ["off", "false"].contains(mode) {
            try await tell("set shuffle enabled to false")
        } else if ["songs", "albums", "groupings"].contains(mode) {
            try await tell("set shuffle enabled to true\nset shuffle mode to \(mode)")
        } else {
            throw CommandError.badRequest("shuffle mode must be songs, albums, groupings or off")
        }
    }

    /// `mode` is "all", "one", or "off"/"false" to disable.
    func setRepeat(_ mode: String) async throws {
        let value = mode == "false" ? "off" : mode
        guard ["off", "one", "all"].contains(value) else {
            throw CommandError.badRequest("repeat mode must be all, one or off")
        }
        try await tell("set song repeat to \(value)")
    }
}
