import SwiftUI

/// Compact pill version of `QuickItemTile`, used in horizontal-scroll lanes
/// for short categories (Frozen, Drinks, Treats, Bakery).
///
/// Same tap/long-press semantics as `QuickItemTile`:
///   - Tap: toggle membership in the basket (parent decides add vs. remove)
///   - Long-press: increment quantity by 1
struct QuickItemChip: View {
    let item: QuickItem
    let isInBasket: Bool
    let quantity: Int
    let action: () -> Void
    let onLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    /// Set when a `LongPressGesture` succeeds — the Button's tap action
    /// checks this and bails so the +1 isn't immediately followed by the
    /// release-tap's toggle (which would remove what was just incremented).
    @State private var didLongPress = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        Button {
            if didLongPress {
                didLongPress = false
                return
            }

            let style: UIImpactFeedbackGenerator.FeedbackStyle = isInBasket ? .soft : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred()

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
        } label: {
            content
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.taplistTap, value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    didLongPress = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                }
        )
    }

    private var content: some View {
        HStack(spacing: 8) {
            Text(item.emoji)
                .font(.title2)
                // Soft sticker shadow to match the tile treatment.
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)

            Text(displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color("BrandGreen"), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                    .contentTransition(.numericText(value: Double(quantity)))
            } else if isInBasket {
                Circle()
                    .fill(Color("BrandGreen"))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color("CardBackground"), lineWidth: 1.2))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            // Flat warm fill — matches the tile's flat surface so the
            // grid reads as one cohesive system.
            Capsule()
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .overlay {
            Capsule().stroke(
                isInBasket ? Color("BrandGreen").opacity(0.55) : Color(.separator).opacity(0.30),
                lineWidth: isInBasket ? 1.5 : 0.5
            )
        }
        .animation(.taplistCelebrate, value: isInBasket)
        .animation(.taplistCelebrate, value: quantity)
    }
}
