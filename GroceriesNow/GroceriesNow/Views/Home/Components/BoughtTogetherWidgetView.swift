import SwiftUI

struct BoughtTogetherWidgetItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let emojiSummary: String
}

/// "Often bought with X" suggestions surfaced from the recommendation engine.
///
/// Visual language deliberately matches `SmartStartView` and the rest of the
/// home screen widgets: `.adaptiveGlass` container, charcoal/BrandGreen palette,
/// soft tile-style shadow, no hardcoded `.white` or `.regularMaterial`.
struct BoughtTogetherWidgetView: View {
    let items: [BoughtTogetherWidgetItem]
    let onTapItem: (BoughtTogetherWidgetItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 8) {
                ForEach(items) { item in
                    suggestionRow(for: item)
                }
            }
        }
        .padding(16)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("contextual_pair.header.title")
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text("contextual_pair.header.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Suggestion row

    private func suggestionRow(for item: BoughtTogetherWidgetItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTapItem(item)
        } label: {
            HStack(spacing: 12) {
                // Emoji tile — same shape language as QuickItemTile
                Text(item.emojiSummary)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color("LaunchBackground"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // "Add" affordance — outlined accent capsule, matching other
                // home-screen secondary CTAs (regulars "Add all", smart-start).
                // No solid white-on-accent — too heavy for this context.
                Text("action.add")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
            }
        }
        .buttonStyle(.spring)
    }
}
