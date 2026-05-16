import SwiftUI

/// Featured "hero" variant of `QuickItemTile`. Sits at the start of every
/// category section so the first item reads as editorial — bigger
/// emoji, more presence, a sticker shadow with attitude — while the
/// remaining items in the category render at standard size.
///
/// Same tap / long-press semantics and pulse + flash celebration as the
/// standard tile; only the geometry and the emoji weight change.
struct FeaturedQuickItemTile: View {
    let item: QuickItem
    let isInBasket: Bool
    let quantity: Int
    /// True when the user can edit / delete this item. Parent decides.
    let isEditable: Bool
    /// Subtle metadata line above the item name — e.g. "Bought 8x".
    /// When `nil`, the standard "Featured" cue is used instead.
    var metaText: String? = nil
    let action: () -> Void
    let onLongPress: () -> Void
    let onTogglePin: () -> Void
    /// Edit / delete callbacks for user-created items. Surfaced via
    /// the Menu's long-press affordance. Pass `nil` if not editable.
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// Explicit width when the tile lives in a horizontal carousel.
    /// Pass `nil` when used in a vertical grid where it should fill
    /// the row.
    var width: CGFloat? = nil
    /// Explicit height; defaults to a card that's clearly taller than
    /// the 108pt standard tile without dominating the screen. Tightened
    /// from 160 → 136 (-15%) so featured slots guide scanning rather
    /// than swallow it.
    var height: CGFloat = 136

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showFlash = false
    @State private var pulseToken: Int = 0
    @State private var didLongPress = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        // Same Menu + primaryAction pattern as the standard tile.
        // Tap → toggle; long-press → menu with pin / add-one-more /
        // edit / delete (last two only for editable items).
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

            if isEditable {
                Button {
                    onEdit?()
                } label: {
                    Label("action.edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("action.delete", systemImage: "trash")
                }
            }
        } label: {
            content
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.taplistTap, value: isPressed)
        } primaryAction: {
            performTap()
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
    }

    private func performTap() {
        if didLongPress { didLongPress = false; return }

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

        withAnimation(.taplistOrNone(.taplistTap, reduceMotion: reduceMotion)) {
            isPressed = true
        }
        action()

        Task {
            try? await Task.sleep(for: .milliseconds(110))
            await MainActor.run {
                withAnimation(.taplistTap) { isPressed = false }
            }
        }
    }

    private var content: some View {
        ZStack(alignment: .bottomTrailing) {
            // Hero emoji — still the headline, but quieter than the old
            // 88pt monolith. 76pt holds its own next to a tighter card
            // without competing with adjacent category content.
            Text(item.emoji)
                .font(.system(size: 76))
                .scaleEffect(isPressed ? 0.94 : 1)
                .shadow(color: .black.opacity(0.14), radius: 3.5, y: 1.5)
                .padding(.bottom, 6)
                .padding(.trailing, 6)

            // Label + small "Featured" / "Bought 8x" cue on top-left.
            // The caption is intentionally tiny + uppercase + tracked
            // so it reads as editorial metadata rather than UI chrome,
            // but `.semibold` keeps it legible at this size. Item name
            // stays the dominant element via larger weight + primary
            // ink contrast.
            VStack(alignment: .leading, spacing: 4) {
                Text(metaText ?? String(localized: "featured.label"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background {
            // Warmer two-stop gradient with a quieter accent terminus —
            // signature stays, dominance drops. In-basket gets the same
            // barely-there BrandGreen wash used on standard tiles, so
            // the featured slot reads from the same calm vocabulary.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color("CardBackground"),
                            Color.accentColor.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color("BrandGreen").opacity(isInBasket ? 0.055 : 0))
                }
                .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
        }
        .overlay {
            // Uniform hairline at all times — no border swap on state
            // change. The card stays a calm surface.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color("BrandGreen"))
                .opacity(showFlash ? 0.18 : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: showFlash)
                .allowsHitTesting(false)
        }
        // Quantity badge — shown only when qty > 1. Below that the
        // background tint carries the in-basket signal.
        .overlay(alignment: .topTrailing) {
            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color("BrandGreen"), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color("CardBackground"), lineWidth: 1))
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                    .contentTransition(.numericText(value: Double(quantity)))
            }
        }
        .animation(.taplistCelebrate, value: isInBasket)
        .animation(.taplistCelebrate, value: quantity)
    }
}
