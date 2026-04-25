import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panel: StatusPanel?
    private let observable = RunnerStoreObservable()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusIcon(for: .allOffline)
            button.action = #selector(togglePanel)
            button.target = self
        }

        let rootView = PopoverMainView(store: observable)
        panel = StatusPanel(rootView: rootView)

        RunnerStore.shared.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.image = makeStatusIcon(for: RunnerStore.shared.aggregateStatus)
            self.observable.reload()
        }
        RunnerStore.shared.start()
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let panel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // Calculate position: directly below the status bar button.
            let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let panelSize  = panel.frame.size
            let x = buttonRect.midX - panelSize.width / 2
            let y = buttonRect.minY - panelSize.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
