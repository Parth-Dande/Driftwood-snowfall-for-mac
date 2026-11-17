import AppKit

/// The app: a background agent with a menu bar item, a gallery window it opens on request, and
/// one `Desktop` they share.
///
/// Driftwood keeps running with no windows open. It shows a Dock icon only while the gallery is
/// open, so the weather can stay on the desktop without taking up a place in the Dock.
@main
@MainActor
final class DriftwoodApp: NSObject, NSApplicationDelegate {
    private static let shared = DriftwoodApp()

    private let desktop = Desktop()
    private lazy var gallery = GalleryWindowController(desktop: desktop)
    private lazy var statusItem = StatusItemController(desktop: desktop) { [weak self] in self?.gallery.show() }

    /// Starts the app and runs it until the user quits.
    static func main() {
        let application = NSApplication.shared
        application.delegate = shared
        application.run()
    }

    /// Sets up the menus and the menu bar item, and opens the gallery unless macOS started
    /// Driftwood at login.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.makeMenu()
        statusItem.install()
        // `-showControls YES` opens the menu bar panel straight away, for scripted checks.
        if UserDefaults.standard.bool(forKey: "showControls") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.statusItem.showControls() }
        }
        // Started by macOS at login, Driftwood stays out of the way. Opened by hand, it shows the gallery.
        guard !LoginItem.launchedAtLogin else { return }
        gallery.show()
        // A scripted launch (`-applyScene`) must not stop to ask questions.
        if UserDefaults.standard.string(forKey: "applyScene") == nil { Setup.offerOnFirstLaunch(for: desktop) }
        // `-showWallpaperPicker YES` opens the Change Wallpaper picker straight away, for scripted checks.
        if UserDefaults.standard.bool(forKey: "showWallpaperPicker") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.desktop.chooseWallpaper(for: self.desktop.activeScene ?? Scene.all[0])
            }
        }
    }

    /// Clicking the Dock icon, or opening the app again, brings the gallery back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        gallery.show()
        return false
    }

    /// Keeps Driftwood running, and the weather on the desktop, after the gallery is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Puts the user's own desktop picture back. With Driftwood gone the desktop shows the system
    /// picture again, so it must be theirs.
    func applicationWillTerminate(_ notification: Notification) {
        LockScreenPicture.restoreUserPicture()
    }
}

/// The menus Driftwood shows while its gallery is in front.
@MainActor
private enum MainMenu {
    /// Makes the menu bar: an app menu and a Window menu.
    static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "About Driftwood", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Driftwood", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Driftwood", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        for menu in [app, window] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.windowsMenu = window
        return main
    }
}
