import SwiftUI

struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { i in
                let height = max(4, levels[i] * 32)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: height)
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: levels[i])
            }
        }
    }
}
