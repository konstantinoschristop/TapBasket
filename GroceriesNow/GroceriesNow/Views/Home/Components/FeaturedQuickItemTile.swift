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
    /// Edit / delete callbacks for user-created items. Surfaced via
    /// the Menu's long-press affordance. Pass `nil` if not editable.
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// Explicit width when the tile lives in a horizontal carousel.
    /// Pass `nil` when used in a vertical grid where it should fill
    /// the row.
    var width: CGFloat? = nil
    /// Explicit height; defaults to a tall card that contrasts the
    /// 108pt standard tile.
    var height: CGFloat = 160

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showFlash = false
    @State private var pulseToken: Int = 0
    @State private var didLongPress = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        // Editable items use `Menu` with a `primaryAction:` so tap fires
        // the same toggle action, and long-press shows Edit / Delete —
        // deterministic alternative to `.contextMenu`, which iOS 18
        // frequently fails to activate inside Lazy grids.
        if isEditable {
            Menu {
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
            } label: {
                content
                    .scaleEffect(isPressed ? 0.97 : 1.0)
                    .animation(.taplistTap, value: isPressed)
            } primaryAction: {
                performTap()
            }
            .buttonStyle(.plain)
            .menuOrder(.fixed)
        } else {
            tileButton
                .simultaneousGesture(longPressIncrement)
        }
    }

    private var tileButton: some View {
        Button {
            performTap()
        } label: {
            content
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.taplistTap, value: isPressed)
        }
        .buttonStyle(.plain)
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

    private var longPressIncrement: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                didLongPress = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if !reduceMotion {
                    pulseToken &+= 1
                    showFlash = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(550))
                        await MainActor.run { showFlash = false }
                    }
                }
                onLongPress()
            }
    }

    private var content: some View {
        ZStack(alignment: .bottomTrailing) {
            // Hero emoji — much bigger than the standard tile so the
            // featured slot reads as "the headline".
            Text(item.emoji)
                .font(.system(size: 88))
                .scaleEffect(isPressed ? 0.94 : 1)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                .padding(.bottom, 6)
                .padding(.trailing, 6)

            // Label + small "Featured" / "Bought 8x" cue on top-left.
            VStack(alignment: .leading, spacing: 4) {
                Text(metaText ?? String(localized: "featured.label"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text(displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background {
            // Warmer two-stop gradient than the standard tile — a
            // subtle accent wash gives the featured slot a different
            // tonal signature.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color("CardBackground"),
                            Color.accentColor.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isInBasket
                            ? [Color("BrandGreen").opacity(0.6), Color("BrandGreen").opacity(0.25)]
                            : [Color.white.opacity(0.55), Color(.separator).opacity(0.30)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isInBasket ? 1.5 : 0.75
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color("BrandGreen"))
                .opacity(showFlash ? 0.18 : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: showFlash)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if isInBasket && quantity <= 1 {
                Circle()
                    .fill(Color("BrandGreen"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color("CardBackground"), lineWidth: 1.5))
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
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
