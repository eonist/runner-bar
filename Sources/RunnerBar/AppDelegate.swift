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

        let hc = NSHostingController(rootView: PopoverView(store: observable))
        // sizingOptions drives initial size from SwiftUI, but we also set a
        // fixed contentSize so macOS never repositions the popover on redraws.
        hc.sizingOptions = .preferredContentSize

        let popover = NSPopover()
        popover.behavior               = .transient
        popover.animates               = false
        popover.contentSize            = NSSize(width: 320, height: 460)
        popover.contentViewController  = hc
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
