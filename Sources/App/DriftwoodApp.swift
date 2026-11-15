import AppKit
import SwiftUI

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
