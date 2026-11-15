import AppKit
import SwiftUI

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
