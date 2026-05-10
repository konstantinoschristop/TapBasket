import Foundation
import SwiftData

enum QuickItemCategory: String, CaseIterable, Codable {
    case essentials
    case produce
    case proteins
    case pantry
    case frozen
    case drinks
    case homeCare
    case treats
    case more
    case custom

    var title: String {
        switch self {
        case .essentials: String(localized: "category.essentials")
        case .produce: String(localized: "category.produce")
        case .proteins: String(localized: "category.proteins")
        case .pantry: String(localized: "category.pantry")
        case .frozen: String(localized: "category.frozen")
        case .drinks: String(localized: "category.drinks")
        case .homeCare: String(localized: "category.home_care")
        case .treats: String(localized: "category.treats")
        case .more: String(localized: "category.more")
        case .custom: String(localized: "category.custom")
        }
    }

    var systemImageName: String {
        switch self {
        case .essentials: "basket.fill"
        case .produce: "leaf.fill"
        case .proteins: "fork.knife"
        case .pantry: "cabinet.fill"
        case .frozen: "snowflake"
        case .drinks: "cup.and.saucer.fill"
        case .homeCare: "sparkles"
        case .treats: "birthday.cake.fill"
        case .more: "square.grid.2x2.fill"
        case .custom: "pencil.and.list.clipboard"
        }
    }

    var tintName: String {
        switch self {
        case .essentials: "blue"
        case .produce: "green"
        case .proteins: "red"
        case .pantry: "orange"
        case .frozen: "cyan"
        case .drinks: "indigo"
        case .homeCare: "teal"
        case .treats: "pink"
        case .more: "gray"
        case .custom: "purple"
        }
    }

    static let orderedBrowseCategories: [QuickItemCategory] = [
        .essentials,
        .produce,
        .proteins,
        .pantry,
        .frozen,
        .drinks,
        .homeCare,
        .treats,
        .more,
        .custom
    ]
}

/// CloudKit-ready: no `@Attribute(.unique)`, every stored property has a default.
/// Uniqueness of `id` is enforced implicitly via SwiftData's primary key.
@Model
final class QuickItem {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    var sortOrder: Int = 0
    var categoryRawValue: String = QuickItemCategory.custom.rawValue

    var category: QuickItemCategory {
        get { QuickItemCategory(rawValue: categoryRawValue) ?? .custom }
        set { categoryRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        sortOrder: Int,
        category: QuickItemCategory = .custom
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.categoryRawValue = category.rawValue
    }
}