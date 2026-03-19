import SwiftUI

struct RecentCompletedBasketsView: View {
    @Environment(\.locale) private var locale

    let baskets: [RecentBasketSummary]
    let onAddBasket: (RecentBasketSummary) -> Void
    let onAddItem: (RecentBasketItem) -> Void
    let onHideBasket: (RecentBasketSummary) -> Void

    @State private var expandedBasketIDs = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if baskets.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                basketCards
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(16)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(sectionBorder)
        .overlay(sectionHighlight)
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        .padding(.horizontal)
        .padding(.top, 18)
        .animation(.easeInOut(duration: 0.22), value: baskets.count)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text("recent_baskets.header.title")
                    .font(.headline)
            } icon: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundStyle(Color.accentColor)
            }

            Text("recent_baskets.header.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var basketCards: some View {
        LazyVStack(spacing: 10) {
            ForEach(baskets) { basket in
                basketCard(for: basket)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    ))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "recent_baskets.empty.title"),
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: Text("recent_baskets.empty.description")
        )
    }

    private var sectionBackground: some View {
        LinearGradient(
            colors: [
                Color(.secondarySystemBackground),
                Color(.systemBackground).opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
    }

    private var sectionHighlight: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Color.white.opacity(0.32), lineWidth: 1)
            .padding(0.5)
    }

    private func basketCard(for basket: RecentBasketSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(for: basket)
            itemsList(for: basket)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }

    private func cardHeader(for basket: RecentBasketSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(basket.completedAt, style: .date)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(basket.completedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                hideButton(for: basket)
                addAllButton(for: basket)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func hideButton(for basket: RecentBasketSummary) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                onHideBasket(basket)
            }
        } label: {
            Image(systemName: "eye.slash")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.secondary)
    }

    private func addAllButton(for basket: RecentBasketSummary) -> some View {
        Button {
            onAddBasket(basket)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text("action.add_all")
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func itemsList(for basket: RecentBasketSummary) -> some View {
        let visibleItems = visibleItems(for: basket)

        return LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(visibleItems) { item in
                itemRow(item)
            }

            if basket.items.count > 4 {
                expandButton(for: basket)
            }
        }
    }

    private func expandButton(for basket: RecentBasketSummary) -> some View {
        Button {
            toggleExpandedState(for: basket)
        } label: {
            HStack(spacing: 6) {
                Text(expandButtonTitle(for: basket))
                Image(systemName: isExpanded(basket) ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func itemRow(_ item: RecentBasketItem) -> some View {
        HStack(spacing: 8) {
            Text("\(item.emoji) \(ProductDisplayNameProvider.displayName(for: item.name)) ×\(item.quantity)")
                .font(.subheadline)
                .lineLimit(1)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())

            Spacer(minLength: 8)

            Button {
                onAddItem(item)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
        }
    }

    private func isExpanded(_ basket: RecentBasketSummary) -> Bool {
        expandedBasketIDs.contains(basket.id)
    }

    private func visibleItems(for basket: RecentBasketSummary) -> ArraySlice<RecentBasketItem> {
        basket.items.prefix(isExpanded(basket) ? basket.items.count : 4)
    }

    private func toggleExpandedState(for basket: RecentBasketSummary) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedBasketIDs.contains(basket.id) {
                expandedBasketIDs.remove(basket.id)
            } else {
                expandedBasketIDs.insert(basket.id)
            }
        }
    }

    private func expandButtonTitle(for basket: RecentBasketSummary) -> String {
        if isExpanded(basket) {
            return String(localized: "recent_baskets.show_less")
        }

        let hiddenCount = max(0, basket.items.count - 4)
        return String(localized: "recent_baskets.show_more_format", defaultValue: "See %lld more", locale: locale)
            .replacingOccurrences(of: "%lld", with: "\(hiddenCount)")
    }
}