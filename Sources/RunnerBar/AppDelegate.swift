import AppKit
import SwiftUI

// ============================================================
// ⚠️⚠️⚠️  STOP. READ THIS ENTIRE COMMENT BEFORE TOUCHING THIS FILE.  ⚠️⚠️⚠️
// ============================================================
// VERSION: v2.3
//
// This file controls a brutally fragile relationship between SwiftUI,
// NSHostingController, and NSPopover. The symptom when broken is that
// the popover flies to the far left of the screen every time it opens
// or every time the background poll fires.
//
// If you are an AI assistant or a future developer reading this:
// DO NOT "simplify" this code. DO NOT "clean it up". DO NOT move
// lines around. DO NOT remove comments. Every single constraint here
// exists because its absence caused a regression.
//
// ============================================================
// SECTION 1: HOW NSPopover SIZING ACTUALLY WORKS
// ============================================================
//
// NSPopover does NOT size itself from contentViewController.view.frame.
// It sizes itself from contentViewController.preferredContentSize.
//
// NSHostingController with sizingOptions = .preferredContentSize
// automatically updates preferredContentSize from SwiftUI's IDEAL size.
//
// KEY INSIGHT: ANY change to preferredContentSize — even 1 point —
// causes NSPopover to re-anchor its FULL screen position (X AND Y).
// A wrong width places the popover's LEFT edge far off-screen.
// This is the "left jump" symptom.
//
// ============================================================
// SECTION 2: THE DYNAMIC HEIGHT STRATEGY (v2.3)
// ============================================================
//
// PROBLEM: We want jobListView to have dynamic (content-sized) height,
// but child nav views (JobStepsView, MatrixGroupView) are always 480pt.
// Navigating between them changes the ideal height => preferredContentSize
// changes => NSPopover re-anchors => left jump. (CAUSE 8)
//
// SOLUTION: Turn OFF automatic sizing (sizingOptions = []) and manually
// set popover.contentSize exactly ONCE — right before show() — by:
//   1. Calling hc.view.layoutSubtreeIfNeeded() to force a synchronous
//      AppKit layout pass so all subviews have computed their frames.
//   2. Reading hc.view.fittingSize — which is now accurate.
//   3. Setting popover.contentSize BEFORE show().
//
// WHY layoutSubtreeIfNeeded() IS REQUIRED (v2.3 lesson):
//   In v2.2, we read fittingSize inside a single DispatchQueue.main.async
//   block (one runloop tick after reload()). SwiftUI had enqueued its
//   layout pass but NOT yet executed it. fittingSize returned the
//   previous (stale/zero) height => popover was sized too small and
//   clipped its content at the top.
//
//   layoutSubtreeIfNeeded() forces AppKit to immediately flush the
//   pending layout pass synchronously, so fittingSize is accurate.
//   This is the correct AppKit pattern for "measure before show".
//
// WHY THIS IS SAFE:
//   1. layoutSubtreeIfNeeded() runs synchronously, not after another tick.
//   2. popover.contentSize is set BEFORE show(). Setting it before the
//      popover is visible does NOT trigger a position re-anchor.
//   3. sizingOptions = [] means SwiftUI NEVER auto-updates
//      preferredContentSize after this point. Navigation between nav
//      states does NOT change contentSize => no re-anchor => no jump.
//   4. On next open, we repeat the snapshot for fresh content size.
//
// ============================================================
// SECTION 3: ALL ROOT CAUSES OF LEFT-JUMP
// ============================================================
//
// CAUSE 1 — Wrong SwiftUI frame modifier on root or child views
//   Fix: .frame(idealWidth: 340) on root Group only.
//        .frame(maxWidth: .infinity, ...) on all child nav views.
//
// CAUSE 2 — Calling observable.reload() while the popover is open
//   Fix: Guard with `if !self.popoverIsOpen`.
//
// CAUSE 3 — Calling observable.reload() from popoverDidClose
//   Fix: NEVER call reload() from popoverDidClose.
//
// CAUSE 4 — popoverIsOpen flag set AFTER reload() in togglePopover
//   Fix: Set popoverIsOpen = true FIRST, then reload(), then show().
//
// CAUSE 5 — Multiple objectWillChange publishes per reload()
//   Fix: Single @Published StoreState struct. ONE assignment = ONE publish.
//
// CAUSE 6 — onChange-triggered reload races with togglePopover
//   Fix: Defer show() with DispatchQueue.main.async.
//
// CAUSE 7 — Async step load in JobStepsView fires @State after appear
//   Fix: Steps pre-loaded in PopoverView before navState changes.
//
// CAUSE 8 — Height changes between jobList (dynamic) and child nav views (480pt)
//   Fix: sizingOptions = [] + layoutSubtreeIfNeeded() + fittingSize snapshot
//        before show(). PopoverView root Group: .frame(idealWidth:340) only.
//
// CAUSE 9 — fittingSize read before SwiftUI layout pass completes (v2.2 bug)
//   What happened: fittingSize was read in first .async tick. SwiftUI had
//   enqueued but not yet executed its layout pass. Returned stale height.
//   Popover opened clipped (too short, content cut off at top).
//   Fix: Call hc.view.layoutSubtreeIfNeeded() before reading fittingSize.
//
// ============================================================
// SECTION 4: COMPLETE FORBIDDEN ACTIONS LIST
// ============================================================
//
//   ✘ Call observable.reload() unconditionally in onChange       => CAUSE 2
//   ✘ Call observable.reload() from popoverDidClose             => CAUSE 3
//   ✘ Set popoverIsOpen = true AFTER reload() in togglePopover  => CAUSE 4
//   ✘ Split StoreState into multiple @Published properties      => CAUSE 5
//   ✘ Add objectWillChange.send() in RunnerStoreObservable      => CAUSE 5
//   ✘ Move show() outside the DispatchQueue.main.async block    => CAUSE 6
//   ✘ Load steps async inside JobStepsView                      => CAUSE 7
//   ✘ Re-enable sizingOptions = .preferredContentSize           => CAUSE 8
//   ✘ Set popover.contentSize while the popover is visible      => re-anchor
//   ✘ Read fittingSize WITHOUT calling layoutSubtreeIfNeeded() first => CAUSE 9
//   ✘ Add KVO observer on preferredContentSize                  => feedback loop
//   ✘ Change popover.animates = false to true                   => re-anchor every frame
//
// ============================================================
// SECTION 5: WHAT IS ALLOWED
// ============================================================
//
//   ✔ Update statusItem button image in onChange (no size impact)
//   ✔ Call reload() inside togglePopover AFTER popoverIsOpen = true
//   ✔ Defer show() with DispatchQueue.main.async
//   ✔ Call hc.view.layoutSubtreeIfNeeded() before reading fittingSize
//   ✔ Set popover.contentSize ONCE before show() (while popover is not shown)
//   ✔ Set popoverIsOpen = false in popoverDidClose
//   ✔ Fetch steps on background thread then navigate (loadStepsAndNavigate)
//   ✔ Read popover.isShown freely
//   ✔ Call popover.performClose()
//
// ============================================================
// SECTION 6: HOW TO VERIFY THE FIX IS STILL WORKING
// ============================================================
//
// Test 1 — Open with no active jobs. Popover MUST NOT jump. Height should be compact.
// Test 2 — Open with jobs. Popover MUST NOT jump. Height should fit all content.
// Test 3 — Open and leave open for 30+ seconds. MUST NOT jump.
// Test 4 — Rapidly open/close 10 times. Must open stably every time.
// Test 5 — Tap a job row => navigate to steps view. MUST NOT jump.
// Test 6 — Navigate to steps, wait 5+ seconds. MUST NOT jump.
// Test 7 — Close popover, wait for job count to change, reopen.
//          New height must reflect new content. MUST NOT jump.
// Test 8 — Open popover. Content must NOT be clipped at the top. (CAUSE 9 test)
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
        // ⚠️ sizingOptions = [] — CAUSE 8 FIX.
        // We do NOT let SwiftUI auto-update preferredContentSize.
        // We snapshot hc.view.fittingSize manually before each show().
        // DO NOT change back to .preferredContentSize.
        hc.sizingOptions = []
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentViewController = hc
        popover.delegate              = self
        // ⚠️ DO NOT set popover.contentSize here at launch.
        // Set it in togglePopover, after layoutSubtreeIfNeeded(), before show().
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            log("AppDelegate > onChange - refreshing status icon")
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)

            // ⚠️ CAUSE 2 FIX. DO NOT REMOVE GUARD.
            if !self.popoverIsOpen {
                self.observable.reload()
            }
        }

        RunnerStore.shared.start()
    }

    // ⚠️⚠️⚠️  ORDER IS NOT NEGOTIABLE. SEE CAUSES 2, 4, 6, 8, AND 9.  ⚠️⚠️⚠️
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

            // STEP 2: Snapshot fresh data. ONE publish. (CAUSE 5 fix)
            observable.reload()

            // STEP 3: Defer to next runloop tick so the SwiftUI publish
            // from reload() is enqueued before we force layout. (CAUSE 6 fix)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let popover = self.popover,
                      let hc = self.hc,
                      let button = self.statusItem?.button else { return }
                guard !popover.isShown else { return }

                // STEP 4 (CAUSE 9 fix): Force AppKit to flush the pending
                // SwiftUI layout pass synchronously RIGHT NOW, before we
                // read fittingSize. Without this, SwiftUI has enqueued
                // its layout work but not yet executed it, so fittingSize
                // returns a stale (too-small) value => clipped popover.
                // ⚠️ DO NOT remove this call.
                hc.view.layoutSubtreeIfNeeded()

                // STEP 5 (CAUSE 8 fix): Read accurate natural size.
                // Width: always at least 340. Height: 120–480 range.
                // Set contentSize BEFORE show() — safe, no re-anchor.
                let fit = hc.view.fittingSize
                let w   = max(fit.width, 340)
                let h   = min(max(fit.height, 120), 480)
                popover.contentSize = NSSize(width: w, height: h)
                log("AppDelegate > contentSize set to \(w)×\(h) before show")

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
