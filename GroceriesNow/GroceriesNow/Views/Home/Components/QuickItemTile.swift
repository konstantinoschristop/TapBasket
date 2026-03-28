import SwiftUI

struct QuickItemTile: View {
    let item: QuickItem
    let hintText: String?
    let isInBasket: Bool
    let action: () -> Void
    let onDelete: (() -> Void)?

    @State private var isPressed = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    private var categoryTint: Color {
        switch item.category.tintName {
        case "green":  return .green
        case "red":    return .red
        case "orange": return .orange
        case "cyan":   return .cyan
        case "indigo": return .indigo
        case "teal":   return .teal
        case "pink":   return .pink
        case "gray":   return .gray
        case "purple": return .purple
        default:       return .blue
        }
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
            tileContent
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

    private var tileContent: some View {
        VStack(spacing: 6) {
            hintBadge
            Text(item.emoji)
                .font(.system(size: 34))
                .scaleEffect(isPressed ? 0.96 : 1)
            Text(displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("CardBackground"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(categoryTint.opacity(0.05))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(categoryTint.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isInBasket {
                Image(systemName: "basket.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.accentColor, in: Circle())
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isInBasket)
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
