import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<PopoverView>?
    private let observable = RunnerStoreObservable()
    private var sizeObserver: NSKeyValueObservation?

    static let popoverWidth: CGFloat = 340

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("AppDelegate > applicationDidFinishLaunching")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hc = NSHostingController(rootView: PopoverView(store: observable))
        // sizingOptions = [] means AppKit does NOT auto-resize the popover.
        // We drive height manually via KVO below, so width never changes.
        hc.sizingOptions = []
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentViewController = hc
        // Seed an initial size; height will be corrected by KVO before first show.
        popover.contentSize = NSSize(width: Self.popoverWidth, height: 480)
        self.popover = popover

        // KVO: whenever SwiftUI recalculates its ideal height, update ONLY the
        // popover height. Width is never touched, so the popover never jumps left.
        sizeObserver = hc.observe(\.preferredContentSize, options: [.new]) { [weak self] _, change in
            guard let self, let popover = self.popover,
                  let newSize = change.newValue else { return }
            let h = max(newSize.height, 1)
            if popover.contentSize.height != h {
                popover.contentSize = NSSize(width: Self.popoverWidth, height: h)
            }
        }

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            log("AppDelegate > onChange - refreshing status icon")
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
            log("AppDelegate > opening popover")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }
}
