import AppKit
import ServiceManagement

/// Menu bar icon so it's obvious the server is running. The app has no Dock icon (LSUIElement),
/// so this is its only visible presence: it shows the port and holds the settings and Quit.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let port: Int
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")

    init(port: Int) {
        self.port = port
        super.init()
        statusItem.button?.image = IconArtwork.menuBarGlyph()

        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Apple Music API", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let portItem = NSMenuItem(title: "Port: \(port)…", action: #selector(changePort), keyEquivalent: "")
        portItem.target = self
        menu.addItem(portItem)

        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // Re-read the login item state each time the menu opens, in case it was changed in System Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleStartAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Couldn't change Start at Login", detail: error.localizedDescription)
        }
        if SMAppService.mainApp.status == .requiresApproval {
            showAlert("Approval needed", detail: "Allow Apple Music API in System Settings → General → Login Items.")
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func changePort() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        field.stringValue = String(port)

        let alert = NSAlert()
        alert.messageText = "Change port"
        alert.informativeText = "Home Assistant must be set to the same port. The app restarts to apply it."
        alert.accessoryView = field
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let newPort = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), Settings.validPorts.contains(newPort) else {
            showAlert("Invalid port", detail: "Enter a number between \(Settings.validPorts.lowerBound) and \(Settings.validPorts.upperBound).")
            return
        }
        guard newPort != port else { return }

        Settings.port = newPort
        relaunch()
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else {
            showAlert("Port saved", detail: "Restart the server to use port \(Settings.port).")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.showAlert("Couldn't restart", detail: error.localizedDescription)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func showAlert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
