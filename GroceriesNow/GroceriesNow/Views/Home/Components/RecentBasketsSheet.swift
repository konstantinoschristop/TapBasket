import SwiftUI

/// History sheet displaying past shopping trips as a 2-column grid.
/// Each tile gives the animated emoji cluster a dedicated stage with a
/// radial glow, and shows date + count in a clean strip below.
/// The whole tile is a `Menu` trigger.
struct RecentBasketsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let baskets: [RecentBasketSummary]
    let inBasketNames: Set<String>
    let onAddBasket: (RecentBasketSummary) -> Void
    let onAddItem: (RecentBasketItem) -> Void
    let onHideBasket: (RecentBasketSummary) -> Void

    // MARK: - State

    @State private var displayedBaskets: [RecentBasketSummary] = []
    @State private var displayLimit: Int = 10
    private let pageSize = 10

    private var visibleBaskets: [RecentBasketSummary] {
        Array(displayedBaskets.prefix(displayLimit))
    }
    private var hasMore: Bool { displayLimit < displayedBaskets.count }

    // MARK: - Sections

    private struct BasketSection: Identifiable {
        let id: String
        let title: String
        let baskets: [RecentBasketSummary]
    }

    private var sections: [BasketSection] {
        let cal = Calendar.current
        let now = Date()
        var today: [RecentBasketSummary] = []
        var week:  [RecentBasketSummary] = []
        var older: [RecentBasketSummary] = []

        for b in visibleBaskets {
            if cal.isDateInToday(b.completedAt) {
                today.append(b)
            } else if let cutoff = cal.date(byAdding: .day, value: -7, to: now),
                      b.completedAt >= cutoff {
                week.append(b)
            } else {
                older.append(b)
            }
        }

        return [
            today.isEmpty ? nil : BasketSection(id: "today",   title: String(localized: "history.section.today"),     baskets: today),
            week.isEmpty  ? nil : BasketSection(id: "week",    title: String(localized: "history.section.this_week"), baskets: week),
            older.isEmpty ? nil : BasketSection(id: "earlier", title: String(localized: "history.section.earlier"),   baskets: older),
        ].compactMap { $0 }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("history.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "action.done")) { dismiss() }
                    }
                }
        }
        .onAppear {
            if displayedBaskets.isEmpty { displayedBaskets = baskets }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if displayedBaskets.isEmpty {
            ContentUnavailableView(
                String(localized: "recent_baskets.empty.title"),
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                description: Text("recent_baskets.empty.description")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionLabel(section.title)

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12),
                                      GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(section.baskets) { basket in
                                basketTile(for: basket)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }

                    if hasMore { showMoreButton.padding(.top, 8) }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color("LaunchBackground"))
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(.tertiaryLabel))
            .textCase(.uppercase)
            .tracking(1)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
    }

    // MARK: - Show-more

    private var showMoreButton: some View {
        let nextBatch = min(pageSize, displayedBaskets.count - displayLimit)
        return Button {
            withAnimation(.taplistTransition) { displayLimit += pageSize }
        } label: {
            HStack(spacing: 6) {
                Text(String(format: String(localized: "recent_baskets.show_more_format", defaultValue: "Show %lld more"), nextBatch))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tile

    private func basketTile(for basket: RecentBasketSummary) -> some View {
        let allAdded = basket.items.allSatisfy { inBasketNames.contains($0.name.lowercased()) }
        let isToday  = Calendar.current.isDateInToday(basket.completedAt)

        return Menu {
            ForEach(basket.items) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAddItem(item)
                } label: {
                    Text("\(item.emoji) \(ProductDisplayNameProvider.displayName(for: item.name))")
                }
            }
            Section {
                if !allAdded {
                    Button {
                        onAddBasket(basket)
                        dismiss()
                    } label: {
                        Label(String(format: String(localized: "history.add_all_format", defaultValue: "Add all %lld items"), basket.items.count), systemImage: "cart.badge.plus")
                    }
                }
                Button(role: .destructive) {
                    onHideBasket(basket)
                    withAnimation(.taplistTransition) {
                        displayedBaskets.removeAll { $0.id == basket.id }
                    }
                } label: {
                    Label(String(localized: "history.hide_shop", defaultValue: "Hide this shop"), systemImage: "eye.slash")
                }
            }
        } label: {
            tileFace(basket: basket, isToday: isToday)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tile face

    private func tileFace(basket: RecentBasketSummary, isToday: Bool) -> some View {
        VStack(spacing: 0) {

            // BrandGreen accent bar on today's tiles
            if isToday {
                Color("BrandGreen").frame(height: 3)
            }

            // Cluster stage: radial glow + animated orbiting emojis
            ZStack {
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.02)],
                    center: .center,
                    startRadius: 2,
                    endRadius: 44
                )
                BasketItemBubbles(emojis: basket.items.map(\.emoji), size: .standard)
            }
            .frame(height: 106)

            // Info strip
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(relativeDateString(basket.completedAt))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(itemCountLabel(basket.items.count))
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("CardBackground"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }

    // MARK: - Formatting

    private func itemCountLabel(_ count: Int) -> String {
        String(localized: "recent_baskets.item_count_format",
               defaultValue: "\(count) items",
               locale: locale)
    }

    private func relativeDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }
}
