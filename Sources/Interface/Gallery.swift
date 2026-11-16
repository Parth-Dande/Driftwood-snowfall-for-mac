import AppKit
import SwiftUI

/// A scene's picture with a light preview of its weather on top.
struct LiveScene: View {
    /// The scene to show.
    let scene: Scene
    /// The app state, read to decide whether the preview should move.
    let desktop: Desktop

    @Environment(\.controlActiveState) private var windowActivity

    var body: some View {
        SceneArtwork(scene: scene)
            .overlay {
                if desktop.isMotionEnabled, windowActivity == .key, desktop.activeScene == nil {
                    WeatherPreview(scene: scene, isRunning: true, density: desktop.density, speed: desktop.fallSpeed)
                }
            }
    }
}

/// The main window: pick a scene, adjust its weather and apply it to the desktop.
struct Gallery: View {
    @Bindable var desktop: Desktop
    @State private var selection = Scene.all[0]

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
                        if Wallpapers.shared.hasCustomImage(for: selection) {
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
                ForEach(Scene.all) { scene in
                    Button {
                        selection = scene
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            SceneArtwork(scene: scene)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: scene.symbolName)
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
                Toggle("Motion", isOn: $desktop.isMotionEnabled)
                Slider(value: $desktop.density, in: 0.05...1.5) { Text("Weather density") }
                    .frame(width: 142)
                    .disabled(!desktop.isMotionEnabled)
                Slider(value: $desktop.fallSpeed, in: 0.12...1.1) { Text("Fall speed") }
                    .frame(width: 135)
                    .disabled(!desktop.isMotionEnabled)
                Spacer()
                Button("Clear") { desktop.clear() }
                    .disabled(desktop.activeScene == nil)
                Button("Apply to All Displays") { desktop.apply(selection) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 18) {
                Toggle("Open at login", isOn: $desktop.opensAtLogin)
                Toggle("Show on lock screen", isOn: $desktop.showsOnLockScreen)
                    .help("Uses the scene's picture as the system desktop picture, which the lock screen shows. macOS does not let the weather run there.")
            }
            .toggleStyle(.checkbox)
            .font(.callout)
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
            get: { desktop.errorMessage != nil }, set: { if !$0 { desktop.errorMessage = nil } }
        )) {
            Button("OK") { desktop.errorMessage = nil }
        } message: {
            Text(desktop.errorMessage ?? "")
        }
    }

    private var status: String {
        if let notice = desktop.notice { return notice }
        if desktop.activeScene?.weather == .snow { return "Drag snow up from the bottom edge. Drop one ball above another to stack them." }
        if let active = desktop.activeScene { return "On your desktop · \(active.name)" }
        return "Preview a scene, then apply it to your desktop."
    }
}
