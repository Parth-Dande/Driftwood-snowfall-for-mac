import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The app's state: which scene is on the desktop, how its weather is set, and the windows that show it.
@MainActor
@Observable
final class Desktop {
    /// The scene currently on the desktop, or `nil` when the regular desktop picture is showing.
    private(set) var activeScene: Scene?
    /// Whether the weather is animating. When `false`, only the picture shows.
    var isMotionEnabled = true { didSet { weather.isMotionEnabled = isMotionEnabled; weather.applySettings() } }
    /// How much weather falls, from sparse to heavy. Saved between launches.
    var density = UserDefaults.standard.object(forKey: "weatherDensity") as? Double ?? 0.55 {
        didSet {
            weather.density = density
            UserDefaults.standard.set(density, forKey: "weatherDensity")
        }
    }
    /// How fast weather time runs; `0.42` is natural speed. Saved between launches.
    var fallSpeed = UserDefaults.standard.object(forKey: "weatherSpeed") as? Double ?? 0.42 {
        didSet {
            weather.fallSpeed = fallSpeed
            UserDefaults.standard.set(fallSpeed, forKey: "weatherSpeed")
        }
    }
    /// A problem to tell the user about, shown as an alert.
    var errorMessage: String?
    /// A passing remark for the status line, such as a picture being smaller than the display.
    var notice: String?
    private let weather = DesktopWeather()
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var observation: NSObjectProtocol?

    /// Creates the state and restores the scene that was showing when Driftwood last quit.
    init() {
        weather.density = density
        weather.fallSpeed = fallSpeed
        observation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.synchronizeWindows() }
        }
        let wanted = UserDefaults.standard.string(forKey: "applyScene") ?? UserDefaults.standard.string(forKey: "activeScene")
        if let scene = Scene.all.first(where: { $0.id == wanted }) {
            DispatchQueue.main.async { [weak self] in self?.apply(scene) }
        }
    }

    /// Shows `scene` and its weather on every display.
    func apply(_ scene: Scene) {
        activeScene = scene
        notice = nil
        UserDefaults.standard.set(scene.id, forKey: "activeScene")
        rebuildWindows()
    }

    /// Removes the scene and weather, revealing the regular desktop picture.
    func clear() {
        activeScene = nil
        notice = nil
        UserDefaults.standard.removeObject(forKey: "activeScene")
        rebuildWindows()
    }

    /// Sends a plough across each display to clear settled snow.
    func sendPlough() { weather.sendPlough() }

    /// Lets the user put their own picture behind a scene's weather.
    func chooseWallpaper(for scene: Scene) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a picture for \(scene.name). \(Wallpapers.guidance)"
        panel.prompt = "Use Picture"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            notice = try Wallpapers.shared.setCustomImage(from: url, for: scene)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Restores the bundled picture for `scene`.
    func resetWallpaper(for scene: Scene) {
        Wallpapers.shared.removeCustomImage(for: scene)
        notice = nil
    }

    private func rebuildWindows() {
        for window in windows.values { window.close() }
        windows.removeAll()
        synchronizeWindows()
    }

    private func synchronizeWindows() {
        guard let activeScene else {
            for window in windows.values { window.close() }
            windows.removeAll()
            weather.stop()
            return
        }
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.displayID))
        for id in Array(windows.keys) where !ids.contains(id) { windows.removeValue(forKey: id)?.close() }
        for screen in screens {
            if let window = windows[screen.displayID] {
                window.fit(to: screen)
                continue
            }
            let window = WallpaperWindow(screen: screen)
            window.contentView = NSHostingView(rootView: SceneArtwork(scene: activeScene))
            windows[screen.displayID] = window
            window.orderFrontRegardless()
        }
        weather.start(activeScene.weather, on: screens)
    }
}
