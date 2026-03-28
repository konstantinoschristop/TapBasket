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
                    .foregroundStyle(item.note?.isEmpty == false ? Color.green : .secondary)
                    .padding(6)
                    .background(Color("LaunchBackground").opacity(item.note?.isEmpty == false ? 1 : 0.01))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            QuantityStepperView(
                quantity: item.quantity,
                onDecrement: onDecrement,
                onIncrement: onIncrement
            )
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(item.isChecked ? 0.2 : 0.55), Color.green.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .opacity(item.isChecked ? 0.6 : 1)
        .scaleEffect(item.isChecked ? 0.992 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: item.isChecked)
        .onTapGesture(perform: onToggleChecked)
    }
}