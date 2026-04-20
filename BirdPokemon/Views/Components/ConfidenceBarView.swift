import SwiftUI

struct ConfidenceBarView: View {
    let percent: Int

    private var fillColor: Color {
        switch percent {
        case ..<40: return .red
        case ..<70: return .orange
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fillColor)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(percent, 100))) / 100)
                }
            }
            .frame(height: 8)

            Text("\(percent)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
