import AppKit
import SwiftUI

/// A borderless, non-activating panel used instead of NSPopover.
/// Positioned manually below the status bar button, so it never
/// suffers from NSPopover's anchor-recalculation bugs.
final class StatusPanel: NSPanel {

    private var hostingView: NSHostingView<AnyView>!

    init<Content: View>(rootView: Content) {
        let size = NSRect(x: 0, y: 0, width: 320, height: 420)
        super.init(
            contentRect: size,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        isOpaque          = false
        backgroundColor   = .clear
        level             = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false

        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = size
        contentView   = hosting
        hostingView   = hosting
    }

    // Allow clicks without activating the app.
    override var canBecomeKey: Bool { true }

    // Close when clicking outside.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
