import AppKit
import Foundation

struct MusicError: Error { let message: String }

/// Music isn't running, and the request wasn't one that should launch it.
struct MusicNotRunning: Error {}

/// Runs AppleScript against Music in-process. NSAppleScript isn't thread-safe,
/// so run it on the main thread (the Apple Event reply is delivered via the main run loop).
final class MusicScript: @unchecked Sendable {
    private let queue = DispatchQueue.main

    /// Volume to restore when unmuting, set only while mute is emulated (see `setMuted`).
    let mutedVolume = Locked<Int?>(nil)

    var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    /// Launches Music if needed and gives it time to finish starting up. Commands sent while it is
    /// still launching can be dropped or overridden when it restores its previous session.
    func ensureRunning() async throws {
        guard !isMusicRunning else { return }
        try await run("tell application \"Music\" to launch", launchIfNeeded: true)
        try await Task.sleep(for: .seconds(3))
    }

    /// Any `tell application "Music"` launches Music if it isn't running. So that polling doesn't
    /// keep reopening a Music the user has quit, only requests that opt in with `launchIfNeeded`
    /// (starting playback) are allowed to do that; the rest throw `MusicNotRunning`.
    func run(_ source: String, launchIfNeeded: Bool = false) async throws -> NSAppleEventDescriptor {
        if !launchIfNeeded && !isMusicRunning { throw MusicNotRunning() }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    return cont.resume(throwing: MusicError(message: "could not compile script"))
                }
                var err: NSDictionary?
                let result = script.executeAndReturnError(&err)
                if let err {
                    cont.resume(throwing: MusicError(message: "\(err)"))
                } else {
                    cont.resume(returning: result)
                }
            }
        }
    }
}

/// Minimal lock-protected value (Synchronization.Mutex needs macOS 15).
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
