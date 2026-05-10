import SwiftUI

struct QuickItemTile: View {
    let item: QuickItem
    let isInBasket: Bool
    /// Quantity in the basket. 0 if not in basket. Used to render the ×N badge.
    let quantity: Int
    /// Tap action — toggles add/remove (parent decides).
    let action: () -> Void
    /// Long-press action — increments quantity by 1.
    let onLongPress: () -> Void
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
        Button {
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
        } label: {
            tileContent
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.taplistTap, value: isPressed)
        }
        .buttonStyle(.plain)
        // Long-press = +1 quantity. Direct gesture (no menu) — heavier medium
        // haptic distinguishes it from the light tap-add feedback. The visual
        // pulse + flash play so the user sees the add land.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    // Mark the long-press as fired so the button's release-tap
                    // bails instead of toggling.
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
        )
    }

    private var tileContent: some View {
        VStack(spacing: 8) {
            Text(item.emoji)
                .font(.system(size: 44))
                .scaleEffect(isPressed ? 0.94 : 1)

            Text(displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isInBasket ? Color("BrandGreen").opacity(0.6) : Color(.separator).opacity(0.35),
                    lineWidth: isInBasket ? 1.5 : 0.5
                )
        }
        .overlay {
            // Brief green glow that pulses across the whole tile on add.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color("BrandGreen"))
                .opacity(showFlash ? 0.20 : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: showFlash)
                .allowsHitTesting(false)
        }
        .overlay {
            // Ripple-pulse ring that expands outward when an item is added.
            AddPulseRing(token: pulseToken)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if isInBasket {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color("BrandGreen"), in: Circle())
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                    .symbolEffect(.bounce, options: .nonRepeating, value: isInBasket)
            }
        }
        // Quantity badge (×N) sits opposite the check so the two never collide.
        // Only shown when qty > 1 — qty == 1 is implied by the checkmark alone.
        .overlay(alignment: .topLeading) {
            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    // AccentColor inverts in dark mode (charcoal → white), so
                    // the badge text needs to invert too. `Color(.systemBackground)`
                    // is white in light, ~black in dark — always reads against
                    // the accent capsule.
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
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
        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
