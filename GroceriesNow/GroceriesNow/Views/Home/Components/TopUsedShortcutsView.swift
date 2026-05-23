import SwiftUI

/// Item surfaced in the Regulars row: a top-used shortcut derived from
/// completed-basket history.
struct TopUsedShortcutItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let totalQuantity: Int
    let category: QuickItemCategory
    /// True when the user has explicitly pinned this item. Lets the
    /// avatar render a subtle pin glyph and the menu offer "Unpin"
    /// instead of "Pin". Auto-derived (history-only) shortcuts are
    /// `false` here and look identical to before.
    let isPinned: Bool
}

/// Horizontal row of circular avatars for the user's most-bought items.
///
/// Items stay visible even when added to the basket — the avatar gains an
/// "added" state (green ring + checkmark) instead of disappearing — because
/// Regulars are essential affordances, not one-shot suggestions.
struct TopUsedShortcutsView: View {
    let items: [TopUsedShortcutItem]
    /// Lowercased names of items currently in the basket — drives the
    /// "added" visual state per avatar.
    let inBasketNames: Set<String>
    let onTapItem: (TopUsedShortcutItem) -> Void
    let onAddAll: () -> Void
    /// Fired when the user taps the empty-state "+" — the parent opens
    /// a picker so the user can pin items in bulk.
    let onPickFavorites: () -> Void
    /// Toggles the underlying `QuickItem.pinned` flag. Surfaced from
    /// the avatar's long-press menu so the user can unpin a regular
    /// without leaving the home screen.
    let onToggleItemPin: (TopUsedShortcutItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.horizontal, 20)
            avatarRow
        }
        .padding(.vertical, 4)
    }

    /// True when every visible regular is already in the basket — "Add all"
    /// would be a no-op, so we suppress the button. Also true (vacuously)
    /// when there are no items at all, so the pill hides in the empty state.
    private var allInBasket: Bool {
        guard !items.isEmpty else { return true }
        return items.prefix(10).allSatisfy { inBasketNames.contains($0.name.lowercased()) }
    }

    /// Quieter editorial header — single line, no accented icon-square.
    /// Subtitle drops to `.secondary` so the row reads as a labelled
    /// shelf rather than a hero card. "Add all" stays as the only
    /// active visual in the right rail.
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("regulars.header.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(items.isEmpty ? "regulars.empty.subtitle" : "regulars.header.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !allInBasket {
                Button(action: onAddAll) {
                    Text("action.add_all")
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
        .animation(.taplistTransition, value: allInBasket)
    }

    /// Avatar row.
    ///
    /// Two presentations:
    ///   - **Empty state** — single inline plus cell + Spacer. The
    ///     2-row scrollable grid would just hold a tall blank space
    ///     under the plus and read as a placeholder; collapsing to
    ///     one row makes the empty state feel intentional.
    ///   - **Populated** — `LazyHGrid` with the items first and the
    ///     plus as the **trailing** cell. Column-major filling means
    ///     the first item (the highest-priority pinned regular) lands
    ///     at top-left where the eye starts scanning. The "+" sits at
    ///     the end of the row as a quieter "add more" affordance —
    ///     still on-screen for short rows, scrollable-to for longer
    ///     ones.
    @ViewBuilder
    private var avatarRow: some View {
        if items.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                plusCell
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [
                        GridItem(.fixed(96), spacing: 8),
                        GridItem(.fixed(96), spacing: 8)
                    ],
                    alignment: .top,
                    spacing: 14
                ) {
                    ForEach(items.prefix(14)) { item in
                        RegularAvatar(
                            item: item,
                            isInBasket: inBasketNames.contains(item.name.lowercased()),
                            onTap: onTapItem,
                            onTogglePin: onToggleItemPin
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    plusCell
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: items.map(\.id))
            }
        }
    }

    /// Plus cell — sized and shaped exactly like a `RegularAvatar` so
    /// it slots into the LazyHGrid without breaking the row's rhythm.
    /// Pulses only while the section is empty; once the user has any
    /// pinned items, the cell sits quietly alongside them.
    private var plusCell: some View {
        Button(action: onPickFavorites) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(items.isEmpty ? 1 : 0.85))
                        .symbolEffect(.pulse, options: .repeating, isActive: items.isEmpty)
                }
                .frame(width: 64, height: 64)

                Text(items.isEmpty ? "regulars.plus.empty_label" : "regulars.plus.label")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.spring(scale: 0.94))
        .accessibilityLabel(Text("regulars.plus.a11y_label"))
    }
}

// MARK: - RegularAvatar

/// Single circular avatar in the Regulars row.
///
/// Tap toggles basket membership (matches `QuickItemTile`). Long-press
/// surfaces a `Menu` so the user can pin / unpin the item without
/// leaving the home screen. Pinned items get a small accent pin glyph
/// at the top-left so the user can distinguish their explicit picks
/// from auto-derived (history-based) regulars at a glance.
private struct RegularAvatar: View {
    let item: TopUsedShortcutItem
    let isInBasket: Bool
    let onTap: (TopUsedShortcutItem) -> Void
    let onTogglePin: (TopUsedShortcutItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showFlash = false
    @State private var pulseToken = 0

    var body: some View {
        Menu {
            Button {
                onTogglePin(item)
            } label: {
                Label(
                    item.isPinned
                        ? String(localized: "action.unpin", defaultValue: "Unpin")
                        : String(localized: "action.pin", defaultValue: "Pin"),
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Single neutral surface. In-basket carries a barely-
                    // there BrandGreen wash instead of a coloured ring —
                    // the avatar reads as "settled" instead of decorated.
                    Circle()
                        .fill(Color("CardBackground"))
                    Circle()
                        .fill(Color("BrandGreen").opacity(isInBasket ? 0.07 : 0))
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
                    Text(item.emoji)
                        .font(.system(size: 32))
                        .opacity(isInBasket ? 0.88 : 1)
                }
                .frame(width: 64, height: 64)
                .overlay {
                    Circle()
                        .fill(Color("BrandGreen"))
                        .opacity(showFlash ? 0.22 : 0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: showFlash)
                        .allowsHitTesting(false)
                }
                .overlay {
                    AvatarPulseRing(token: pulseToken)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if item.isPinned {
                        // Quieter pin marker: tinted glyph on the card
                        // surface, no coloured fill, no white ring. Reads
                        // as a hint, not a badge.
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor.opacity(0.85))
                            .padding(3)
                            .background(Color("CardBackground"), in: Circle())
                            .offset(x: -1, y: -1)
                            .transition(.opacity)
                    }
                }
                // No persistent in-basket checkmark badge. The temporary
                // AvatarPulseRing + the subtle wash are enough state cue;
                // a permanent badge would re-introduce the visual noise
                // the rest of the grid is shedding.
                .animation(.taplistCelebrate, value: isInBasket)
                .animation(.taplistCelebrate, value: item.isPinned)

                Text(ProductDisplayNameProvider.displayName(for: item.name))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        } primaryAction: {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = isInBasket ? .soft : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred()

            if !isInBasket && !reduceMotion {
                pulseToken &+= 1
                showFlash = true
                Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    await MainActor.run { showFlash = false }
                }
            }

            onTap(item)
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityLabel(Text(
            String(
                localized: isInBasket
                    ? "regulars.avatar.a11y_remove_format"
                    : "regulars.avatar.a11y_add_format",
                defaultValue: isInBasket
                    ? "Remove \(ProductDisplayNameProvider.displayName(for: item.name)) from basket"
                    : "Add \(ProductDisplayNameProvider.displayName(for: item.name)) to basket",
                comment: "VoiceOver label for a regular-item avatar. %@ is the item name."
            )
        ))
    }
}

/// Circular green ring that expands + fades each time `token` changes —
/// played as a celebration on every add.
private struct AvatarPulseRing: View {
    let token: Int

    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .strokeBorder(Color("BrandGreen"), lineWidth: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: token) { _, _ in play() }
    }

    private func play() {
        scale = 1
        opacity = 0.9
        withAnimation(.easeOut(duration: 0.5)) {
            scale = 1.18
            opacity = 0
        }
    }
}
