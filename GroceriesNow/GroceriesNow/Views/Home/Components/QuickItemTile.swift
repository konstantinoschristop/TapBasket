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
        // Two render paths.
        //
        // Editable items use `Menu { … } primaryAction:` so that tap
        // = the same toggle action and long-press = the Edit / Delete
        // menu. This is the deterministic alternative to `.contextMenu`,
        // which iOS 18 frequently fails to activate inside LazyV/HGrid
        // rows (the grid intercepts the long-press first).
        //
        // Non-editable items keep a Button + a LongPressGesture for the
        // +1-quantity behaviour, which is meaningless for custom items.
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
                tileContent
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
            tileContent
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.taplistTap, value: isPressed)
        }
        .buttonStyle(.plain)
    }

    /// Shared tap handler — runs whether the user taps the Button
    /// (non-editable) or triggers the Menu's primaryAction (editable).
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
            // Flat warm card fill — no diagonal gradient. Calmer,
            // more cohesive with the rest of the grid.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isInBasket ? Color("BrandGreen").opacity(0.55) : Color(.separator).opacity(0.30),
                    lineWidth: isInBasket ? 1.5 : 0.5
                )
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
        // "In basket" state: a small green dot floating top-right.
        // Quieter and cleaner than the full checkmark badge — the dot
        // reads at a glance without dominating the tile.
        .overlay(alignment: .topTrailing) {
            if isInBasket && quantity <= 1 {
                Circle()
                    .fill(Color("BrandGreen"))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color("CardBackground"), lineWidth: 1.5))
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // Quantity badge — shown only when qty > 1 (replaces the dot).
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
