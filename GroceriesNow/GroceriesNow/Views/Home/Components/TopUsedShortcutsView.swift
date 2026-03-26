import SwiftUI

struct TopUsedShortcutItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let totalQuantity: Int
}

struct TopUsedShortcutsView: View {
    let items: [TopUsedShortcutItem]
    let onTapItem: (TopUsedShortcutItem) -> Void
    let onAddAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            grid
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top) {
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
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(items.prefix(4)) { item in
                tile(for: item)
            }
        }
    }

    private func tile(for item: TopUsedShortcutItem) -> some View {
        Button { onTapItem(item) } label: {
            VStack(spacing: 6) {
                Text(item.emoji)
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(ProductDisplayNameProvider.displayName(for: item.name))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}
