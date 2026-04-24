import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let observable = RunnerStoreObservable()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hc = NSHostingController(rootView: PopoverView(store: observable))
        hc.sizingOptions = .preferredContentSize

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = hc
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)
                self.observable.reload()
            }
        }

        RunnerStore.shared.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button,
              button.window != nil,
              let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }
}
