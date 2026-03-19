import SwiftUI

struct QuickItemTile: View {
    let item: QuickItem
    let hintText: String?
    let action: () -> Void
    let onDelete: (() -> Void)?

    @State private var isPressed = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                isPressed = true
            }
            action()

            Task {
                try? await Task.sleep(for: .milliseconds(110))
                await MainActor.run {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        isPressed = false
                    }
                }
            }
        } label: {
            VStack(spacing: 8) {
                hintBadge
                Text(item.emoji)
                    .font(.system(size: 36))
                    .scaleEffect(isPressed ? 0.96 : 1)
                Text(displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 118)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(isPressed ? 0.3 : 0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isPressed ? 0.04 : 0.08), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 4)
            .opacity(isPressed ? 0.96 : 1)
            .scaleEffect(isPressed ? 0.955 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isPressed)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Product", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var hintBadge: some View {
        if let hintText {
            Text(hintText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
                .scaleEffect(isPressed ? 0.96 : 1)
        } else {
            Color.clear
                .frame(height: 0)
        }
    }
}
