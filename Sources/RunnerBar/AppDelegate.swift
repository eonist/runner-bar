import AppKit
import SwiftUI

// ============================================================
// ⚠️⚠️⚠️  STOP. READ THIS ENTIRE COMMENT BEFORE TOUCHING THIS FILE.  ⚠️⚠️⚠️
// ============================================================
// VERSION: v2.0
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
// SECTION 2: ALL 7 ROOT CAUSES OF LEFT-JUMP (ALL must be fixed)
// ============================================================
//
// CAUSE 1 — Wrong SwiftUI frame modifier on root or child views
//   Location: PopoverView.swift, JobStepsView.swift, MatrixGroupView.swift
//   Fix: .frame(idealWidth: 340) on root Group only.
//        .frame(maxWidth: .infinity, ...) on all child nav views.
//
// CAUSE 2 — Calling observable.reload() while the popover is open
//   Location: onChange handler
//   Fix: Guard with `if !self.popoverIsOpen`.
//
// CAUSE 3 — Calling observable.reload() from popoverDidClose
//   Fix: NEVER call reload() from popoverDidClose. Not ever.
//
// CAUSE 4 — popoverIsOpen flag set AFTER reload() in togglePopover
//   Fix: Set popoverIsOpen = true FIRST, then reload(), then show().
//   DO NOT REORDER THESE.
//
// CAUSE 5 — Multiple objectWillChange publishes per reload()
//   Fix: Single @Published StoreState struct in RunnerStoreObservable.
//   ONE assignment = ONE publish = ONE render.
//
// CAUSE 6 — onChange-triggered reload races with togglePopover
//   Fix: Defer show() with DispatchQueue.main.async.
//   Lets in-flight publishes drain before show() runs.
//
// CAUSE 7 — Async step load in JobStepsView fires @State change after appear
//   Location: JobStepsView.swift (v1.7-v1.9 had loadSteps() in .onAppear)
//   What happens: Steps fetched async inside JobStepsView. Result arrives
//   ~2 seconds after appear, setting @State isLoading=false and steps=result.
//   @State changes => SwiftUI re-render => preferredContentSize recalc
//   => NSPopover re-anchors => left jump ~2 seconds after tapping a job row.
//   Fix: Steps are now fetched in PopoverView.loadStepsAndNavigate() BEFORE
//   setting navState. JobStepsView receives steps as a constructor parameter
//   and renders immediately. No async load = no @State change after appear
//   = no re-render = no jump.
//   See: JobStepsView.swift CAUSE 7 section, PopoverView.swift groupRow section.
//
// ============================================================
// SECTION 3: COMPLETE FORBIDDEN ACTIONS LIST
// ============================================================
//
//   ✘ Call observable.reload() unconditionally in onChange
//       => CAUSE 2
//
//   ✘ Call observable.reload() from popoverDidClose
//       => CAUSE 3
//
//   ✘ Set popoverIsOpen = true AFTER reload() in togglePopover
//       => CAUSE 4
//
//   ✘ Split StoreState back into separate @Published properties
//       => CAUSE 5
//
//   ✘ Add objectWillChange.send() anywhere in RunnerStoreObservable
//       => Extra publish => extra re-render => re-anchor
//
//   ✘ Move show() outside the DispatchQueue.main.async block
//       => CAUSE 6
//
//   ✘ Load steps async inside JobStepsView (navigate-then-load pattern)
//       => CAUSE 7: @State change ~2s after appear => re-render => jump
//
//   ✘ Set popover.contentSize anywhere
//       => NSPopover immediately re-anchors
//
//   ✘ Remove hc.sizingOptions = .preferredContentSize
//       => Wrong size entirely
//
//   ✘ Add KVO observer on preferredContentSize
//       => Feedback loop => jump
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
//   ✔ Defer show() with DispatchQueue.main.async
//   ✔ Set popoverIsOpen = false in popoverDidClose
//   ✔ Fetch steps on background thread then navigate (loadStepsAndNavigate)
//   ✔ Read popover.isShown freely
//   ✔ Call popover.performClose()
//
// ============================================================
// SECTION 5: HOW TO VERIFY THE FIX IS STILL WORKING
// ============================================================
//
// Test 1 — Open with no active jobs. Popover MUST NOT jump.
// Test 2 — Close. Wait for job to appear. Reopen.
//          Popover MUST NOT jump or immediately close.
// Test 3 — Open and leave open for 30+ seconds.
//          Popover MUST NOT jump while open.
// Test 4 — Rapidly open/close 10 times.
//          Must open stably every time.
// Test 5 — Tap a job row to navigate to steps view.
//          Popover MUST NOT jump during or after navigation.
//          There will be a brief pause (fetch time) before navigation.
//          That is expected and correct.
// Test 6 — Navigate to steps view, wait 5+ seconds.
//          Popover MUST NOT jump while on steps view.
//
// ============================================================

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<PopoverView>?
    private let observable = RunnerStoreObservable()

    // ⚠️ CRITICAL FLAG — CAUSE 2, CAUSE 4, CAUSE 6.
    // MUST be set to true BEFORE reload() in togglePopover.
    // MUST be set to false in popoverDidClose.
    // DO NOT use popover.isShown — unreliable during transitions.
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
        // ⚠️ DO NOT REMOVE. preferredContentSize + idealWidth:340 lock width=340.
        hc.sizingOptions = .preferredContentSize
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentViewController = hc
        popover.delegate              = self
        // ⚠️ DO NOT set popover.contentSize. Re-anchors on every write.
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            log("AppDelegate > onChange - refreshing status icon")
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)

            // ⚠️ CAUSE 2 FIX. DO NOT REMOVE GUARD.
            // reload() while open => re-render => re-anchor => jump.
            // ⚠️ CAUSE 6 NOTE: reload() here while closed queues a publish.
            // That publish drains before show() due to DispatchQueue.main.async
            // in togglePopover. DO NOT move show() out of the async block.
            if !self.popoverIsOpen {
                self.observable.reload()
            }
        }

        RunnerStore.shared.start()
    }

    // ⚠️⚠️⚠️  ORDER IS NOT NEGOTIABLE. SEE CAUSES 4 AND 6.  ⚠️⚠️⚠️
    @objc private func togglePopover() {
        guard let button = statusItem?.button,
              button.window != nil,
              let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            log("AppDelegate > opening popover")

            // STEP 1: Arm guard FIRST (CAUSE 4 fix).
            popoverIsOpen = true

            // STEP 2: Snapshot data. Fires ONE publish (StoreState). (CAUSE 5 fix)
            observable.reload()

            // STEP 3: Defer show to next runloop tick.
            // Gives any in-flight onChange-triggered publish time to drain.
            // (CAUSE 6 fix) DO NOT move show() outside this async block.
            DispatchQueue.main.async { [weak self] in
                guard let self, let popover = self.popover,
                      let button = self.statusItem?.button else { return }
                guard !popover.isShown else { return }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        log("AppDelegate > popoverDidClose")
        popoverIsOpen = false
        // ⚠️⚠️⚠️  DO NOT ADD reload() HERE. CAUSE 3.  ⚠️⚠️⚠️
    }
}
