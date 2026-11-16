import AppKit
import SwiftUI

/// The menu bar item's controls.
struct StatusMenu: View {
    @Bindable var desktop: Desktop
    /// Called when the user asks for the gallery.
    let openGallery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weather density").font(.headline)
                Spacer()
                Text(desktop.density, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $desktop.density, in: 0.05...1.5) { Text("Weather density") }
            HStack {
                Text("Fall speed").font(.headline)
                Spacer()
                Text("\(desktop.fallSpeed / 0.42, format: .number.precision(.fractionLength(1)))×")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $desktop.fallSpeed, in: 0.12...1.1) { Text("Fall speed") }
            Divider()
            Button("Open Gallery", action: openGallery)
            Menu("Apply Scene") {
                ForEach(Scene.all) { scene in
                    Button(scene.name) { desktop.apply(scene) }
                }
            }
            Button(desktop.isMotionEnabled ? "Pause Motion" : "Resume Motion") {
                desktop.isMotionEnabled.toggle()
            }
            Button {
                desktop.sendPlough()
            } label: {
                Label("Plough", systemImage: "truck.box")
            }
            .disabled(desktop.activeScene?.weather != .snow)
            Button("Clear Wallpaper") { desktop.clear() }
                .disabled(desktop.activeScene == nil)
            Divider()
            // Something the user has already allowed needs no switch here; the gallery keeps both.
            if !desktop.opensAtLogin { Toggle("Open at Login", isOn: $desktop.opensAtLogin) }
            if !desktop.showsOnLockScreen { Toggle("Show on Lock Screen", isOn: $desktop.showsOnLockScreen) }
            Button("Quit Driftwood") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 250)
    }
}
