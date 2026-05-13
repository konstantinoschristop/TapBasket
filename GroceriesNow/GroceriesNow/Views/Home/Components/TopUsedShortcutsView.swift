import SwiftUI

/// Item surfaced in the Regulars row: a top-used shortcut derived from
/// completed-basket history.
struct TopUsedShortcutItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let totalQuantity: Int
    let category: QuickItemCategory
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header.padding(.horizontal, 20)
            avatarRow
        }
        .padding(.vertical, 4)
    }

    /// True when every visible regular is already in the basket — "Add all"
    /// would be a no-op, so we suppress the button.
    private var allInBasket: Bool {
        items.prefix(10).allSatisfy { inBasketNames.contains($0.name.lowercased()) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("regulars.header.title")
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text("regulars.header.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !allInBasket {
                Button(action: onAddAll) {
                    Text("action.add_all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.spring(scale: 0.94))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.taplistTransition, value: allInBasket)
    }

    private var avatarRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(items.prefix(10)) { item in
                    RegularAvatar(
                        item: item,
                        isInBasket: inBasketNames.contains(item.name.lowercased()),
                        onTap: onTapItem
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            // Leading-only padding so the first avatar has breathing
            // room; trailing edge is open so avatars scroll cleanly off
            // the screen edge rather than stopping short.
            .padding(.leading, 20)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: items.map(\.id))
        }
    }
}

// MARK: - RegularAvatar

/// Single circular avatar in the Regulars row.
///
/// Tap toggles basket membership (matches `QuickItemTile`). When the item
/// is in the basket, a BrandGreen checkmark badge appears at top-right and
/// the circle gains a thin green ring.
private struct RegularAvatar: View {
    let item: TopUsedShortcutItem
    let isInBasket: Bool
    let onTap: (TopUsedShortcutItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showFlash = false
    @State private var pulseToken = 0

    var body: some View {
        Button {
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
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color("CardBackground"))
                    Circle()
                        .strokeBorder(
                            isInBasket ? Color("BrandGreen").opacity(0.6) : Color(.separator).opacity(0.25),
                            lineWidth: isInBasket ? 1.5 : 0.5
                        )
                    Text(item.emoji)
                        .font(.system(size: 32))
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
                .overlay(alignment: .topTrailing) {
                    if isInBasket {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color("BrandGreen"), in: Circle())
                            .overlay {
                                Circle().strokeBorder(Color("CardBackground"), lineWidth: 1.5)
                            }
                            .offset(x: 2, y: -2)
                            .transition(.scale.combined(with: .opacity))
                            .symbolEffect(.bounce, options: .nonRepeating, value: isInBasket)
                    }
                }
                .animation(.taplistCelebrate, value: isInBasket)

                Text(ProductDisplayNameProvider.displayName(for: item.name))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.spring(scale: 0.92))
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
