import SwiftUI

struct QuickItemTile: View {
    let item: QuickItem
    let isInBasket: Bool
    /// Quantity in the basket. 0 if not in basket. Used to render the ×N badge.
    let quantity: Int
    /// True when the user can edit / delete this item — i.e. it was
    /// added by them, regardless of which category they put it in. The
    /// parent decides; the tile just renders the affordance.
    let isEditable: Bool
    /// Tap action — toggles add/remove (parent decides).
    let action: () -> Void
    /// Long-press action — increments quantity by 1.
    let onLongPress: () -> Void
    /// Pin / unpin toggle. Always available — non-editable seed items
    /// are still pinnable.
    let onTogglePin: () -> Void
    /// Edit action — non-nil only for editable items. Surfaced via the
    /// Menu's long-press affordance.
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showFlash = false

    /// Ripple-pulse trigger: changes value each time we want to play the
    /// "item added" ring expansion. The overlay watches this and animates.
    @State private var pulseToken: Int = 0

    /// Set to `true` when a `LongPressGesture` succeeds. The Button's tap
    /// action checks this on release and bails — otherwise the user holds for
    /// +1, releases, and the toggle would immediately remove what was just
    /// incremented. Reset to `false` after the suppressed tap.
    @State private var didLongPress = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        // Every tile uses a `Menu { … } primaryAction:` so tap fires
        // the toggle and long-press surfaces the menu. Menu contents
        // adapt to the item: pin/unpin always, "Add one more" when
        // the item is already in the basket, edit/delete for items
        // the user created.
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
            tileContent
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.taplistTap, value: isPressed)
        } primaryAction: {
            performTap()
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
    }

    /// Tap handler — runs from the Menu's `primaryAction`.
    private func performTap() {
        // Suppress the tap when it's actually the release after a
        // successful long-press — otherwise +1 would be immediately
        // followed by the toggle (= remove), wiping the increment.
        if didLongPress {
            didLongPress = false
            return
        }

        // Tap = toggle. Light for add, soft for remove (matches BasketHaptics).
        let style: UIImpactFeedbackGenerator.FeedbackStyle = isInBasket ? .soft : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()

        // Only celebrate add taps — removing shouldn't pulse.
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
                withAnimation(.taplistTap) {
                    isPressed = false
                }
            }
        }
    }

    private var tileContent: some View {
        ZStack(alignment: .bottomTrailing) {
            // Hero emoji — anchored bottom-right with a soft sticker shadow.
            // Makes the tile feel like a product on a shelf rather than a
            // generic centred label.
            Text(item.emoji)
                .font(.system(size: 54))
                .scaleEffect(isPressed ? 0.94 : 1)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
                .padding(.bottom, 4)
                .padding(.trailing, 4)

            // Label — top-leading, modest weight. The emoji is the
            // protagonist; the label is the caption.
            VStack(alignment: .leading) {
                Text(displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        .background {
            // Flat warm card fill. In-basket state gets a barely-there
            // BrandGreen wash on top of the card so the tile looks
            // "settled" rather than ringed. Idle tiles read as neutral
            // surfaces; only the live add-pulse uses a saturated border.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("CardBackground"))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color("BrandGreen").opacity(isInBasket ? 0.055 : 0))
                }
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .overlay {
            // Single uniform hairline at all times — the grid reads as
            // one calm surface instead of vibrating between idle/active.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
        }
        .overlay {
            // Brief green glow on add.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("BrandGreen"))
                .opacity(showFlash ? 0.18 : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: showFlash)
                .allowsHitTesting(false)
        }
        .overlay {
            AddPulseRing(token: pulseToken)
                .allowsHitTesting(false)
        }
        // Quantity badge — shown only when qty > 1. Below quantity 2
        // the tile relies on the subtle background tint to signal
        // membership; no persistent corner indicator.
        .overlay(alignment: .topTrailing) {
            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color("BrandGreen"), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color("CardBackground"), lineWidth: 1))
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                    .contentTransition(.numericText(value: Double(quantity)))
                    .symbolEffect(.bounce, options: .nonRepeating, value: quantity)
            }
        }
        .animation(.taplistCelebrate, value: isInBasket)
        .animation(.taplistCelebrate, value: quantity)
    }
}

/// Animates a green border that scales out + fades each time `token` changes.
/// Implemented as a separate view so its state is independent per tile.
private struct AddPulseRing: View {
    let token: Int

    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color("BrandGreen"), lineWidth: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: token) { _, _ in
                play()
            }
    }

    private func play() {
        // Reset instantly to start state, then expand + fade.
        scale = 1
        opacity = 0.9
        withAnimation(.easeOut(duration: 0.45)) {
            scale = 1.08
            opacity = 0
        }
    }
}
