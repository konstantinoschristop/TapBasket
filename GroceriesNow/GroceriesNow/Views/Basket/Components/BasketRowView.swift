import SwiftUI

struct BasketRowView: View {
    let item: BasketItem
    let onToggleChecked: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onEditNote: () -> Void

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.title2)
                .scaleEffect(item.isChecked ? 0.9 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: item.note)

            Spacer()

            Button(action: onEditNote) {
                Image(systemName: item.note?.isEmpty == false ? "note.text" : "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(.secondarySystemBackground).opacity(item.note?.isEmpty == false ? 1 : 0.01))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            QuantityStepperView(
                quantity: item.quantity,
                onDecrement: onDecrement,
                onIncrement: onIncrement
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(item.isChecked ? 0.72 : 1)
        .scaleEffect(item.isChecked ? 0.992 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: item.isChecked)
        .onTapGesture(perform: onToggleChecked)
    }
}