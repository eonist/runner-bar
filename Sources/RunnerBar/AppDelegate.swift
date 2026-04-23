import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let observable = RunnerStoreObservable()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.title = "⚫"
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: observable))
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.statusItem?.button?.title = RunnerStore.shared.aggregateStatus.dot
                self.observable.reload()
            }
        }

        guard githubToken() != nil else {
            statusItem?.button?.title = "⚠️"
            return
        }

        if !ScopeStore.shared.isEmpty {
            RunnerStore.shared.start()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
