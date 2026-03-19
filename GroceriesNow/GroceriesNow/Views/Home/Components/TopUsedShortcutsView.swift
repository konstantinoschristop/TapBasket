import SwiftUI

struct TopUsedShortcutItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let totalQuantity: Int
}

struct TopUsedShortcutsView: View {
    @Environment(\.locale) private var locale

    let items: [TopUsedShortcutItem]
    let onTapItem: (TopUsedShortcutItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerContent

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        shortcutChip(for: item, isPrimary: index == 0)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemBackground),
                            Color(.systemBackground).opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .padding(.horizontal)
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("regulars.header.title")
                .font(.headline)
                .fontWeight(.semibold)

            Text("regulars.header.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func shortcutChip(for item: TopUsedShortcutItem, isPrimary: Bool) -> some View {
        Button {
            onTapItem(item)
        } label: {
            HStack(spacing: 10) {
                Text(item.emoji)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(isPrimary ? 0.2 : 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductDisplayNameProvider.displayName(for: item.name))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(String(localized: "regulars.bought_count_format", defaultValue: "Bought %lldx", locale: locale).replacingOccurrences(of: "%lld", with: "\(item.totalQuantity)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isPrimary ? Color.accentColor.opacity(0.42) : Color.white.opacity(0.38), lineWidth: isPrimary ? 1.3 : 1)
            )
            .shadow(color: .black.opacity(isPrimary ? 0.1 : 0.07), radius: isPrimary ? 10 : 8, y: isPrimary ? 4 : 3)
            .scaleEffect(isPrimary ? 1.01 : 1)
        }
        .buttonStyle(.plain)
    }
}