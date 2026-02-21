import SwiftUI

@main
struct SpikeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Spike", systemImage: "waveform.circle.fill") {
            MenuBarPopover()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
