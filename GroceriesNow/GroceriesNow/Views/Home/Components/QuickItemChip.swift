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
    let onTogglePin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        // Same Menu + primaryAction pattern as `QuickItemTile`.
        // Tap → toggle add/remove; long-press → pin / +1 menu.
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
            content
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.taplistTap, value: isPressed)
        } primaryAction: {
            performTap()
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
    }

    private func performTap() {
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
            }
            // No corner dot for the qty == 1 case — the chip's subtle
            // background tint shift (below) is enough state signal.
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            // Flat warm fill + barely-there BrandGreen wash when in
            // basket. Single neutral surface; no border vibration.
            Capsule()
                .fill(Color("CardBackground"))
                .overlay {
                    Capsule().fill(Color("BrandGreen").opacity(isInBasket ? 0.055 : 0))
                }
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .overlay {
            Capsule().stroke(Color(.separator).opacity(0.30), lineWidth: 0.5)
        }
        .animation(.taplistCelebrate, value: isInBasket)
        .animation(.taplistCelebrate, value: quantity)
    }
}
