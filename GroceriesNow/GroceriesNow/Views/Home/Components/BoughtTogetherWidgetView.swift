import SwiftUI

struct BoughtTogetherWidgetItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let emojiSummary: String
}

struct BoughtTogetherWidgetView: View {
    let items: [BoughtTogetherWidgetItem]
    let onTapItem: (BoughtTogetherWidgetItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerContent

            VStack(spacing: 10) {
                ForEach(items) { item in
                    suggestionCard(for: item)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")

                Text("contextual_pair.header.title")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Text("contextual_pair.header.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func suggestionCard(for item: BoughtTogetherWidgetItem) -> some View {
        Button {
            onTapItem(item)
        } label: {
            HStack(spacing: 12) {
                Text(item.emojiSummary)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("action.add")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}