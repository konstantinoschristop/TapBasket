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
        widgetContainer
            .padding(.horizontal)
    }

    @ViewBuilder
    private var widgetContainer: some View {
        let base = VStack(alignment: .leading, spacing: 12) {
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

        base.adaptiveGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            chipContent(for: item, isPrimary: isPrimary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chipContent(for item: TopUsedShortcutItem, isPrimary: Bool) -> some View {
        let base = HStack(spacing: 10) {
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
        .scaleEffect(isPrimary ? 1.01 : 1)

        base.adaptiveGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}