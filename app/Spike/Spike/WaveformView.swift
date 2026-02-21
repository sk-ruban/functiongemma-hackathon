import SwiftUI

struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(.red)
                    .frame(width: 6, height: max(4, levels[i] * 40))
                    .animation(.easeInOut(duration: 0.1), value: levels[i])
            }
        }
    }
}
