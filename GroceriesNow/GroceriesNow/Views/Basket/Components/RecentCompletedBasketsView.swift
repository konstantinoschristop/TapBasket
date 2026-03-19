import SwiftUI

struct RecentCompletedBasketsView: View {
    @Environment(\.locale) private var locale

    let baskets: [RecentBasketSummary]
    let onAddBasket: (RecentBasketSummary) -> Void
    let onAddItem: (RecentBasketItem) -> Void
    let onHideBasket: (RecentBasketSummary) -> Void

    @State private var expandedBasketIDs = Set<UUID>()
    @State private var showAll = false

    private var visibleBaskets: [RecentBasketSummary] {
        showAll ? baskets : Array(baskets.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal)

            if baskets.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                basketCards
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.top, 18)
        .animation(.easeInOut(duration: 0.22), value: baskets.count)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
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

            Spacer()

            if !baskets.isEmpty {
                Text("\(baskets.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var basketCards: some View {
        LazyVStack(spacing: 10) {
            ForEach(visibleBaskets) { basket in
                basketCard(for: basket)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    ))
            }

            if !showAll && baskets.count > 3 {
                loadMoreButton
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showAll)
    }

    private var loadMoreButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showAll = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption.weight(.semibold))
                Text(
                    String(localized: "recent_baskets.load_more_format", defaultValue: "Show %lld more carts", locale: locale)
                        .replacingOccurrences(of: "%lld", with: "\(baskets.count - 3)")
                )
                .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "recent_baskets.empty.title"),
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: Text("recent_baskets.empty.description")
        )
    }

    // MARK: - Card

    private func basketCard(for basket: RecentBasketSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(for: basket)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            itemsList(for: basket)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }

    private func cardHeader(for basket: RecentBasketSummary) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(relativeDateString(basket.completedAt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(basket.completedAt, style: .time)
                    .font(.caption)
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

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, 32)
                }
                itemRow(item)
            }

            if basket.items.count > 4 {
                Divider()
                    .padding(.leading, 32)
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func itemRow(_ item: RecentBasketItem) -> some View {
        HStack(spacing: 10) {
            Text(item.emoji)
                .font(.body)
                .frame(width: 24)

            Text(ProductDisplayNameProvider.displayName(for: item.name))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                onAddItem(item)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
    }

    // MARK: - Helpers

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

    private func relativeDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
