import Foundation

enum Settings {
    static let defaultPort = 10100
    static let validPorts = 1024...65535
    private static let portKey = "port"

    /// Port saved from the menu bar, else the `PORT` environment variable, else the default.
    static var port: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: portKey)
            if validPorts.contains(saved) { return saved }
            if let env = ProcessInfo.processInfo.environment["PORT"].flatMap({ Int($0) }) { return env }
            return defaultPort
        }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }
}
