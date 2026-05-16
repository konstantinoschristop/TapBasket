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
    /// Persisted as "more" for backward-compatibility with users seeded
    /// before the rename. New display is "Bakery"; raw value stays "more".
    case bakery = "more"
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
        case .bakery: String(localized: "category.bakery")
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
        case .bakery: "birthday.cake"
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
        case .bakery: "brown"
        case .custom: "purple"
        }
    }

    /// Visual density for the category's home-screen presentation.
    ///
    /// Alternates between vertical grids, horizontal multi-row carousels,
    /// and single chip rows so that scrolling the home feed never feels
    /// like an endless wall of identical tiles.
    ///
    ///  - `.essentials`, `.proteins` — anchor categories, vertical 2-col
    ///    grids of big tiles. Hero feel.
    ///  - `.produce`, `.pantry`, `.homeCare`, `.custom` — long browse
    ///    lists, horizontal 2-row carousels. Saves vertical space and
    ///    breaks the page rhythm.
    ///  - `.frozen`, `.drinks`, `.treats`, `.bakery` — short categories,
    ///    a single horizontal chip row.
    var layout: CategoryLayout {
        switch self {
        case .essentials, .proteins:
            return .grid(columns: 2)
        case .produce, .pantry, .homeCare, .custom:
            return .carousel(rows: 2)
        case .frozen, .drinks, .treats, .bakery:
            return .chipRow
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
        .bakery,
        .custom
    ]
}

/// How a category renders on the home screen.
///
/// - `grid(columns:)` — vertical `LazyVGrid` of full tiles.
/// - `carousel(rows:)` — horizontal `LazyHGrid` of full tiles, multiple
///   rows tall. Long categories use this to swap a tall vertical wall
///   for a wide, swipeable shelf.
/// - `chipRow` — horizontal scroll of compact pill chips, used for short
///   categories where a tall grid would feel ceremonial.
enum CategoryLayout: Equatable {
    case grid(columns: Int)
    case carousel(rows: Int)
    case chipRow
}

/// CloudKit-ready: no `@Attribute(.unique)`, every stored property has a default.
/// Uniqueness of `id` is enforced implicitly via SwiftData's primary key.
@Model
final class QuickItem: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    var sortOrder: Int = 0
    var categoryRawValue: String = QuickItemCategory.custom.rawValue
    /// User-pinned favourites surface at the top of the Regulars row
    /// regardless of how often they've been bought. Default `false` so
    /// existing data sails through the SwiftData lightweight migration.
    var pinned: Bool = false

    var category: QuickItemCategory {
        get { QuickItemCategory(rawValue: categoryRawValue) ?? .custom }
        set { categoryRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        sortOrder: Int,
        category: QuickItemCategory = .custom,
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.categoryRawValue = category.rawValue
        self.pinned = pinned
    }
}
