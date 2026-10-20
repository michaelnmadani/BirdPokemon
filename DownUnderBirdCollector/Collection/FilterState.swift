import Foundation
import SwiftUI

@MainActor
final class FilterState: ObservableObject {
    @Published var criteria = FilterCriteria()
    @Published var showFilterSheet = false

    /// Clears filters but keeps whatever is typed in the search field.
    func reset() {
        let search = criteria.searchText
        criteria = FilterCriteria()
        criteria.searchText = search
    }
}
