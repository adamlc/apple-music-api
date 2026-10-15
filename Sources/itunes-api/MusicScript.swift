import Foundation

struct MusicError: Error { let message: String }

/// Runs AppleScript against Music in-process. NSAppleScript isn't thread-safe,
/// so run it on the main thread (the Apple Event reply is delivered via the main run loop).
final class MusicScript: @unchecked Sendable {
    private let queue = DispatchQueue.main

    func run(_ source: String) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { cont in
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
