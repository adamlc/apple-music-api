import Foundation

struct AirPlayDevice: Codable {
    var id: String
    var name: String
    var kind: String
    var active: Bool
    var selected: Bool
    var sound_volume: Int
    var supports_video: Bool
    var supports_audio: Bool
    var network_address: String?
}

private let listScript = """
tell application "Music"
    set out to {}
    repeat with d in every AirPlay device
        set addr to missing value
        try
            set addr to network address of d
        end try
        set end of out to {addr, name of d, kind of d as text, active of d, selected of d, sound volume of d, supports video of d, supports audio of d}
    end repeat
    return out
end tell
"""

extension MusicScript {
    func airPlayDevices() async throws -> [AirPlayDevice] {
        let d = try await run(listScript)
        return (0..<d.numberOfItems).compactMap { i in
            guard let row = d.atIndex(i + 1), row.numberOfItems == 8 else { return nil }
            let address = row.atIndex(1)?.stringValue
            let name = row.atIndex(2)?.stringValue ?? ""
            return AirPlayDevice(
                id: address.map { $0.replacingOccurrences(of: ":", with: "-") } ?? name,
                name: name,
                kind: row.atIndex(3)?.stringValue ?? "",
                active: row.atIndex(4)?.booleanValue ?? false,
                selected: row.atIndex(5)?.booleanValue ?? false,
                sound_volume: Int(row.atIndex(6)?.int32Value ?? 0),
                supports_video: row.atIndex(7)?.booleanValue ?? false,
                supports_audio: row.atIndex(8)?.booleanValue ?? false,
                network_address: address
            )
        }
    }

    func airPlayDevice(id: String) async throws -> AirPlayDevice? {
        try await airPlayDevices().first { $0.id == id }
    }

    /// Applies `property` ("selected" or "sound volume") to the device, then returns its new state.
    private func updateAirPlayDevice(id: String, property: String, value: String) async throws -> AirPlayDevice? {
        let devices = try await airPlayDevices()
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return nil }
        try await tell("set \(property) of AirPlay device \(index + 1) to \(value)")
        // Music reorders the list when a device is selected, so look it up by id again.
        return try await airPlayDevice(id: id)
    }

    func setAirPlayDevice(id: String, selected: Bool) async throws -> AirPlayDevice? {
        try await updateAirPlayDevice(id: id, property: "selected", value: "\(selected)")
    }

    func setAirPlayDevice(id: String, volume: Int) async throws -> AirPlayDevice? {
        try await updateAirPlayDevice(id: id, property: "sound volume", value: "\(min(max(volume, 0), 100))")
    }
}
