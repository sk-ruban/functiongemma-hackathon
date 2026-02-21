import SwiftUI

struct ResultView: View {
    let response: BridgeResponse
    let actionResults: [ActionResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\"\(response.transcription)\"")
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                StatusBadge(source: response.source)
            }

            if !response.functionCalls.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(response.functionCalls.enumerated()), id: \.offset) { idx, call in
                        HStack(spacing: 6) {
                            let result = idx < actionResults.count ? actionResults[idx] : nil
                            Image(systemName: result?.success == true ? "checkmark.circle.fill" : result != nil ? "xmark.circle.fill" : "circle")
                                .foregroundStyle(result?.success == true ? .green : result != nil ? .red : .secondary)
                                .font(.caption)
                            Text("\(call.name)")
                                .font(.caption.monospaced())
                            if let firstArg = call.arguments.values.first {
                                Text(firstArg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Label(String(format: "%.0fms", response.totalTimeMs), systemImage: "clock")
                Label(String(format: "%.0fms transcribe", response.transcriptionTimeMs), systemImage: "waveform")
                Label(String(format: "%.0fms route", response.routingTimeMs), systemImage: "arrow.triangle.branch")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
