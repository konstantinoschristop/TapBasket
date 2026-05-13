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

                    // Inline banner at the end of the sheet — never
                    // overlays a basket tile, matches the basket view's
                    // bottom-of-list placement.
                    if !AdsConfiguration.hideForScreenshots {
                        InlineBannerSection()
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            String(localized: "history.tile.a11y_format",
                   defaultValue: "\(relativeDateString(basket.completedAt)), \(basket.items.count) items",
                   comment: "VoiceOver label for a recent-basket tile.")
        ))
        .accessibilityHint(Text("history.tile.a11y_hint"))
    }

    // MARK: - Tile face

    /// Two-zone card: overlapping avatar stack above, date + count below,
    /// separated by a hairline. Today's basket gets a small green dot at
    /// the top-right corner.
    private func tileFace(basket: RecentBasketSummary, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            avatarStack(items: basket.items)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Rectangle()
                .fill(Color(.separator).opacity(0.30))
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    if let label = basket.friendlyLabel {
                        // Friendly auto-label leads, with the date
                        // demoted to a secondary caption alongside the
                        // item count. Reads as a memory ("Pasta night")
                        // rather than a log entry ("Tuesday").
                        HStack(spacing: 4) {
                            Text(label.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(label.emoji)
                                .font(.subheadline)
                        }

                        Text("\(relativeDateString(basket.completedAt))  ·  \(itemCountLabel(basket.items.count))")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(1)
                    } else {
                        Text(relativeDateString(basket.completedAt))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(itemCountLabel(basket.items.count))
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color("CardBackground"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
        .overlay(alignment: .topTrailing) {
            if isToday {
                Circle()
                    .fill(Color("BrandGreen"))
                    .frame(width: 9, height: 9)
                    .padding(10)
            }
        }
    }

    // MARK: - Avatar stack

    /// iOS contact-group-style overlapping circular avatars. Shows up to
    /// 4 emojis, with a `+N` bubble when the basket has more.
    private func avatarStack(items: [RecentBasketItem]) -> some View {
        let maxVisible = 4
        let visible = Array(items.prefix(maxVisible))
        let hidden = max(0, items.count - maxVisible)

        return HStack(spacing: -12) {
            ForEach(visible) { item in
                avatarBubble(emoji: item.emoji)
            }
            if hidden > 0 {
                avatarBubble(label: "+\(hidden)")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func avatarBubble(emoji: String? = nil, label: String? = nil) -> some View {
        ZStack {
            if let emoji {
                Text(emoji).font(.system(size: 22))
            } else if let label {
                Text(label)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color(.tertiarySystemFill), in: Circle())
        // The 2pt stroke is the card background — it "punches out" each
        // avatar so adjacent overlapping circles read as separate units.
        .overlay(Circle().strokeBorder(Color("CardBackground"), lineWidth: 2))
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
