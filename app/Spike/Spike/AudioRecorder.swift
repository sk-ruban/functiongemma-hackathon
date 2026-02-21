import AVFAudio
import AVFoundation
import Foundation

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var wavURL: URL?
    private var outputFile: AVAudioFile?
    private var meterTimer: Timer?
    private let onLevels: ([CGFloat]) -> Void
    private var currentPower: Float = -50

    init(onLevels: @escaping ([CGFloat]) -> Void) {
        self.onLevels = onLevels
    }

    func start() {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            print("AudioRecorder: microphone not authorized, skipping")
            return
        }

        let engine = AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        print("AudioRecorder: hardware format — \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        wavURL = url

        let monoFloat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hwFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        do {
            outputFile = try AVAudioFile(
                forWriting: url,
                settings: monoFloat.settings
            )
        } catch {
            print("AudioRecorder: failed to create output file: \(error)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: monoFloat) { [weak self] buffer, _ in
            guard let self, let file = self.outputFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("AudioRecorder: write error: \(error)")
            }
            // Compute power for waveform
            if let data = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count { sum += data[i] * data[i] }
                let rms = sqrtf(sum / Float(max(count, 1)))
                let db = 20 * log10f(max(rms, 1e-7))
                self.currentPower = db
            }
        }

        do {
            try engine.start()
        } catch {
            print("AudioRecorder: engine start failed: \(error)")
            return
        }

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let power = self.currentPower
            let normalized = CGFloat(max(0, min(1, (power + 50) / 50)))
            let levels = (0..<12).map { _ in
                normalized * CGFloat.random(in: 0.5...1.0)
            }
            self.onLevels(levels)
        }
    }

    func stop() -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil
        return wavURL
    }
}
