import AppKit
import SwiftUI

/// The menu bar item's controls.
struct StatusMenu: View {
    @Bindable var desktop: Desktop
    @Environment(\.openWindow) private var openWindow

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
            Button("Open Gallery") {
                openWindow(id: "gallery")
                NSApp.activate(ignoringOtherApps: true)
            }
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
            Button("Quit Driftwood") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 250)
    }
}
