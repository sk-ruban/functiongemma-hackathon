import SwiftUI

struct StatusBadge: View {
    let source: String

    private var isOnDevice: Bool {
        source.lowercased().contains("on-device") || source.lowercased().contains("local")
    }

    var body: some View {
        Label(
            isOnDevice ? "On-Device" : "Cloud",
            systemImage: isOnDevice ? "cpu" : "cloud"
        )
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(isOnDevice ? Color.green : Color.blue)
        .background(
            Capsule()
                .fill((isOnDevice ? Color.green : Color.blue).opacity(isOnDevice ? 0.15 : 0))
                .strokeBorder(isOnDevice ? Color.green.opacity(0.4) : Color.blue.opacity(0.4), lineWidth: 1)
        )
    }
}
