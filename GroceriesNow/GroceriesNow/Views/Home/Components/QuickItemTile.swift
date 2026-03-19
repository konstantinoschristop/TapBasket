import SwiftUI

struct QuickItemTile: View {
    let item: QuickItem
    let hintText: String?
    let isInBasket: Bool
    let action: () -> Void
    let onDelete: (() -> Void)?

    @State private var isPressed = false
    @State private var justAdded = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                isPressed = true
            }
            withAnimation(.easeIn(duration: 0.1)) {
                justAdded = true
            }
            action()

            Task {
                try? await Task.sleep(for: .milliseconds(110))
                await MainActor.run {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        isPressed = false
                    }
                }
                try? await Task.sleep(for: .milliseconds(650))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) {
                        justAdded = false
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isInBasket && !justAdded {
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
        .overlay {
            if justAdded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.18))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: justAdded)
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
