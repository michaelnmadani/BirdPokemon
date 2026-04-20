import SwiftUI

struct FilterSheetView: View {
    @ObservedObject var state: FilterState
    let availableFamilies: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Region") {
                    ForEach(Region.allCases) { region in
                        Toggle(isOn: Binding(
                            get: { state.criteria.regions.contains(region) },
                            set: { isOn in
                                if isOn { state.criteria.regions.insert(region) }
                                else { state.criteria.regions.remove(region) }
                            }
                        )) {
                            Text("\(region.flag) \(region.displayName)")
                        }
                    }
                }

                Section("Size") {
                    ForEach(SizeCategory.allCases) { size in
                        Toggle(isOn: Binding(
                            get: { state.criteria.sizes.contains(size) },
                            set: { isOn in
                                if isOn { state.criteria.sizes.insert(size) }
                                else { state.criteria.sizes.remove(size) }
                            }
                        )) {
                            HStack {
                                Text(size.displayName)
                                Spacer()
                                Text(size.approxLength)
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }
                    }
                }

                Section("Primary colours") {
                    let columns = [GridItem(.adaptive(minimum: 80))]
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(BirdColor.allCases) { color in
                            colorChip(color)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Family") {
                    if availableFamilies.isEmpty {
                        Text("No families loaded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableFamilies, id: \.self) { family in
                            Toggle(family, isOn: Binding(
                                get: { state.criteria.families.contains(family) },
                                set: { isOn in
                                    if isOn { state.criteria.families.insert(family) }
                                    else { state.criteria.families.remove(family) }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { state.reset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func colorChip(_ color: BirdColor) -> some View {
        let isOn = state.criteria.colors.contains(color)
        return Button {
            if isOn { state.criteria.colors.remove(color) }
            else { state.criteria.colors.insert(color) }
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(color.swiftUIColor)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                    .frame(width: 32, height: 32)
                Text(color.displayName)
                    .font(.caption2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.accentColor.opacity(0.2) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
