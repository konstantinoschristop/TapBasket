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
    let onToggleStar: (RecentBasketSummary) -> Void
    let onRename: (RecentBasketSummary, String) -> Void

    // MARK: - State

    @State private var displayedBaskets: [RecentBasketSummary] = []
    @State private var displayLimit: Int = 10
    private let pageSize = 10
    /// Drives the inline rename alert. `nil` = alert hidden.
    @State private var renamingBasket: RecentBasketSummary? = nil
    @State private var renameDraft: String = ""

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

        // Sort each section so starred baskets float to the top —
        // they're the user's recurring shops and deserve fast access.
        let starredFirst: ([RecentBasketSummary]) -> [RecentBasketSummary] = { list in
            list.sorted { ($0.isStarred ? 1 : 0) > ($1.isStarred ? 1 : 0) }
        }

        return [
            today.isEmpty ? nil : BasketSection(id: "today",   title: String(localized: "history.section.today"),     baskets: starredFirst(today)),
            week.isEmpty  ? nil : BasketSection(id: "week",    title: String(localized: "history.section.this_week"), baskets: starredFirst(week)),
            older.isEmpty ? nil : BasketSection(id: "earlier", title: String(localized: "history.section.earlier"),   baskets: starredFirst(older)),
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
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel(Text("action.done"))
                    }
                }
                .alert(
                    String(localized: "history.rename_alert.title", defaultValue: "Rename shop"),
                    isPresented: renameAlertBinding,
                    presenting: renamingBasket
                ) { target in
                    TextField(
                        String(localized: "history.rename_alert.placeholder", defaultValue: "e.g. Pasta night"),
                        text: $renameDraft
                    )
                    .textInputAutocapitalization(.words)
                    Button(String(localized: "action.cancel"), role: .cancel) {
                        renamingBasket = nil
                    }
                    Button(String(localized: "action.save")) {
                        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onRename(target, trimmed)
                        renamingBasket = nil
                    }
                }
        }
        .onAppear {
            if displayedBaskets.isEmpty { displayedBaskets = baskets }
        }
        .onChange(of: baskets) { _, new in
            // Reflect external updates (star toggle, rename) that
            // changed the source list while the sheet is open.
            displayedBaskets = new
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingBasket != nil },
            set: { if !$0 { renamingBasket = nil } }
        )
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
            // Primary reuse path — promoted to the top so it's the
            // first thing the user sees in the menu.
            if !allAdded {
                Button {
                    onAddBasket(basket)
                    dismiss()
                } label: {
                    Label(
                        String(format: String(localized: "history.use_again_format",
                                              defaultValue: "Use again (%lld items)"),
                               basket.items.count),
                        systemImage: "arrow.uturn.forward"
                    )
                }
            }

            // Personalization — star + rename. Both very lightweight.
            Section {
                Button {
                    onToggleStar(basket)
                } label: {
                    Label(
                        basket.isStarred
                            ? String(localized: "history.unstar", defaultValue: "Unstar")
                            : String(localized: "history.star", defaultValue: "Star"),
                        systemImage: basket.isStarred ? "star.slash" : "star"
                    )
                }
                Button {
                    renameDraft = basket.customName ?? ""
                    renamingBasket = basket
                } label: {
                    Label(
                        String(localized: "history.rename", defaultValue: "Rename…"),
                        systemImage: "pencil"
                    )
                }
            }

            // Individual item re-adds — secondary, kept at the bottom
            // so they don't crowd the primary "Use again" path.
            Section {
                ForEach(basket.items) { item in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onAddItem(item)
                    } label: {
                        Text("\(item.emoji) \(ProductDisplayNameProvider.displayName(for: item.name))")
                    }
                }
            }

            Section {
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
                tileTitleColumn(basket: basket)
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

    // MARK: - Tile title column
    //
    // Extracted into small dedicated helpers because Swift's type
    // checker can't reasonably solve a triple if/else with multiple
    // nested HStacks all in one expression. Each branch returns a
    // fully-resolved `some View` so the compiler only has to merge
    // them via @ViewBuilder.

    @ViewBuilder
    private func tileTitleColumn(basket: RecentBasketSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title precedence: user-supplied custom name → friendly
            // auto-label → bare date.
            if let customName = basket.customName {
                titleLine(text: customName, trailingLabelEmoji: nil, starred: basket.isStarred)
                metaCaption(basket: basket, includeDate: true)
            } else if let label = basket.friendlyLabel {
                titleLine(text: label.text, trailingLabelEmoji: label.emoji, starred: basket.isStarred)
                metaCaption(basket: basket, includeDate: true)
            } else {
                titleLine(text: relativeDateString(basket.completedAt), trailingLabelEmoji: nil, starred: basket.isStarred)
                metaCaption(basket: basket, includeDate: false)
            }
        }
    }

    @ViewBuilder
    private func titleLine(text: String, trailingLabelEmoji: String?, starred: Bool) -> some View {
        HStack(spacing: 4) {
            if starred {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let emoji = trailingLabelEmoji {
                Text(emoji).font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func metaCaption(basket: RecentBasketSummary, includeDate: Bool) -> some View {
        let count = itemCountLabel(basket.items.count)
        if includeDate {
            Text("\(relativeDateString(basket.completedAt))  ·  \(count)")
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        } else {
            Text(count)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
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
