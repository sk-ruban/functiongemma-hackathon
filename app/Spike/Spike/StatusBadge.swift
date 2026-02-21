import SwiftUI

struct StatusBadge: View {
    let source: String

    private var isOnDevice: Bool {
        source.lowercased().contains("on-device") || source.lowercased().contains("local")
    }

    var body: some View {
        Text(isOnDevice ? "On-Device" : "Cloud")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOnDevice ? Color.green : Color.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
