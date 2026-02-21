import SwiftUI

struct ResultView: View {
    let response: BridgeResponse
    let actionResults: [ActionResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with source badge
            HStack {
                Text("Result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                StatusBadge(source: response.source)
            }

            // Transcription with accent bar
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                Text(response.transcription)
                    .font(.system(.body, design: .default))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }
            .fixedSize(horizontal: false, vertical: true)

            // Function calls as cards
            if !response.functionCalls.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(response.functionCalls.enumerated()), id: \.offset) { idx, call in
                        let result = idx < actionResults.count ? actionResults[idx] : nil
                        HStack(spacing: 8) {
                            Image(systemName: result?.success == true ? "checkmark.circle.fill" : result != nil ? "xmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(result?.success == true ? .green : result != nil ? .red : .secondary)
                                .font(.system(size: 12))
                            Text(call.name)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                            if let firstArg = call.arguments.values.first {
                                Text(firstArg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Timing stats as pill badges
            HStack(spacing: 6) {
                timingPill(String(format: "%.0fms", response.totalTimeMs), icon: "clock")
                timingPill(String(format: "%.0fms whisper", response.transcriptionTimeMs), icon: "waveform")
                timingPill(String(format: "%.0fms route", response.routingTimeMs), icon: "arrow.triangle.branch")
            }
        }
    }

    private func timingPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
    }
}
