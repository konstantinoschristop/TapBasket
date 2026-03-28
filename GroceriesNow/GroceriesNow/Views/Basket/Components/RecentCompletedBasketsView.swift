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
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.22), value: baskets.count)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [Color.indigo.mix(with: .white, by: 0.18), Color.indigo],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: Color.indigo.opacity(0.35), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("recent_baskets.header.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))

                Text("recent_baskets.header.subtitle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !baskets.isEmpty {
                Text("\(baskets.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.indigo)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Cards list

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
            .foregroundStyle(Color.indigo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.indigo.opacity(0.10))
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
            emojiStrip(for: basket)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            infoBar(for: basket)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            if isExpanded(basket) {
                Divider()
                    .padding(.horizontal, 14)

                itemsList(for: basket)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.35), Color.indigo.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.indigo.opacity(0.08), radius: 10, y: 4)
    }

    private func emojiStrip(for basket: RecentBasketSummary) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(basket.items.prefix(6).enumerated()), id: \.offset) { _, item in
                Text(item.emoji)
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color("LaunchBackground"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if basket.items.count > 6 {
                Text("+\(basket.items.count - 6)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color("LaunchBackground"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer(minLength: 0)
        }
    }

    private func infoBar(for basket: RecentBasketSummary) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(relativeDateString(basket.completedAt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(basket.completedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            // Item count
            Text("\(basket.items.count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color("LaunchBackground"), in: Capsule())

            // Expand / collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    toggleExpandedState(for: basket)
                }
            } label: {
                Image(systemName: isExpanded(basket) ? "chevron.up" : "list.bullet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.indigo)
                    .frame(width: 30, height: 30)
                    .background(Color.indigo.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)

            // Add all
            Button { onAddBasket(basket) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("action.add_all")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.indigo, in: Capsule())
            }
            .buttonStyle(.plain)

            // Hide
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { onHideBasket(basket) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color("LaunchBackground"), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Items list

    private func itemsList(for basket: RecentBasketSummary) -> some View {
        let visibleItems = visibleItems(for: basket)

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(visibleItems) { item in
                itemRow(item)
            }

            if basket.items.count > 4 {
                expandButton(for: basket)
                    .padding(.top, 4)
            }
        }
    }

    private func expandButton(for basket: RecentBasketSummary) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                toggleExpandedState(for: basket)
            }
        } label: {
            HStack(spacing: 6) {
                Text(expandButtonTitle(for: basket))
                Image(systemName: isExpanded(basket) ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.indigo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func itemRow(_ item: RecentBasketItem) -> some View {
        HStack(spacing: 10) {
            Text(item.emoji)
                .font(.body)
                .frame(width: 28, height: 28)
                .background(Color("LaunchBackground"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                    .foregroundStyle(Color.indigo)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func isExpanded(_ basket: RecentBasketSummary) -> Bool {
        expandedBasketIDs.contains(basket.id)
    }

    private func visibleItems(for basket: RecentBasketSummary) -> ArraySlice<RecentBasketItem> {
        basket.items.prefix(isExpanded(basket) ? basket.items.count : 4)
    }

    private func toggleExpandedState(for basket: RecentBasketSummary) {
        if expandedBasketIDs.contains(basket.id) {
            expandedBasketIDs.remove(basket.id)
        } else {
            expandedBasketIDs.insert(basket.id)
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
