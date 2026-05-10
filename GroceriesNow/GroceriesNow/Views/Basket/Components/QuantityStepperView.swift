import SwiftUI

/// Compact pill-style quantity stepper used in basket rows.
/// Buttons are flush, count is monospaced, the whole control sits on a tinted fill.
struct QuantityStepperView: View {
    let quantity: Int
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.footnote.weight(.bold))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(quantity <= 1)

            Text("\(quantity)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.label))
                .frame(minWidth: 22)
                .contentTransition(.numericText(value: Double(quantity)))

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.accentColor)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .overlay(Capsule().stroke(Color(.separator).opacity(0.25), lineWidth: 0.5))
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: quantity)
    }
}
