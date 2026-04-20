import SwiftUI

struct FilterBarView: View {
    @ObservedObject var state: FilterState

    var body: some View {
        HStack {
            Button {
                state.showFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filters")
                    if state.criteria.activeFilterCount > 0 {
                        Text("\(state.criteria.activeFilterCount)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            if !state.criteria.isEmpty {
                Button("Clear") { state.reset() }
                    .font(.footnote)
            }
        }
        .padding(.horizontal)
    }
}
