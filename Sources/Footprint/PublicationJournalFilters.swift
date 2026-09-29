import Foundation

struct JournalCategoryFilterState: Equatable {
    var includedCategories: Set<String> = []
    var excludedCategories: Set<String> = []

    var isActive: Bool {
        !includedCategories.isEmpty || !excludedCategories.isEmpty
    }

    func matches(categorySet: Set<String>) -> Bool {
        let matchesIncluded = includedCategories.isEmpty || !includedCategories.isDisjoint(with: categorySet)
        let avoidsExcluded = excludedCategories.isDisjoint(with: categorySet)
        return matchesIncluded && avoidsExcluded
    }
}
