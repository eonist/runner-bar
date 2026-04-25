import AppKit
import SwiftUI

// ============================================================
// ⚠️  WARNING — POPOVER SIZING CONTRACT — READ BEFORE EDITING
// ============================================================
// VERSION: v1.5
//
// NSPopover re-anchors its FULL screen position (X and Y) any time
// contentSize changes — even by 1pt, even height-only changes.
// There is NO AppKit API to update height without triggering a re-anchor.
//
// TWO INDEPENDENT CAUSES OF LEFT-JUMP — both must be fixed simultaneously:
//
// CAUSE 1 — SwiftUI frame contract (PopoverView / child views):
//   - Root Group must use .frame(idealWidth: 340) NOT .frame(width: 340)
//   - Child nav views must use .frame(maxWidth: .infinity, ...) NOT width: 340
//   - See PopoverView.swift for full contract details
//
// CAUSE 2 — observable.reload() while popover is open (THIS FILE):
//   - Every poll cycle: RunnerStore.onChange => observable.reload()
//     => SwiftUI re-render => preferredContentSize changes (even 1pt)
//     => NSPopover re-anchors screen X position => left jump
//   - FIX: only call observable.reload() when popover is NOT shown
//   - On popover close: always do a final reload() so data is fresh on reopen
//
// ⚠️  THINGS THAT WILL CAUSE LEFT-JUMP REGRESSION:
//   ✗ Calling observable.reload() unconditionally in onChange
//   ✗ Setting popover.contentSize anywhere (even once at startup)
//   ✗ Removing or changing hc.sizingOptions
//   ✗ Adding KVO on preferredContentSize to manually update contentSize
//   ✗ Changing .frame(idealWidth:) to .frame(width:) in PopoverView
//   ✗ Using .frame(width: 340) in any child nav view (JobStepsView etc.)
//
// ⚠️  THINGS THAT WILL CAUSE EMPTY-SPACE REGRESSION:
//   ✗ Removing .fixedSize(horizontal:false, vertical:true) from jobListView
//   ✗ Changing .frame(maxHeight: 480) to .frame(height: 480) on jobListView
//   ✗ Wrapping jobListView in a ScrollView
//
// This regression has been introduced and "fixed" 20+ times in one day.
// See GitHub issues #53, #54, #58 before touching any of this.
// ============================================================

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<PopoverView>?
    private let observable = RunnerStoreObservable()

    // Track whether the popover is currently visible.
    // Used to suppress observable.reload() while open — see CAUSE 2 above.
    private var popoverIsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("AppDelegate > applicationDidFinishLaunching")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hc = NSHostingController(rootView: PopoverView(store: observable))
        // ⚠️ DO NOT remove or change this line. See contract at top of file.
        // sizingOptions = .preferredContentSize + .frame(idealWidth:340) in PopoverView
        // together keep preferredContentSize.width locked at 340 across all nav states.
        hc.sizingOptions = .preferredContentSize
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentViewController = hc
        popover.delegate              = self
        // ⚠️ DO NOT set popover.contentSize here or anywhere else.
        // Any manual write to contentSize causes a full NSPopover re-anchor => left jump.
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            log("AppDelegate > onChange - refreshing status icon")
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)

            // ⚠️ CAUSE 2 FIX: only reload observable when popover is NOT open.
            // Calling reload() while popover is visible triggers a SwiftUI re-render
            // which changes preferredContentSize which causes NSPopover to re-anchor
            // its full screen position => left jump.
            // When closed: reload freely so data is always fresh on next open.
            if !self.popoverIsOpen {
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
            log("AppDelegate > opening popover")
            // Always do a fresh reload before showing, so data is current.
            observable.reload()
            popoverIsOpen = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        log("AppDelegate > popover closed - reloading observable")
        popoverIsOpen = false
        // Final reload so next open shows fresh data immediately.
        observable.reload()
    }
}
