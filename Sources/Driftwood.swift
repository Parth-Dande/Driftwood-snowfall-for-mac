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

struct LiveScene: View {
    let scene: Scene
    let desktop: Desktop

    @Environment(\.controlActiveState) private var windowActivity

    var body: some View {
        SceneArtwork(scene: scene)
            .overlay {
                if desktop.motion, windowActivity == .key, desktop.active == nil {
                    Weather(scene: scene, running: true, strength: desktop.intensity, speed: desktop.speed)
                }
            }
    }
}

struct Gallery: View {
    @Bindable var desktop: Desktop
    @State private var selection = Scene.catalog[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DRIFTWOOD").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(3).foregroundStyle(.mint)
                    Text("Weather for your desktop").font(.system(size: 27, weight: .medium, design: .serif))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 8) {
                        if Wallpapers.shared.isCustom(selection) {
                            Button("Use Original") { desktop.resetWallpaper(for: selection) }
                        }
                        Button("Change Wallpaper…") { desktop.chooseWallpaper(for: selection) }
                            .help(Wallpapers.guidance)
                    }
                    Text("Best at \(Int(Wallpapers.recommendedSize.width)) × \(Int(Wallpapers.recommendedSize.height)) px or larger, landscape")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            LiveScene(scene: selection, desktop: desktop)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.black.opacity(0.83), .clear], startPoint: .bottom, endPoint: .top)
                        .frame(height: 140)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selection.name).font(.system(size: 34, weight: .medium, design: .serif))
                        Text(selection.caption).font(.callout).foregroundStyle(.white.opacity(0.85))
                    }
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .padding(23)
                }
                .frame(height: 280)
                .clipShape(.rect(cornerRadius: 12))

            HStack(spacing: 8) {
                ForEach(Scene.catalog) { scene in
                    Button {
                        selection = scene
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            SceneArtwork(scene: scene)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: scene.symbol)
                                        .font(.caption).padding(6)
                                        .background(.black.opacity(0.42), in: Circle()).padding(5)
                                }
                                .frame(height: 48).clipShape(.rect(cornerRadius: 6))
                            Text(scene.name).font(.caption).lineLimit(1)
                        }
                        .padding(5)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.05), in: .rect(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selection.id == scene.id ? Color.mint : Color.clear, lineWidth: 1.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(scene.name)
                    .accessibilityAddTraits(selection.id == scene.id ? .isSelected : [])
                }
            }
            HStack(spacing: 14) {
                Toggle("Motion", isOn: $desktop.motion)
                Slider(value: $desktop.intensity, in: 0.05...1.5) { Text("Weather density") }
                    .frame(width: 142)
                    .disabled(!desktop.motion)
                Slider(value: $desktop.speed, in: 0.12...1.1) { Text("Fall speed") }
                    .frame(width: 135)
                    .disabled(!desktop.motion)
                Spacer()
                Button("Clear") { desktop.clear() }
                    .disabled(desktop.active == nil)
                Button("Apply to All Displays") { desktop.apply(selection) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            Text(status)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .accessibilityIdentifier("desktop-status")
        }
        .padding(23)
        .frame(width: 730)
        .background(Color(red: 0.07, green: 0.09, blue: 0.12))
        .preferredColorScheme(.dark)
        .alert("Driftwood", isPresented: Binding(
            get: { desktop.error != nil }, set: { if !$0 { desktop.error = nil } }
        )) {
            Button("OK") { desktop.error = nil }
        } message: {
            Text(desktop.error ?? "")
        }
    }

    private var status: String {
        if let notice = desktop.notice { return notice }
        if desktop.active?.id == "snow" { return "Drag snow up from the bottom edge. Drop one ball above another to stack them." }
        if let active = desktop.active { return "On your desktop · \(active.name)" }
        return "Preview a scene, then apply it to your desktop."
    }
}

@main
struct DriftwoodApp: App {
    @State private var desktop = Desktop()

    var body: some SwiftUI.Scene {
        Window("Driftwood", id: "gallery") {
            Gallery(desktop: desktop)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Driftwood", systemImage: "cloud.moon") {
            StatusMenu(desktop: desktop)
        }
        .menuBarExtraStyle(.window)
    }
}

struct StatusMenu: View {
    @Bindable var desktop: Desktop
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weather density").font(.headline)
                Spacer()
                Text(desktop.intensity, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $desktop.intensity, in: 0.05...1.5) { Text("Weather density") }
            HStack {
                Text("Fall speed").font(.headline)
                Spacer()
                Text("\(desktop.speed / 0.42, format: .number.precision(.fractionLength(1)))×")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $desktop.speed, in: 0.12...1.1) { Text("Fall speed") }
            Divider()
            Button("Open Gallery") {
                openWindow(id: "gallery")
                NSApp.activate(ignoringOtherApps: true)
            }
            Menu("Apply Scene") {
                ForEach(Scene.catalog) { scene in
                    Button(scene.name) { desktop.apply(scene) }
                }
            }
            Button(desktop.motion ? "Pause Motion" : "Resume Motion") {
                desktop.motion.toggle()
            }
            Button {
                desktop.plough()
            } label: {
                Label("Plough", systemImage: "truck.box")
            }
            .disabled(desktop.active?.id != "snow")
            Button("Clear Wallpaper") { desktop.clear() }
                .disabled(desktop.active == nil)
            Divider()
            Button("Quit Driftwood") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 250)
    }
}
