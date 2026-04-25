import AppKit
import SwiftUI

// ============================================================
// ⚠️  WARNING — POPOVER SIZING CONTRACT — READ BEFORE EDITING
// ============================================================
// NSPopover re-anchors its FULL screen position (including X/horizontal)
// any time contentSize changes — even by 1pt, even height-only.
// There is NO AppKit API to update height without triggering a full re-anchor.
//
// THE CONTRACT (all three must be true simultaneously):
//   1. hc.sizingOptions = .preferredContentSize          ← MUST stay
//   2. popover.contentSize is NEVER set anywhere          ← MUST stay absent
//   3. PopoverView root Group has .frame(idealWidth: 340) ← MUST stay
//
// HOW IT WORKS:
//   sizingOptions = .preferredContentSize makes NSHostingController
//   publish SwiftUI's ideal size as preferredContentSize.
//   .frame(idealWidth: 340) on the root Group ensures
//   preferredContentSize.width is always exactly 340 across all nav states.
//   Height varies freely with content. NSPopover reads this and resizes
//   height-only => anchor never moves => NO LEFT JUMP.
//
// THINGS THAT WILL CAUSE THE LEFT-JUMP REGRESSION:
//   ✗ Setting popover.contentSize anywhere (even once at startup)
//   ✗ Removing or changing hc.sizingOptions
//   ✗ Adding KVO on preferredContentSize to update contentSize
//   ✗ Changing .frame(idealWidth:) to .frame(width:) in PopoverView
//
// This regression has been introduced and "fixed" 8+ times in one day.
// See GitHub issue #53 before touching any of this.
// ============================================================

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<PopoverView>?
    private let observable = RunnerStoreObservable()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("AppDelegate > applicationDidFinishLaunching")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hc = NSHostingController(rootView: PopoverView(store: observable))
        // ⚠️ DO NOT remove this line. See contract at top of file.
        // sizingOptions = .preferredContentSize makes NSHostingController track SwiftUI ideal size.
        // Combined with .frame(idealWidth: 340) in PopoverView, this keeps width always 340.
        hc.sizingOptions = .preferredContentSize
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentViewController = hc
        // ⚠️ DO NOT set popover.contentSize here or anywhere else.
        // preferredContentSize drives it. Any manual write causes a full re-anchor => left jump.
        self.popover = popover

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
