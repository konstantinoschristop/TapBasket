import SwiftUI

struct CollapsibleQuickItemSection<Content: View>: View {
    let title: String
    let systemImageName: String
    let tintName: String
    let itemCount: Int
    let usageCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerButton

            if isExpanded {
                content()
                    .transition(.opacity)
            }
        }
    }

    private var headerButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(headerTint)
                    .frame(width: 32, height: 32)
                    .background(headerTint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("\(itemCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if usageCount > 0 {
                    Text("Top \(usageCount)x")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(headerTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(headerTint.opacity(0.12))
                        .clipShape(Capsule())
                }

                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerTint: Color {
        switch tintName {
        case "green": .green
        case "red": .red
        case "orange": .orange
        case "cyan": .cyan
        case "indigo": .indigo
        case "teal": .teal
        case "pink": .pink
        case "gray": .gray
        case "purple": .purple
        default: .blue
        }
    }
}