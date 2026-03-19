import Foundation

struct HomeBrowseState {
    static func defaultExpandedCategories(for sections: [QuickItemCategory]) -> Set<QuickItemCategory> {
        let preferredOrder: [QuickItemCategory] = [.essentials, .produce, .homeCare, .pantry, .custom]
        let visibleSections = Set(sections)

        var expanded = Set(preferredOrder.filter { visibleSections.contains($0) }.prefix(3))

        if visibleSections.contains(.custom) {
            expanded.insert(.custom)
        }

        return expanded
    }
}