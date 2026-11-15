import AppKit
import CoreGraphics

/// A borderless window that sits behind the desktop icons and shows a scene's picture.
@MainActor
final class WallpaperWindow: NSWindow {
    /// The display this window covers.
    let displayID: CGDirectDisplayID

    /// Creates a wallpaper window covering `screen`.
    init(screen: NSScreen) {
        displayID = screen.displayID
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        title = "Driftwood"

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        contentView = view

        setFrame(screen.frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Resizes the window to cover `screen` after its arrangement or resolution changes.
    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }
}
