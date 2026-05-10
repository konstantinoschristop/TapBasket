import SwiftUI

struct TopUsedShortcutItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let totalQuantity: Int
    let category: QuickItemCategory
}

struct TopUsedShortcutsView: View {
    let items: [TopUsedShortcutItem]
    /// Set of lowercased item names currently in the basket — drives the
    /// "added" visual state per avatar. Items stay visible regardless.
    let inBasketNames: Set<String>
    let onTapItem: (TopUsedShortcutItem) -> Void
    let onAddAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, 16)
            avatarRow
        }
        .padding(.vertical, 4)
    }

    /// True when every visible regular is already in the basket — "Add all"
    /// would do nothing, so we suppress the button.
    private var allInBasket: Bool {
        items.prefix(10).allSatisfy { inBasketNames.contains($0.name.lowercased()) }
    }

    /// Header matches SmartStart and BoughtTogether: leading icon in an
    /// accent-tinted rounded square + headline title + caption subtitle +
    /// trailing accent capsule action. One pattern across all home widgets.
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
                // Up to 10 essentials. Items don't get filtered out when added —
                // they're permanent affordances; the avatar shows an "added"
                // state instead.
                ForEach(items.prefix(10)) { item in
                    RegularAvatar(
                        item: item,
                        isInBasket: inBasketNames.contains(item.name.lowercased()),
                        onTap: onTapItem
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: items.map(\.id))
        }
    }
}

/// Single circular avatar in the Regulars row.
///
/// Tap toggles membership in the basket (matches QuickItemTile). When the
/// item is in the basket, a small BrandGreen checkmark badge appears in the
/// top-right corner and the circle gains a thin green ring.
private struct RegularAvatar: View {
    let item: TopUsedShortcutItem
    let isInBasket: Bool
    let onTap: (TopUsedShortcutItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showFlash = false
    @State private var pulseToken = 0

    var body: some View {
        Button {
            // Light for add, soft for remove (matches BasketHaptics + tile behavior).
            let style: UIImpactFeedbackGenerator.FeedbackStyle = isInBasket ? .soft : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred()

            // Visual celebration only on add — don't pulse on remove.
            if !isInBasket && !reduceMotion {
                pulseToken &+= 1
                showFlash = true
                Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    await MainActor.run { showFlash = false }
                }
            }

            // Avatar stays in the row regardless of whether we're adding or
            // removing — no need to delay the callback to wait for an exit
            // animation.
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
                // Brief green glow over the avatar on add
                .overlay {
                    Circle()
                        .fill(Color("BrandGreen"))
                        .opacity(showFlash ? 0.22 : 0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: showFlash)
                        .allowsHitTesting(false)
                }
                // Expanding green ring on each tap
                .overlay {
                    AvatarPulseRing(token: pulseToken)
                        .allowsHitTesting(false)
                }
                // Top-right BrandGreen checkmark badge when added — same
                // visual language as QuickItemTile.
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
    }
}

/// Circular green ring that expands + fades each time `token` changes.
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
