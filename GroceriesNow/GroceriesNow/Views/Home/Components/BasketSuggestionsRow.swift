import SwiftUI

/// "Recommended for you" row — appears once the user has enough
/// Regulars to be considered established. Surfaces items from their
/// own purchase history that aren't currently in Regulars or in the
/// basket, so the slot stays useful without ever feeling pushy.
///
/// Replaces the cold-start Pantry staples row for established users.
/// Uses the same pastel-widget visual vocabulary as Pantry staples so
/// the section reads as a soft, considered recommendation rather than
/// another chip row competing with the categories further down.
struct BasketSuggestionsRow: View {
    let items: [QuickItem]
    let inBasketNames: Set<String>
    let quantitiesByName: [String: Int]
    let onTap: (QuickItem) -> Void
    let onIncrement: (QuickItem) -> Void
    let onTogglePin: (QuickItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.horizontal, 20)
            widgetRow
        }
        .padding(.vertical, 4)
    }

    /// Quiet header — recommendations are secondary content, so the
    /// section identifies itself with a small sparkles glyph inline
    /// with the title instead of an accented icon-square. Subtitle
    /// drops to `.secondary` and `.caption2` so the row supports
    /// scanning without competing with the category content below.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.85))

            VStack(alignment: .leading, spacing: 2) {
                Text("suggestions.header.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("suggestions.header.subtitle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var widgetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    SuggestionWidget(
                        item: item,
                        isInBasket: inBasketNames.contains(item.name.lowercased()),
                        quantity: quantitiesByName[item.name.lowercased()] ?? 0,
                        onTap: { onTap(item) },
                        onLongPress: { onIncrement(item) },
                        onTogglePin: { onTogglePin(item) }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.85),
                       value: items.map(\.id))
        }
    }
}

// MARK: - SuggestionWidget

/// Pastel-tinted square widget used inside the Recommendations row.
/// Mirrors Pantry staples' visual vocabulary (radial-gradient tinted
/// background, hero emoji, small label) so the two slots feel like
/// the same idea evolving with the user: cold-start universal items
/// → personalised picks.
///
/// Tint is derived from the item's category so each widget reads as
/// a soft, identifiable category cue without screaming colour.
private struct SuggestionWidget: View {
    let item: QuickItem
    let isInBasket: Bool
    let quantity: Int
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onTogglePin: () -> Void

    private var tint: Color {
        switch item.category {
        case .essentials: return Color(red: 0.965, green: 0.933, blue: 0.871)  // cream
        case .produce:    return Color(red: 0.871, green: 0.918, blue: 0.847)  // sage
        case .proteins:   return Color(red: 0.969, green: 0.871, blue: 0.835)  // peach
        case .pantry:     return Color(red: 0.973, green: 0.929, blue: 0.804)  // butter
        case .frozen:     return Color(red: 0.851, green: 0.910, blue: 0.957)  // sky
        case .drinks:     return Color(red: 0.910, green: 0.875, blue: 0.945)  // lilac
        case .homeCare:   return Color(red: 0.849, green: 0.937, blue: 0.925)  // mist
        case .treats:     return Color(red: 0.972, green: 0.872, blue: 0.901)  // blush
        case .bakery:     return Color(red: 0.949, green: 0.886, blue: 0.745)  // wheat
        case .custom:     return Color(red: 0.918, green: 0.886, blue: 0.949)  // soft lilac
        }
    }

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        Menu {
            Button {
                onTogglePin()
            } label: {
                Label(
                    item.pinned
                        ? String(localized: "action.unpin", defaultValue: "Unpin")
                        : String(localized: "action.pin", defaultValue: "Pin"),
                    systemImage: item.pinned ? "pin.slash" : "pin"
                )
            }
            if isInBasket {
                Button {
                    onLongPress()
                } label: {
                    Label(String(localized: "action.add_one_more", defaultValue: "Add one more"),
                          systemImage: "plus")
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                // Softer tint wash — 92% so the widget reads as a hint
                // of colour rather than a saturated chip competing with
                // the primary grid below. In-basket state quietly dims
                // the widget instead of stamping a coloured dot on it.
                RadialGradient(
                    colors: [tint.opacity(0.92), tint.opacity(0.70)],
                    center: UnitPoint(x: 0.3, y: 0.25),
                    startRadius: 4,
                    endRadius: 100
                )

                VStack(spacing: 3) {
                    Text(item.emoji)
                        .font(.system(size: 32))
                        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)

                // Persistent dot removed. ×N stays — it carries genuine
                // information (quantity), not just state signaling.
                if quantity > 1 {
                    Text("×\(quantity)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color("BrandGreen"), in: Capsule())
                        .padding(6)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Softened tint shadow — the widget settles into the layout
            // instead of casting a coloured halo around itself.
            .shadow(color: tint.opacity(0.30), radius: 4, y: 2)
            .opacity(isInBasket ? 0.62 : 1)
        } primaryAction: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
    }
}
