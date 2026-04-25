import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<AnyView>?
    private let observable = RunnerStoreObservable()

    // ⚠️ REGRESSION GUARD — width/height (ref issue #54)
    // WIDTH must ALWAYS be 320. Never make it dynamic or derive it from fittingSize.
    // Dynamic width causes the popover to jump left on every data update.
    // Heights are the ONLY place dimensions are defined — PopoverMainView must NOT
    // set its own .frame(height:). The views fill whatever size AppDelegate gives them.
    // sizingOptions MUST remain [] — .preferredContentSize causes SwiftUI to resize
    // the popover on every layout pass, which also causes the left-jump.
    private static let width: CGFloat        = 320
    private static let mainHeight: CGFloat   = 360
    private static let detailHeight: CGFloat = 460

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let size = NSSize(width: Self.width, height: Self.mainHeight)
        let hc = NSHostingController(rootView: mainView())
        hc.sizingOptions = []  // ⚠️ NEVER change to .preferredContentSize — causes left-jump
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

    /// Swap content and resize the popover WITHOUT closing it.
    /// ⚠️ REGRESSION GUARD: NEVER navigate by calling performClose() + show().
    /// Closing and reopening the popover causes macOS to re-anchor it from scratch,
    /// which shifts it left. Always swap hc.rootView in-place instead.
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
