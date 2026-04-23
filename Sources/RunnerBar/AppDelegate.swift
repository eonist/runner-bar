import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.title = "⚫"
            button.action = #selector(showMenu)
            button.target = self
        }

        statusItem?.menu = buildMenu()
    }

    @objc private func showMenu() {
        statusItem?.button?.performClick(nil)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if githubToken() == nil {
            menu.addItem(NSMenuItem(title: "Run `gh auth login` in Terminal", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "RunnerBar v0.1", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}
