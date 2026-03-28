import SwiftUI

struct TopUsedShortcutItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let totalQuantity: Int
    let category: QuickItemCategory
}

struct TopUsedShortcutsView: View {
    let items: [TopUsedShortcutItem]
    let onTapItem: (TopUsedShortcutItem) -> Void
    let onAddAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 16)
            grid
                .safeAreaPadding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.07),
                            Color.yellow.opacity(0.04),
                            Color("CardBackground")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.7),
                            Color(red: 1.0, green: 0.48, blue: 0.08).opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: Color.orange.opacity(0.15), radius: 12, y: 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.18),
                            Color(red: 1.0, green: 0.48, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: Color.orange.opacity(0.4), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("regulars.header.title")
                    .font(.subheadline.weight(.semibold))

                Text("regulars.header.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAddAll) {
                Text("Add all")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var grid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.prefix(8)) { item in
                    chip(for: item)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 2, for: .scrollContent)
    }

    private func chip(for item: TopUsedShortcutItem) -> some View {
        Button { onTapItem(item) } label: {
            HStack(spacing: 7) {
                Text(item.emoji)
                    .font(.body)

                Text(ProductDisplayNameProvider.displayName(for: item.name))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color("LaunchBackground"), in: Capsule())
            .overlay(Capsule().stroke(tintColor(for: item.category).opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func tintColor(for category: QuickItemCategory) -> Color {
        switch category.tintName {
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
}
