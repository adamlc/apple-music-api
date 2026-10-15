import AppKit

/// Menu bar icon so it's obvious the server is running, with a Quit item.
/// The app has no Dock icon (LSUIElement), so this is the only visible sign of it.
@MainActor
final class MenuBar: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(port: Int) {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Apple Music API")

        let menu = NSMenu()
        let title = NSMenuItem(title: "Apple Music API — port \(port)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
