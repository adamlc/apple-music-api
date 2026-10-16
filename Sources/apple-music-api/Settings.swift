import Foundation

enum Settings {
    /// Same default as Home Assistant's iTunes integration and the original itunes-api.
    static let defaultPort = 8181
    static let validPorts = 1024...65535
    private static let portKey = "port"

    /// The `PORT` environment variable (an explicit override, handy for running a second copy),
    /// else the port saved from the menu bar, else the default.
    static var port: Int {
        get {
            if let env = ProcessInfo.processInfo.environment["PORT"].flatMap({ Int($0) }) { return env }
            let saved = UserDefaults.standard.integer(forKey: portKey)
            return validPorts.contains(saved) ? saved : defaultPort
        }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }
}
