import SwiftUI

struct QuantityStepperView: View {
    let quantity: Int
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDecrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Text("\(quantity)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(minWidth: 22)
                .foregroundStyle(.primary)

            Button(action: onIncrement) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.green)
    }
}
