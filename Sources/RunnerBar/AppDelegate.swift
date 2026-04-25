import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hc: NSHostingController<AnyView>?
    private let observable = RunnerStoreObservable()

    private static let popoverWidth: CGFloat = 320

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let rootView = AnyView(mainView())
        let hc = NSHostingController(rootView: rootView)
        hc.sizingOptions = []
        self.hc = hc

        let popover = NSPopover()
        popover.behavior              = .transient
        popover.animates              = false
        popover.contentViewController = hc
        self.popover = popover

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)
            self.observable.reload()
        }
        RunnerStore.shared.start()
    }

    // MARK: - View factories

    private func mainView() -> some View {
        PopoverMainView(store: observable, onSelectJob: { [weak self] job in
            self?.navigateTo(job: job)
        })
    }

    private func detailView(job: ActiveJob) -> some View {
        JobDetailView(job: job, onBack: { [weak self] in
            self?.navigateBack()
        })
    }

    // MARK: - Navigation

    private func navigateTo(job: ActiveJob) {
        // 1. Close while open so next show() re-anchors correctly.
        popover?.performClose(nil)
        // 2. Swap content and size while closed.
        let view = AnyView(detailView(job: job))
        hc?.rootView = view
        let size = NSSize(width: Self.popoverWidth, height: 460)
        popover?.contentSize = size
        hc?.view.setFrameSize(size)
        // 3. Re-open on next runloop tick.
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    private func navigateBack() {
        popover?.performClose(nil)
        let view = AnyView(mainView())
        hc?.rootView = view
        let size = NSSize(width: Self.popoverWidth, height: 420)
        popover?.contentSize = size
        hc?.view.setFrameSize(size)
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    // MARK: - Toggle

    @objc private func togglePopover() {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Ensure main view is loaded with correct size.
            let size = NSSize(width: Self.popoverWidth, height: 420)
            popover.contentSize = size
            hc?.view.setFrameSize(size)
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button,
              button.window != nil,
              let popover else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
