import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            switch appState.phase {
            case .idle:
                idleView
            case .recording:
                recordingView
            case .processing:
                processingView
            case .result(let response):
                ResultView(response: response, actionResults: appState.actionResults)
            case .error(let message):
                errorView(message)
            }

            Divider()

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { appState.setup() }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Hold Ctrl+Option+` to speak")
                .font(.headline)
            Text("Release to process")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var recordingView: some View {
        VStack(spacing: 8) {
            WaveformView(levels: appState.audioLevels)
                .frame(height: 40)
            Text("Listening...")
                .font(.headline)
                .foregroundStyle(.red)
        }
        .padding(.vertical, 8)
    }

    private var processingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            Text("Processing...")
                .font(.headline)
        }
        .padding(.vertical, 8)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Dismiss") { appState.reset() }
        }
        .padding(.vertical, 8)
    }
}
