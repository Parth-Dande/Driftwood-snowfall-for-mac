import AppKit
import SwiftUI

/// Driftwood's menu bar item and the panel of controls it opens.
///
/// The panel is placed by hand directly under the item, sized to its contents first, so it can
/// never open over the menu bar or run off the top of the screen.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    /// A borderless panel that can still take the keyboard, so its sliders and menus work.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: Panel
    private let host: NSHostingView<StatusMenu>
    private var outsideClickMonitor: Any?
    private var lastClosed = 0.0

    /// Creates the controller. `openGallery` is called when the user asks for the gallery.
    init(desktop: Desktop, openGallery: @escaping () -> Void) {
        panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        var close: () -> Void = {}
        host = NSHostingView(rootView: StatusMenu(desktop: desktop) {
            close()
            openGallery()
        })
        super.init()
        close = { [weak self] in self?.close() }

        let backdrop = NSVisualEffectView()
        backdrop.material = .menu
        backdrop.state = .active
        backdrop.blendingMode = .behindWindow
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 12
        backdrop.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor), host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            host.topAnchor.constraint(equalTo: backdrop.topAnchor), host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])
        panel.contentView = backdrop
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
    }

    /// Puts the item in the menu bar.
    func install() {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "cloud.moon", accessibilityDescription: "Driftwood")
        button.target = self
        button.action = #selector(toggle)
        // Acting on the press, not the release, means a click always registers, even when the
        // pointer leaves the icon before the button comes up.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func toggle() {
        // Pressing the item while the panel is open first takes the panel's key state away, which
        // closes it. That same press must not then open it again.
        if panel.isVisible { close() } else if ProcessInfo.processInfo.systemUptime - lastClosed > 0.3 { showControls() }
    }

    /// Opens the panel of controls under the menu bar item.
    func showControls() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = host.fittingSize
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(CGRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        // A click anywhere outside Driftwood dismisses the panel, as it would a menu.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastClosed = ProcessInfo.processInfo.systemUptime
        item.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Dismisses the panel when another of Driftwood's own windows is clicked. A menu opened from
    /// inside the panel does not take the key state away, so the panel stays put for that.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
