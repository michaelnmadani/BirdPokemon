import Foundation
import SwiftUI

@MainActor
final class FilterState: ObservableObject {
    @Published var criteria: FilterCriteria = FilterCriteria()
    @Published var showFilterSheet: Bool = false

    func reset() {
        criteria = FilterCriteria()
    }
}
