import SwiftUI

@main
struct SpikeApp: App {
    @State private var appState = AppState()

    init() {
        // Delay slightly so @State is initialized before setup
        DispatchQueue.main.async { [appState] in
            appState.setup()
        }
    }

    var body: some Scene {
        MenuBarExtra("Spike", systemImage: "waveform.circle.fill") {
            MenuBarPopover()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
