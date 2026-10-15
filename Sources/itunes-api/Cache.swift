import Foundation

/// Short-lived cache for /now_playing so frequent polling doesn't hammer Music.
/// Concurrent requests share one in-flight lookup; any command invalidates it.
actor NowPlayingCache {
    private let music: MusicScript
    private let ttl: Duration
    private var value: NowPlaying?
    private var fetchedAt: ContinuousClock.Instant?
    private var inflight: Task<NowPlaying, Error>?

    init(music: MusicScript, ttl: Duration = .seconds(1)) {
        self.music = music
        self.ttl = ttl
    }

    func get() async throws -> NowPlaying {
        if let value, let fetchedAt, ContinuousClock.now - fetchedAt < ttl { return value }
        if let inflight { return try await inflight.value }

        let music = self.music
        let task = Task { try await music.nowPlaying() }
        inflight = task
        defer { inflight = nil }
        let fresh = try await task.value
        value = fresh
        fetchedAt = .now
        return fresh
    }

    func invalidate() {
        value = nil
        fetchedAt = nil
    }
}
