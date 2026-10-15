import Foundation

extension MusicScript {
    /// Raw image bytes of the current track's first artwork, or nil if it has none.
    func artwork() async throws -> (data: Data, contentType: String)? {
        let d: NSAppleEventDescriptor
        do {
            d = try await tell("return data of artwork 1 of current track")
        } catch {
            return nil  // no current track, or no artwork
        }
        let data = d.data
        guard data.count > 8 else { return nil }
        return (data, Self.contentType(for: data))
    }

    private static func contentType(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        return "application/octet-stream"
    }
}
