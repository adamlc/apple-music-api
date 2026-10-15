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
        mutedVolume.withLock { $0 = nil }
        try await tell("set sound volume to \(min(max(level, 0), 100))")
    }

    /// Music's `mute` property can't be set to true on current macOS versions (error 9038), so when
    /// that fails we emulate muting by dropping the volume to 0 and restoring it on unmute.
    func setMuted(_ muted: Bool) async throws {
        if muted {
            if mutedVolume.withLock({ $0 }) != nil { return }
            do {
                try await tell("set mute to true")
            } catch {
                let current = try await tell("return sound volume").int32Value
                mutedVolume.withLock { $0 = Int(current) }
                try await tell("set sound volume to 0")
            }
        } else {
            _ = try? await tell("set mute to false")
            if let restore = mutedVolume.withLock({ let v = $0; $0 = nil; return v }) {
                try await tell("set sound volume to \(restore)")
            }
        }
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
