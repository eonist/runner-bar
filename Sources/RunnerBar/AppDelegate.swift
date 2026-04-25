import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<AnyView>?
    private let observable = RunnerStoreObservable()

    // ═══════════════════════════════════════════════════════════════════
    // ⚠️ REGRESSION GUARD — SIZE RULES (ref #52 #54 #57)
    // ═══════════════════════════════════════════════════════════════════
    //
    // THE LEFT-JUMP RULE (#52 #54):
    //   macOS re-anchors NSPopover to the status bar button every time
    //   popover.contentSize changes while the popover is VISIBLE.
    //   That re-anchor is the left-jump.
    //
    //   THEREFORE: contentSize/setFrameSize are FORBIDDEN while popover.isShown.
    //
    // THE HEIGHT-FITS-CONTENT RULE (#57):
    //   The popover should be sized to its content, not a fixed over-tall constant.
    //   THEREFORE: compute height and resize right before show(), while isShown==false.
    //
    // THE TWO RULES ARE COMPATIBLE because:
    //   openPopover() is the ONLY call site where isShown is guaranteed false.
    //   navigate() fires while the popover IS open (tapping inside does NOT close
    //   a .transient popover — only clicking OUTSIDE closes it).
    //
    // SAFE OPERATIONS PER CALL SITE:
    //
    //   applicationDidFinishLaunching:
    //     ✔ set frame / contentSize (popover not yet created)
    //     ✔ any initialization
    //
    //   onChange (fires every poll while popover may be OPEN):
    //     ✔ statusItem icon update
    //     ✔ observable.reload()
    //     ✖ contentSize  ← LEFT-JUMP
    //     ✖ setFrameSize ← LEFT-JUMP
    //     ✖ hc.rootView  ← triggers layout, may cause LEFT-JUMP
    //
    //   navigate() (fires while popover IS open — user tapped inside):
    //     ✔ hc.rootView = newView  (SwiftUI updates in-place, no re-anchor)
    //     ✖ contentSize  ← LEFT-JUMP (popover is OPEN)
    //     ✖ setFrameSize ← LEFT-JUMP (popover is OPEN)
    //
    //   openPopover() (isShown == false, guaranteed):
    //     ✔ setFrameSize  (popover is CLOSED)
    //     ✔ contentSize   (popover is CLOSED)
    //     ✖ hc.rootView   ← creates new SwiftUI tree → deferred layout fires
    //                       AFTER show() while popover becomes visible → LEFT-JUMP.
    //                       hc.rootView is already correct (navigate resets on Back).
    //                       DO NOT reassign it here.
    //
    // SUMMARY TABLE:
    //   onChange    : reload icon + observable ONLY
    //   navigate()  : hc.rootView ONLY
    //   openPopover(): setFrameSize + contentSize ONLY (no rootView)
    //
    // ═══════════════════════════════════════════════════════════════════

    // Fixed width. Never dynamic. Dynamic width = anchor drift.
    private static let fixedWidth: CGFloat = 320

    // MARK: — Height computation
    //
    // Computes main-view height from current store state.
    // ⚠️ Called ONLY from openPopover() where isShown == false.
    // ⚠️ NEVER call from onChange, navigate(), or any other site.
    //
    // Pixel budget (must match PopoverMainView.swift padding values EXACTLY):
    //   header:              44px  (paddingTop 12 + content + paddingBottom 8)
    //   "Active Jobs" label: 26px  (paddingTop 8 + caption + paddingBottom 2)
    //   divider:              1px
    //   scopes block:        82px  (label 18 + 1-scope row 26 + input 38)
    //   divider:              1px
    //   toggle row:          38px  (paddingVertical 8 each side)
    //   divider:              1px
    //   quit row:            38px  (paddingVertical 8 each side)
    //   fixed chrome:       231px
    //
    //   "No active jobs":    22px  (only when jobCount == 0)
    //   each job row:        26px  (paddingVertical 3 each side + content ~20)
    //   job-list pad:         6px  (only when jobCount > 0)
    //   runners label:       26px  (only when runnerCount > 0)
    //   each runner row:     32px  (paddingVertical 5 each side + content ~22)
    //   runners divider:      1px  (only when runnerCount > 0)
    //
    // ⚠️ If you change ANY padding in PopoverMainView.swift, update these numbers.
    // ⚠️ If you add a scope row to the scopes section, update scopes block (26px/scope).
    private static func computeMainHeight() -> CGFloat {
        let jobs    = min(RunnerStore.shared.jobs.count, 3)
        let runners = RunnerStore.shared.runners.count
        var h: CGFloat = 231
        h += jobs == 0 ? 22 : CGFloat(jobs) * 26 + 6
        if runners > 0 { h += 26 + CGFloat(runners) * 32 + 1 }
        return max(h, 200)  // floor: never collapse below 200px
    }

    // MARK: — App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Initial size. openPopover() will recompute on every open.
        let initialSize = NSSize(width: Self.fixedWidth, height: Self.computeMainHeight())
        let hc = NSHostingController(rootView: mainView())
        hc.sizingOptions = []  // ⚠️ NEVER .preferredContentSize — auto-resizes on SwiftUI layout = left-jump
        hc.view.frame = NSRect(origin: .zero, size: initialSize)
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentSize           = initialSize
        popover.contentViewController = hc
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            // ⚠️ EXACTLY TWO LINES. NEVER ADD A THIRD. NEVER TOUCH SIZE.
            // See REGRESSION GUARD: onChange fires while popover may be visible.
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)
            self.observable.reload()
        }
        RunnerStore.shared.start()
    }

    // MARK: — View factories

    private func mainView() -> AnyView {
        AnyView(PopoverMainView(store: observable, onSelectJob: { [weak self] job in
            guard let self else { return }
            self.navigate(to: self.detailView(job: job))
        }))
    }

    private func detailView(job: ActiveJob) -> AnyView {
        AnyView(JobDetailView(job: job, onBack: { [weak self] in
            guard let self else { return }
            self.navigate(to: self.mainView())
            // ⚠️ No size change here. openPopover() will resize on next open.
        }))
    }

    // MARK: — Navigation

    // ⚠️ REGRESSION GUARD: rootView swap ONLY. ZERO size changes.
    // navigate() fires while the popover IS open (user tapped inside it).
    // .transient only closes on clicks OUTSIDE — not on taps inside.
    // Any contentSize/setFrameSize here = popover is visible = LEFT-JUMP.
    // Width and height stay exactly as set by openPopover(). No exceptions.
    private func navigate(to view: AnyView) {
        guard let hc else { return }
        hc.rootView = view
        // ⚠️ That is ALL. Do not add size changes here. Ever.
    }

    // MARK: — Popover show/hide

    @objc private func togglePopover() {
        guard let popover else { return }
        if popover.isShown { popover.performClose(nil) } else { openPopover() }
    }

    // openPopover() — the ONE safe site for sizing.
    // Guaranteed: only called from the else-branch above, so isShown == false.
    // popover.contentSize on a CLOSED popover does NOT trigger macOS re-anchor.
    //
    // ⚠️ DO NOT reassign hc.rootView here.
    //   Reassigning rootView discards the existing SwiftUI tree and builds a new one.
    //   SwiftUI defers part of that work to the next run-loop tick, which fires
    //   AFTER show() while the popover is becoming visible → macOS re-anchors → left-jump.
    //   hc.rootView is already the main view because:
    //     • We initialise it as mainView() in applicationDidFinishLaunching.
    //     • navigate()-to-Back always resets it to mainView().
    //     • .transient closes the popover before any outside-click; the user cannot
    //       open the popover while still on the detail view.
    private func openPopover() {
        guard let button = statusItem?.button,
              button.window != nil,
              let popover,
              let hc else { return }

        // Resize to fit current content. Safe: isShown == false (see above).
        // ⚠️ NO hc.rootView change here — see warning above.
        let h = Self.computeMainHeight()
        let newSize = NSSize(width: Self.fixedWidth, height: h)
        hc.view.setFrameSize(newSize)
        popover.contentSize = newSize

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
