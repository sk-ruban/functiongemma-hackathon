import AppKit
import AVFoundation
import SwiftUI
import Observation

enum Phase: Equatable {
    case idle
    case recording
    case processing
    case result(BridgeResponse)
    case error(String)

    static func == (lhs: Phase, rhs: Phase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.processing, .processing):
            return true
        case (.result(let a), .result(let b)):
            return a.transcription == b.transcription
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@Observable
final class AppState {
    var phase: Phase = .idle
    var audioLevels: [CGFloat] = Array(repeating: 0, count: 12)
    var actionResults: [ActionResult] = []

    private var audioRecorder: AudioRecorder?
    private var hotkeyManager: HotkeyManager?
    private let bridgeClient = BridgeClient()
    private let actionDispatcher = ActionDispatcher()
    private var recordingStartDate: Date?
    private var previousApp: NSRunningApplication?

    func setup() {
        Task.detached {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                await MainActor.run { self.phase = .error("Microphone permission denied. Grant in System Settings → Privacy → Microphone.") }
            }
        }

        hotkeyManager = HotkeyManager(
            onKeyDown: { [weak self] in self?.startRecording() },
            onKeyUp: { [weak self] in self?.stopAndProcess() }
        )

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func startRecording() {
        let permission = AVAudioApplication.shared.recordPermission
        guard permission == .granted else {
            print("AppState: mic permission not granted (status: \(permission)), requesting…")
            Task.detached {
                let granted = await AVAudioApplication.requestRecordPermission()
                if !granted {
                    await MainActor.run { self.phase = .error("Microphone permission denied.") }
                }
            }
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        phase = .recording
        actionResults = []
        audioRecorder = AudioRecorder { [weak self] levels in
            self?.audioLevels = levels
        }
        recordingStartDate = Date()
        // Delay 300ms to skip the hotkey beep sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.audioRecorder?.start()
        }
    }

    func stopAndProcess() {
        if let start = recordingStartDate,
           Date().timeIntervalSince(start) < 1.5 {
            phase = .error("Hold longer to record")
            _ = audioRecorder?.stop()
            audioRecorder = nil
            recordingStartDate = nil
            return
        }
        recordingStartDate = nil

        guard let recorder = audioRecorder, let url = recorder.stop() else {
            phase = .idle
            return
        }
        audioRecorder = nil
        phase = .processing

        Task {
            do {
                let response = try await bridgeClient.transcribeAndAct(audioFileURL: url)
                phase = .result(response)

                if let app = previousApp {
                    app.activate()
                    try? await Task.sleep(for: .milliseconds(200))
                }

                let results = await actionDispatcher.dispatch(response.functionCalls)
                actionResults = results
            } catch {
                phase = .error(error.localizedDescription)
            }

            try? FileManager.default.removeItem(at: url)
        }
    }

    func reset() {
        phase = .idle
        actionResults = []
        audioLevels = Array(repeating: 0, count: 12)
    }
}
