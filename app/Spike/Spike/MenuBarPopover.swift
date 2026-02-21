import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @State private var micPulse = false
    @State private var dotCount = 0
    @State private var errorVisible = true

    var body: some View {
        VStack(spacing: 0) {
            Group {
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
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .animation(.easeInOut(duration: 0.2), value: phaseKey)

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.6))
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 12)

            Image(systemName: "mic.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
                .scaleEffect(micPulse ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: micPulse)
                .onAppear { micPulse = true }

            Text("⌥ Space")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Spacer(minLength: 12)
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .scaleEffect(micPulse ? 1.25 : 1.0)
                    .opacity(micPulse ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: micPulse)

                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.red)
            }

            WaveformView(levels: appState.audioLevels)
                .frame(height: 32)

            HStack(spacing: 0) {
                Text("Listening")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                Text(String(repeating: ".", count: dotCount))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.4))
                    .frame(width: 20, alignment: .leading)
            }
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                    dotCount = (dotCount % 3) + 1
                }
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 16)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotCount == i ? 1.3 : 0.7)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: dotCount)
                }
            }
            .onAppear { dotCount = 1 }

            Text("Processing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))

            Spacer(minLength: 16)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red.opacity(0.8))
                .font(.system(size: 14))
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(2)
            Spacer()
            Button {
                appState.reset()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(errorVisible ? 1 : 0)
        .onAppear {
            errorVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.3)) { errorVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { appState.reset() }
            }
        }
    }

    // Stable key for driving phase transitions
    private var phaseKey: String {
        switch appState.phase {
        case .idle: "idle"
        case .recording: "recording"
        case .processing: "processing"
        case .result: "result"
        case .error: "error"
        }
    }
}
