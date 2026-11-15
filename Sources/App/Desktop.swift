import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class Desktop {
    private(set) var active: Scene?
    var motion = true { didSet { weather.motion = motion; weather.refresh() } }
    var intensity = UserDefaults.standard.object(forKey: "weatherDensity") as? Double ?? 0.55 {
        didSet {
            weather.density = intensity
            UserDefaults.standard.set(intensity, forKey: "weatherDensity")
        }
    }
    var speed = UserDefaults.standard.object(forKey: "weatherSpeed") as? Double ?? 0.42 {
        didSet {
            weather.speed = speed
            UserDefaults.standard.set(speed, forKey: "weatherSpeed")
        }
    }
    var error: String?
    /// A passing remark for the status line, such as a picture being smaller than the display.
    var notice: String?
    private let weather = DesktopWeather()
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var observation: NSObjectProtocol?

    init() {
        weather.density = intensity
        weather.speed = speed
        observation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        let wanted = UserDefaults.standard.string(forKey: "applyScene") ?? UserDefaults.standard.string(forKey: "activeScene")
        if let scene = Scene.catalog.first(where: { $0.id == wanted }) {
            DispatchQueue.main.async { [weak self] in self?.apply(scene) }
        }
    }

    func apply(_ scene: Scene) {
        active = scene
        notice = nil
        UserDefaults.standard.set(scene.id, forKey: "activeScene")
        rebuild()
    }

    func clear() {
        active = nil
        notice = nil
        UserDefaults.standard.removeObject(forKey: "activeScene")
        rebuild()
    }

    func plough() { weather.plough() }

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
            notice = try Wallpapers.shared.replace(scene, with: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func resetWallpaper(for scene: Scene) {
        Wallpapers.shared.reset(scene)
        notice = nil
    }

    private func rebuild() {
        for window in windows.values { window.close() }
        windows.removeAll()
        sync()
    }

    private func sync() {
        guard let active else {
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
                window.match(screen: screen)
                continue
            }
            let window = WallpaperWindow(screen: screen)
            window.contentView = NSHostingView(rootView: SceneArtwork(scene: active))
            windows[screen.displayID] = window
            window.orderFrontRegardless()
        }
        weather.configure(effect: active.id, screens: screens)
    }
}
