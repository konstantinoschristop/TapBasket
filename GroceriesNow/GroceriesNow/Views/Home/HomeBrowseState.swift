import Foundation

struct HomeBrowseState {
    static func defaultExpandedCategories(for sections: [QuickItemCategory]) -> Set<QuickItemCategory> {
        Set(sections)
    }
}