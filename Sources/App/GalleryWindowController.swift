import AppKit
import SwiftUI

/// Owns the gallery window and Driftwood's presence in the Dock.
///
/// The window is created once and reused, so asking for it always brings the same window forward
/// instead of depending on whether a previous one still exists.
@MainActor
final class GalleryWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    /// Creates the controller for a gallery editing `desktop`. The window stays hidden until `show()`.
    init(desktop: Desktop) {
        let host = NSHostingController(rootView: Gallery(desktop: desktop))
        window = NSWindow(contentViewController: host)
        window.title = "Driftwood"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("gallery")
        super.init()
        window.delegate = self
        if window.frame.origin == .zero { window.center() }
    }

    /// Brings the gallery to the front, showing Driftwood in the Dock while it is open.
    func show() {
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Takes Driftwood out of the Dock. With the gallery gone there is nothing to switch to.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
