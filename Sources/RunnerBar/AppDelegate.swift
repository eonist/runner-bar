import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<AnyView>?
    private let observable = RunnerStoreObservable()

    // ⚠️ REGRESSION GUARD — sizing (ref issues #52 #54)
    //
    // THE LEFT-JUMP RULE:
    //   popover.contentSize must NEVER change while the popover is open.
    //   macOS re-computes the anchor point whenever contentSize changes on a
    //   visible NSPopover, which shifts the window to the left.
    //   → onChange must NEVER call popover.contentSize or hc.view.setFrameSize.
    //   → Only navigate() may resize, and it is only called on user tap —
    //     the popover is typically dismissed before the user taps again.
    //
    // WIDTH = 320. NEVER dynamic, NEVER from fittingSize.
    //   Dynamic width → anchor drift on every poll.
    //
    // mainHeight = 390.
    //   Pixel budget for the TALLEST realistic main-view state
    //   (2 runners + 3 job rows + all fixed chrome):
    //     header:        44px
    //     jobs label:    26px
    //     3 job rows:    84px  (3 × 26px + 6px bottom pad)
    //     divider:        1px
    //     runners label: 26px
    //     2 runner rows: 64px  (2 × 32px)
    //     divider:        1px
    //     scopes:        82px
    //     divider:        1px
    //     toggle:        38px
    //     divider:        1px
    //     quit:          38px
    //     -------------------------
    //     total:        406px  → use 390 (scopes section measured tighter in practice)
    //   When fewer rows are shown SwiftUI top-aligns and the extra space at
    //   the bottom is acceptable. Do NOT lower below 390.
    //
    // detailHeight = 460.
    //   Covers header + back button + up to ~10 step rows (scrollable).
    //   Do NOT lower below 460.
    //
    // sizingOptions MUST remain [] — .preferredContentSize makes NSPopover
    //   auto-resize on every SwiftUI layout pass → left-jump on every poll.
    private static let width:        CGFloat = 320
    private static let mainHeight:   CGFloat = 390  // ⚠️ do not lower — see budget above
    private static let detailHeight: CGFloat = 460  // ⚠️ do not lower — covers ~10 step rows

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let size = NSSize(width: Self.width, height: Self.mainHeight)
        let hc = NSHostingController(rootView: mainView())
        hc.sizingOptions = []          // ⚠️ NEVER .preferredContentSize — causes left-jump
        hc.view.frame = NSRect(origin: .zero, size: size)
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentSize           = size
        popover.contentViewController = hc
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            // ⚠️ DO NOT touch popover.contentSize or hc.view.setFrameSize here.
            // Changing contentSize on a visible popover causes the left-jump.
            // Only update the status icon and reload the observable.
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)
            self.observable.reload()
        }
        RunnerStore.shared.start()
    }

    private func mainView() -> AnyView {
        AnyView(PopoverMainView(store: observable, onSelectJob: { [weak self] job in
            guard let self else { return }
            self.navigate(to: self.detailView(job: job), height: Self.detailHeight)
        }))
    }

    private func detailView(job: ActiveJob) -> AnyView {
        AnyView(JobDetailView(job: job, onBack: { [weak self] in
            guard let self else { return }
            self.navigate(to: self.mainView(), height: Self.mainHeight)
        }))
    }

    // ⚠️ REGRESSION GUARD — navigation (ref issues #52 #54)
    // Swaps content IN-PLACE and resizes in one atomic operation.
    // NEVER navigate by calling performClose() + show() — that re-anchors the popover.
    // This is the ONLY place where contentSize is allowed to change.
    // It is only called on explicit user interaction (tap job row / tap Back),
    // so the popover is typically not visible during the resize, or the user
    // expects the visual change and anchor shift is not noticeable.
    // Width ALWAYS stays Self.width (320) — never pass a different width here.
    private func navigate(to view: AnyView, height: CGFloat) {
        guard let popover, let hc else { return }
        let newSize = NSSize(width: Self.width, height: height)
        hc.rootView = view
        hc.view.setFrameSize(newSize)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            popover.contentSize = newSize
        }
    }

    @objc private func togglePopover() {
        guard let popover else { return }
        if popover.isShown { popover.performClose(nil) } else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem?.button,
              button.window != nil,
              let popover else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
