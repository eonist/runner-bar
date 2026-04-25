import AppKit
import SwiftUI

// ============================================================
// ⚠️⚠️⚠️  STOP. READ THIS ENTIRE COMMENT BEFORE TOUCHING THIS FILE.  ⚠️⚠️⚠️
// ============================================================
// VERSION: v1.8
//
// This file controls a brutally fragile relationship between SwiftUI,
// NSHostingController, and NSPopover. The symptom when broken is that
// the popover flies to the far left of the screen every time it opens
// or every time the background poll fires. It looks like a trivial
// layout bug. It is NOT. It took 30+ attempts across a single day to
// fully identify all root causes.
//
// If you are an AI assistant or a future developer reading this:
// DO NOT "simplify" this code. DO NOT "clean it up". DO NOT move
// lines around. DO NOT remove comments. Every single constraint here
// exists because its absence caused a regression that was extremely
// hard to diagnose and fix.
//
// ============================================================
// SECTION 1: HOW NSPopover SIZING ACTUALLY WORKS
// ============================================================
//
// NSPopover does NOT size itself from contentViewController.view.frame.
// It sizes itself from contentViewController.preferredContentSize.
//
// NSHostingController (which IS our contentViewController) automatically
// updates preferredContentSize from the SwiftUI view's IDEAL size when
// sizingOptions = .preferredContentSize.
//
// KEY INSIGHT: ANY change to preferredContentSize — even 1 point, even
// height-only changes — causes NSPopover to re-anchor its FULL screen
// position (both X and Y). There is NO AppKit API to change height
// without triggering a position re-anchor. This is undocumented AppKit
// behavior discovered through painful trial and error.
//
// The re-anchor recalculates where the arrow should point on the status
// bar button. Since the status bar button is on the RIGHT side of the
// screen, a wrong preferredContentSize.width places the popover's LEFT
// edge far to the LEFT of the screen. This is the "left jump" symptom.
//
// ============================================================
// SECTION 2: ALL 5 ROOT CAUSES OF LEFT-JUMP (ALL must be fixed)
// ============================================================
//
// CAUSE 1 — Wrong SwiftUI frame modifier on root or child views
//   Location: PopoverView.swift, JobStepsView.swift, MatrixGroupView.swift
//   What happens: .frame(width: 340) in any view overrides the ideal
//   width computation. When SwiftUI navigates between states, the
//   preferredContentSize.width fluctuates => NSPopover re-anchors.
//   Fix: .frame(idealWidth: 340) on root Group only.
//        .frame(maxWidth: .infinity, ...) on all child nav views.
//   See: PopoverView.swift SECTION 1 for full frame contract.
//
// CAUSE 2 — Calling observable.reload() while the popover is open
//   Location: onChange handler in this file
//   What happens: The background RunnerStore poll fires every ~10s.
//   Each poll calls onChange => observable.reload() => objectWillChange
//   => SwiftUI re-renders => preferredContentSize changes => re-anchor
//   => popover jumps left while the user is looking at it.
//   Fix: Guard with `if !self.popoverIsOpen`.
//
// CAUSE 3 — Calling observable.reload() from popoverDidClose
//   Location: popoverDidClose in this file
//   What happens: reload() fires objectWillChange. NSPopover with
//   behavior = .transient treats this as an outside-click and immediately
//   re-closes — creating a rapid open/close/open/close thrash loop.
//   Fix: NEVER call reload() from popoverDidClose. Not ever.
//
// CAUSE 4 — popoverIsOpen flag set AFTER reload() in togglePopover
//   Location: togglePopover in this file
//   What happens: reload() fires objectWillChange synchronously.
//   SwiftUI schedules the re-render for the next runloop tick.
//   If popoverIsOpen is still false when that re-render fires (because
//   it was set AFTER reload()), the CAUSE 2 guard doesn't block it.
//   The re-render changes preferredContentSize AFTER show() => jump.
//   Fix: Set popoverIsOpen = true FIRST, then reload(), then show().
//   DO NOT REORDER THESE THREE LINES.
//
// CAUSE 5 — Triple objectWillChange publish from reload()
//   Location: RunnerStoreObservable.reload() in PopoverView.swift
//   What happens: The original reload() was:
//     runners = ...  => @Published fires objectWillChange (1)
//     jobs = ...     => @Published fires objectWillChange (2)
//     objectWillChange.send()  => explicit fires (3)  ← THE BUG
//   Three publishes = three re-renders queued on the runloop.
//   Even with CAUSE 4 fixed, these three re-renders race against show().
//   The first render sees stale data (0 jobs), subsequent renders see
//   fresh data (1 job). These have DIFFERENT heights. Each re-render
//   changes preferredContentSize => re-anchor => left jump on 2nd open.
//   Fix: Remove the explicit objectWillChange.send() from reload().
//        Wrap assignments in withAnimation(nil) to coalesce into 1 pass.
//   See: RunnerStoreObservable in PopoverView.swift for details.
//
// ============================================================
// SECTION 3: COMPLETE FORBIDDEN ACTIONS LIST
// ============================================================
//
//   ✘ Call observable.reload() unconditionally in onChange
//       => CAUSE 2: jump every poll cycle while popover is open
//
//   ✘ Call observable.reload() from popoverDidClose
//       => CAUSE 3: open/close thrash loop on every click
//
//   ✘ Set popoverIsOpen = true AFTER reload() in togglePopover
//       => CAUSE 4: jump on first open due to runloop race
//
//   ✘ Add objectWillChange.send() to RunnerStoreObservable.reload()
//       => CAUSE 5: triple publish => triple re-render => jump on 2nd open
//
//   ✘ Set popover.contentSize anywhere in this file or any other
//       => NSPopover immediately re-anchors => left jump
//
//   ✘ Remove hc.sizingOptions = .preferredContentSize
//       => NSHostingController stops syncing => wrong size entirely
//
//   ✘ Add KVO observer on preferredContentSize
//       => Feedback loop: size change => KVO => set contentSize => re-anchor
//
//   ✘ Change popover.animates = false to true
//       => Animation interpolates contentSize => re-anchor every frame
//
// ============================================================
// SECTION 4: WHAT IS ALLOWED
// ============================================================
//
//   ✔ Update statusItem button image in onChange (no size impact)
//   ✔ Call reload() inside togglePopover AFTER popoverIsOpen = true
//   ✔ Set popoverIsOpen = false in popoverDidClose (flag only, no reload)
//   ✔ Read popover.isShown freely
//   ✔ Call popover.performClose()
//
// ============================================================
// SECTION 5: HOW TO VERIFY THE FIX IS STILL WORKING
// ============================================================
//
// 1. Run with no active jobs. Open popover. Must NOT jump.
// 2. Close it. Wait for a job to appear (poll cycle). Reopen.
//    => Must NOT jump even though content changed (0 jobs -> 1 job).
// 3. Open and leave open for 30+ seconds (3+ poll cycles).
//    => Must NOT jump while open.
// 4. Rapidly open/close 10 times.
//    => Must open stably every time. No thrash.
// 5. Navigate to JobStepsView and back.
//    => Width must stay 340pt. No jump.
//
// ============================================================

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<PopoverView>?
    private let observable = RunnerStoreObservable()

    // ⚠️ CRITICAL FLAG — participates in CAUSE 2 and CAUSE 4 fixes.
    // MUST be set to true BEFORE calling observable.reload() in togglePopover.
    // MUST be set to false in popoverDidClose.
    // DO NOT use popover.isShown as a substitute — it is unreliable during
    // the open/close transition. Use this flag exclusively.
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
        // ⚠️ DO NOT REMOVE OR CHANGE THIS LINE.
        // .preferredContentSize + .frame(idealWidth:340) in PopoverView
        // together lock preferredContentSize.width = 340 at all times.
        hc.sizingOptions = .preferredContentSize
        self.hc = hc

        let popover = NSPopover()
        // ⚠️ behavior = .transient is required for standard macOS menu-bar UX.
        // WARNING: .transient means objectWillChange publishes during close
        // can trigger auto-dismiss. This is why CAUSE 3 is so dangerous.
        popover.behavior              = .transient
        // ⚠️ animates = false prevents size-interpolation re-anchors during open.
        popover.animates              = false
        popover.contentViewController = hc
        popover.delegate              = self
        // ⚠️ DO NOT set popover.contentSize here or anywhere else.
        // Any write to contentSize triggers a full position re-anchor.
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            log("AppDelegate > onChange - refreshing status icon")
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)

            // ⚠️ CAUSE 2 FIX — DO NOT REMOVE THIS GUARD.
            // reload() while popover is open => re-render => preferredContentSize
            // changes => NSPopover re-anchors => left jump.
            // While closed: reload freely to keep data current.
            // DO NOT replace with `if !self.popover?.isShown ?? false`.
            // popover.isShown is unreliable during transitions.
            if !self.popoverIsOpen {
                self.observable.reload()
            }
        }

        RunnerStore.shared.start()
    }

    // ⚠️⚠️⚠️  THE ORDER OF OPERATIONS IN THIS METHOD IS NOT NEGOTIABLE  ⚠️⚠️⚠️
    // See SECTION 2 CAUSE 4 for full explanation.
    // The three lines inside `else` MUST stay in this exact order:
    //   1. popoverIsOpen = true
    //   2. observable.reload()
    //   3. popover.show(...)
    @objc private func togglePopover() {
        guard let button = statusItem?.button,
              button.window != nil,
              let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            log("AppDelegate > opening popover")

            // STEP 1: Arm the CAUSE 2 guard FIRST.
            // Any re-renders from reload() (step 2) that land after show() (step 3)
            // will be blocked by the !popoverIsOpen check in onChange.
            popoverIsOpen = true

            // STEP 2: Snapshot fresh data. Only valid here because step 1 is done.
            // ⚠️ reload() now fires objectWillChange ONCE (via @Published x2 coalesced
            // by withAnimation(nil)). It no longer fires 3x. See CAUSE 5.
            observable.reload()

            // STEP 3: Show the popover. Guard armed. Data fresh. Size stable.
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        log("AppDelegate > popoverDidClose")
        popoverIsOpen = false

        // ⚠️⚠️⚠️  DO NOT ADD observable.reload() HERE. EVER.  ⚠️⚠️⚠️
        // This is CAUSE 3. reload() => objectWillChange => NSPopover (.transient)
        // treats it as outside-click => immediately re-closes => thrash loop.
        // Data stays current via onChange. Fresh data is loaded in togglePopover.
    }
}
