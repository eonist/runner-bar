import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let observable = RunnerStoreObservable()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("AppDelegate › applicationDidFinishLaunching")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // sizingOptions = .preferredContentSize causes the popover to jump left
        // whenever SwiftUI recomputes its size on data updates. Omitting it lets
        // the popover stay anchored to the status item. .fixedSize() in PopoverView
        // handles intrinsic sizing correctly.
        let hc = NSHostingController(rootView: PopoverView(store: observable))

        let popover = NSPopover()
        popover.behavior    = .transient
        popover.animates    = false
        popover.contentViewController = hc
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            log("AppDelegate › onChange — refreshing status icon")
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)
            self.observable.reload()
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
            log("AppDelegate › opening popover")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }
}
