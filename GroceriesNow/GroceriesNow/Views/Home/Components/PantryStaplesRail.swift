import SwiftUI

// MARK: - Model

/// Universal grocery essential — surfaced regardless of user history.
struct PantryStaple: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    /// Tint that drives the widget background. Each staple gets a consistent
    /// colour so the grid reads as a varied set of widgets, not a uniform block.
    let tint: Color
}

extension PantryStaple {
    /// Full curated list of staples in display order. Exposed so consumers
    /// (e.g. the "Add all" action) can enumerate them outside this file.
    static var all: [PantryStaple] { pantryStaples }
}

/// Muted, low-saturation tints. Bright enough to register; restrained enough
/// to stay sympathetic to the Health/Sport design direction.
private enum Tint {
    static let cream  = Color(red: 0.965, green: 0.933, blue: 0.871)
    static let butter = Color(red: 0.973, green: 0.929, blue: 0.804)
    static let peach  = Color(red: 0.969, green: 0.871, blue: 0.835)
    static let sky    = Color(red: 0.851, green: 0.910, blue: 0.957)
    static let sage   = Color(red: 0.871, green: 0.918, blue: 0.847)
    static let lilac  = Color(red: 0.910, green: 0.875, blue: 0.945)
    static let wheat  = Color(red: 0.949, green: 0.886, blue: 0.745)
}

/// Order alternates tints so adjacent widgets never share a colour.
private let pantryStaples: [PantryStaple] = [
    PantryStaple(id: "milk",      name: "Milk",      emoji: "🥛", tint: Tint.sky),
    PantryStaple(id: "bread",     name: "Bread",     emoji: "🍞", tint: Tint.cream),
    PantryStaple(id: "egg",       name: "Egg",       emoji: "🥚", tint: Tint.butter),
    PantryStaple(id: "tomato",    name: "Tomato",    emoji: "🍅", tint: Tint.peach),
    PantryStaple(id: "onion",     name: "Onion",     emoji: "🧅", tint: Tint.lilac),
    PantryStaple(id: "banana",    name: "Banana",    emoji: "🍌", tint: Tint.butter),
    PantryStaple(id: "olive oil", name: "Olive oil", emoji: "🫒", tint: Tint.sage),
    PantryStaple(id: "pasta",     name: "Pasta",     emoji: "🍝", tint: Tint.cream),
    PantryStaple(id: "apple",     name: "Apple",     emoji: "🍎", tint: Tint.peach),
    PantryStaple(id: "yogurt",    name: "Yogurt",    emoji: "🍶", tint: Tint.sky),
    PantryStaple(id: "garlic",    name: "Garlic",    emoji: "🧄", tint: Tint.lilac),
    PantryStaple(id: "potato",    name: "Potato",    emoji: "🥔", tint: Tint.wheat),
    PantryStaple(id: "butter",    name: "Butter",    emoji: "🧈", tint: Tint.butter),
    PantryStaple(id: "rice",      name: "Rice",      emoji: "🍚", tint: Tint.cream),
]

// MARK: - Rail (now a static widget grid)

/// Grid of small "widget"-style tiles for universal grocery staples.
///
/// Deliberately uses a different UI vocabulary from the category grid below —
/// colourful tinted squares with a hero emoji, no quantity badges — so the
/// section reads as its own little dashboard rather than another row of
/// generic tiles.
///
/// Shows up to 8 staples that aren't yet in the basket; as items are added,
/// remaining staples animate in to fill the gaps.
struct PantryStaplesRail: View {

    let inBasketNames: Set<String>
    let onTap: (PantryStaple) -> Void
    /// Adds every staple currently visible in the grid at once.
    let onAddAll: () -> Void

    /// 4 columns of small widgets — same density as Apple's home screen
    /// small-widget grid. Visually distinct from the 2-column category tiles
    /// further down.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 4
    )

    /// Cap the visible count so the section stays compact (2 rows max).
    /// As items get added to the basket, the next staples in the curated
    /// order rotate into view.
    private let maxVisible = 8

    private var visibleStaples: [PantryStaple] {
        Array(pantryStaples
            .filter { !inBasketNames.contains($0.id) }
            .prefix(maxVisible))
    }

    // MARK: Body

    var body: some View {
        if !visibleStaples.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.horizontal, 20)
                grid.padding(.horizontal, 20)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Header

    /// Quiet editorial header — matches the new Regulars silhouette.
    /// Pantry staples are cold-start scaffolding for new users; once
    /// the row is no longer dominant, the rest of the home screen can
    /// settle into its proper hierarchy.
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "pantry.header.title", defaultValue: "Pantry staples"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "pantry.header.subtitle", defaultValue: "Worth picking up"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAddAll) {
                Text(String(localized: "action.add_all", defaultValue: "Add all"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.spring(scale: 0.94))
            .transition(.opacity)
        }
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(visibleStaples) { item in
                widget(for: item)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // Spring the gap-fill when an item is added and the next staple
        // rotates into its slot.
        .animation(.spring(response: 0.4, dampingFraction: 0.85),
                   value: visibleStaples.map(\.id))
    }

    // MARK: Widget

    private func widget(for item: PantryStaple) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap(item)
        } label: {
            ZStack(alignment: .topTrailing) {
                // Tinted background — opacity dropped to 0.92 so the
                // colour reads as ambient rather than chip-saturated.
                RadialGradient(
                    colors: [item.tint.opacity(0.92), item.tint.opacity(0.70)],
                    center: UnitPoint(x: 0.3, y: 0.25),
                    startRadius: 4,
                    endRadius: 100
                )

                VStack(spacing: 3) {
                    Text(item.emoji)
                        .font(.system(size: 34))
                        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                    Text(item.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)

                // Quieter "+" affordance — smaller, lower-contrast disc
                // so the grid doesn't carry 8 simultaneous corner badges.
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 14, height: 14)
                    .background(Color.black.opacity(0.14), in: Circle())
                    .padding(5)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Softer tint-flavoured shadow — the grid sits inside the
            // page instead of hovering above it.
            .shadow(color: item.tint.opacity(0.30), radius: 4, y: 2)
        }
        .buttonStyle(.spring(scale: 0.94))
        .accessibilityLabel(Text(
            String(localized: "pantry.staple.a11y_format",
                   defaultValue: "Add \(item.name) to basket",
                   comment: "VoiceOver label for a pantry-staple tile. %@ is the item name.")
        ))
    }
}
