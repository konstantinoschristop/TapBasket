import SwiftUI
import SwiftData
import TipKit

/// Snapshot of the last add, used to drive the "Undo" affordance on the
/// basket button. We capture enough to build a localized label and to call
/// `BasketManager.undoAddItem` without having to look anything up again.
private struct LastAddRecord {
    let name: String          // canonical name (matches BasketItem.name)
    let displayName: String   // localized display
    let emoji: String
    let previousQuantity: Int // 0 = was a fresh insert, N = was already at N
    let addedAt: Date

    /// Undo is only valid for ~30 seconds — beyond that the user has likely
    /// moved on and an unexpected revert would be jarring.
    var isFresh: Bool {
        Date().timeIntervalSince(addedAt) < 30
    }
}

private struct QuickItemSection: Identifiable {
    let category: QuickItemCategory
    let items: [QuickItem]
    let usageCount: Int

    var id: QuickItemCategory { category }
}

struct MainGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\QuickItem.sortOrder, order: .forward)]) private var quickItems: [QuickItem]
    @Query(sort: [SortDescriptor(\BasketItem.name, order: .forward)]) private var basketItems: [BasketItem]
    @Query(sort: [SortDescriptor(\CompletedBasketEntry.completedAt, order: .reverse)]) private var completedEntries: [CompletedBasketEntry]
    @Query(sort: [SortDescriptor(\CompletedBasket.completedAt, order: .reverse)]) private var completedBaskets: [CompletedBasket]

    @State private var basketManager = BasketManager()
    @Namespace private var basketZoom
    @State private var showBasket = false
    @State private var searchText = ""
    @State private var showManualAddSheet = false
    @State private var expandedCategories = Set<QuickItemCategory>()
    @State private var basketButtonScale: CGFloat = 1
    /// Last single-item add — surfaces an "Undo" action via long-press on the
    /// basket button. Cleared on bulk adds, removes, or basket completion so
    /// undo never reaches across context boundaries.
    @State private var lastAdd: LastAddRecord?
    /// Brief "Logged" confirmation pill shown when returning home after a
    /// completed basket. Auto-dismisses ~2.5s later.
    @State private var loggedPillVisible = false
    @State private var loggedPillDismissTask: Task<Void, Never>?
    @State private var cachedCategoryUsage: [QuickItemCategory: Int] = [:]
    @State private var showRecipeSheet = false
    @State private var showRecentBasketsSheet = false
    @State private var showFavoritesPicker = false
    /// Set to a custom `QuickItem` to present the edit sheet pre-filled
    /// with that item's name / emoji / category.
    @State private var editingQuickItem: QuickItem? = nil
    @State private var isRecipeAvailable = false
    #if DEBUG
    @State private var showDebugMenu = false
    #endif
    @AppStorage("collapsedCategoryKeys") private var collapsedCategoryKeys: String = ""

    private let addItemTip = AddItemTip()
    private let recipeAITip = RecipeAITip()

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    private var filteredQuickItems: [QuickItem] {
        guard isSearching else { return quickItems }
        return quickItems.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch) || $0.emoji.contains(trimmedSearch)
        }
    }

    private var basketItemNames: Set<String> {
        Set(basketItems.map { $0.name.lowercased() })
    }

    /// Quick lookup of in-basket quantities so each tile can show its ×N badge
    /// without doing an O(n) scan per tile.
    private var basketQuantitiesByName: [String: Int] {
        Dictionary(uniqueKeysWithValues: basketItems.map { ($0.name.lowercased(), $0.quantity) })
    }

    private var sectionedQuickItems: [QuickItemSection] {
        var byCategory: [QuickItemCategory: [QuickItem]] = [:]
        for item in quickItems {
            byCategory[item.category, default: []].append(item)
        }
        return QuickItemCategory.orderedBrowseCategories
            .compactMap { category -> QuickItemSection? in
                guard let items = byCategory[category], !items.isEmpty else { return nil }
                return QuickItemSection(
                    category: category,
                    items: items,
                    usageCount: cachedCategoryUsage[category, default: 0]
                )
            }
            .sorted(by: sectionSort)
    }

    private var visibleCategories: [QuickItemCategory] {
        sectionedQuickItems.map(\.category)
    }

    private var hasExactNameMatch: Bool {
        guard isSearching else { return false }
        return quickItems.contains { $0.name.caseInsensitiveCompare(trimmedSearch) == .orderedSame }
    }

    /// Up to 5 ranked autocomplete suggestions from the bundled product
    /// catalog. Excludes products the user already has as a `QuickItem`
    /// so the user's own matches always win the top slot and we never
    /// surface a duplicate. Empty when the user isn't searching. The
    /// limit is intentionally tight — search should feel scannable in
    /// one glance, not require scrolling.
    ///
    /// Exclusion compares by `ProductDisplayNameProvider.canonicalKey`
    /// rather than raw lowercased name, so the catalog's "Eggs" gets
    /// hidden when the user already has the seed's "Egg" (both
    /// resolve to `product.eggs`). The catalog API still excludes by
    /// raw lowercased name; we request more than we need and
    /// post-filter to enforce canonical equivalence.
    private var catalogSuggestions: [Product] {
        guard isSearching else { return [] }
        let existingCanonicals = Set(quickItems.map {
            ProductDisplayNameProvider.canonicalKey(for: $0.name)
        })
        return ProductCatalog.shared.suggestions(
            for: trimmedSearch,
            excluding: [],
            limit: 10
        ).filter { product in
            !existingCanonicals.contains(
                ProductDisplayNameProvider.canonicalKey(for: product.name)
            )
        }
        .prefix(5)
        .map { $0 }
    }

    private var purchaseHints: [PurchaseHint] {
        basketManager.topPurchaseHints(from: completedEntries)
    }

    /// Recent shopping trips surfaced via the toolbar `recentBasketsMenu`.
    /// Capped at 10 — older trips still influence recommendations but aren't surfaced.
    private var recentBasketSummaries: [RecentBasketSummary] {
        basketManager.recentBasketSummaries(
            baskets: completedBaskets,
            entries: completedEntries,
            limit: 10
        )
    }

    private var topShortcutItems: [TopUsedShortcutItem] {
        let shortcuts = basketManager.topUsedShortcuts(from: completedEntries)
        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Dedup key: lowercased *display* name. Two distinct
        // `QuickItem` rows can resolve to the same display label
        // (e.g. a legacy "Eggs" + a new "Egg" both render as "Egg")
        // and we don't want them appearing twice in Regulars. Pinned
        // items get first dibs on each key; history-derived shortcuts
        // skip any key already claimed.
        func displayKey(_ canonicalName: String) -> String {
            ProductDisplayNameProvider.displayName(for: canonicalName).lowercased()
        }

        var seen = Set<String>()
        var result: [TopUsedShortcutItem] = []

        // Pinned items lead.
        for item in quickItems where item.pinned {
            let key = displayKey(item.name)
            guard seen.insert(key).inserted else { continue }
            result.append(TopUsedShortcutItem(
                id: item.id,
                name: item.name,
                emoji: item.emoji,
                totalQuantity: 0,
                category: item.category,
                isPinned: true
            ))
        }

        // History-derived next. Note: we deliberately don't filter
        // out items already in the basket — Regulars are essential
        // affordances; the avatar shows an "added" state instead.
        for shortcut in shortcuts {
            guard let item = itemsByName[shortcut.itemName.lowercased()] else { continue }
            let key = displayKey(item.name)
            guard seen.insert(key).inserted else { continue }
            result.append(TopUsedShortcutItem(
                id: item.id,
                name: item.name,
                emoji: item.emoji,
                totalQuantity: shortcut.totalQuantity,
                category: item.category,
                isPinned: false
            ))
        }

        return result
    }

    /// Items the user has bought before that are *not* currently
    /// surfaced in Regulars (deduped by display key) and *not*
    /// currently in the basket. Powers the "More you've bought" row
    /// once the user is established enough that Pantry staples have
    /// stopped earning their keep. Capped at 6 — this is a quiet
    /// secondary surface, never a wall of items.
    private var basketSuggestions: [QuickItem] {
        let shortcuts = basketManager.topUsedShortcuts(from: completedEntries, limit: 40)
        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func displayKey(_ canonical: String) -> String {
            ProductDisplayNameProvider.displayName(for: canonical).lowercased()
        }

        // Anything already visible in Regulars (or currently in the
        // basket) gets skipped — Suggestions only surfaces items the
        // user can't see elsewhere on the home screen right now.
        var seen = Set<String>()
        seen.formUnion(topShortcutItems.map { displayKey($0.name) })
        seen.formUnion(basketItemNames.map { displayKey($0) })

        var result: [QuickItem] = []
        for shortcut in shortcuts {
            guard let item = itemsByName[shortcut.itemName.lowercased()] else { continue }
            let key = displayKey(item.name)
            guard seen.insert(key).inserted else { continue }
            result.append(item)
            if result.count >= 6 { break }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            scrollContent
                .overlay(alignment: .top) {
                    loggedPill
                }
                .overlay {
                    FloatingBasketButton(
                        emojis: basketItems.map(\.emoji),
                        count: basketManager.totalItemCount(from: basketItems),
                        scale: basketButtonScale,
                        namespace: basketZoom,
                        onTap: { showBasket = true }
                    )
                }
                .navigationDestination(isPresented: $showBasket) {
                    basketDestination
                }
                .navigationTitle(Text("home.navigation_title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            #if DEBUG
            .sheet(isPresented: $showDebugMenu) { debugMenuSheet }
            #endif
            .searchable(text: $searchText, prompt: Text("home.search_prompt"))
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                if !recentBasketSummaries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showRecentBasketsSheet = true
                        } label: {
                            // Title + icon makes the History entry point
                            // discoverable without adding another widget to
                            // the already-busy home screen.
                            Label("history.title", systemImage: "clock.arrow.circlepath")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel(Text("history.title"))
                    }
                }
                if isRecipeAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showRecipeSheet = true
                            recipeAITip.invalidate(reason: .actionPerformed)
                        } label: {
                            Label(String(localized: "recipe.toolbar_button"), systemImage: "sparkles")
                        }
                        .popoverTip(recipeAITip)
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDebugMenu = true } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showManualAddSheet) {
                ManualQuickItemSheet(initialName: trimmedSearch, onSave: saveManualQuickItem)
            }
            .sheet(item: $editingQuickItem) { item in
                ManualQuickItemSheet(
                    initialName: item.name,
                    initialEmoji: item.emoji,
                    initialCategory: item.category,
                    showAddToBasketOption: false,
                    title: String(localized: "manual_add.title.edit", defaultValue: "Edit Item")
                ) { name, emoji, category, _ in
                    updateCustomQuickItem(item, name: name, emoji: emoji, category: category)
                }
            }
            #if canImport(FoundationModels)
            .sheet(isPresented: $showRecipeSheet) {
                if #available(iOS 26.0, macOS 26.0, *) {
                    RecipeBasketSheet(quickItems: quickItems) { recipeName, ingredients in
                        addRecipeIngredients(ingredients, recipeName: recipeName)
                    }
                }
            }
            #endif
            .sheet(isPresented: $showFavoritesPicker) {
                PickFavoritesSheet(
                    items: quickItems,
                    onTogglePin: { togglePin($0) }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRecentBasketsSheet) {
                RecentBasketsSheet(
                    baskets: recentBasketSummaries,
                    inBasketNames: basketItemNames,
                    onAddBasket: addRecentBasketFromHome,
                    onAddItem: addRecentItemFromHome,
                    onHideBasket: hideRecentBasketFromHome,
                    onToggleStar: toggleBasketStar,
                    onRename: renameCompletedBasket
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear(perform: syncExpandedCategories)
            .onAppear {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    isRecipeAvailable = FeatureFlags.aiRecipeEnabled
                }
                #endif
            }
            .onChange(of: completedEntries, initial: true) { _, _ in recomputeCategoryUsage() }
            .onChange(of: quickItems) { _, _ in recomputeCategoryUsage() }
            .onChange(of: visibleCategories, initial: true) { _, _ in
                syncExpandedCategories()
            }
        }
    }

    /// Brief post-completion confirmation that slides down from the top after
    /// the basket has been logged to history. Doesn't block taps — purely
    /// visual reinforcement so the celebration doesn't evaporate when the
    /// basket sheet dismisses.
    @ViewBuilder
    private var loggedPill: some View {
        if loggedPillVisible {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color("BrandGreen"))
                Text("home.logged_pill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .adaptiveGlass(in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        List {
            if isSearching {
                // User's own matches first — always the top slot when
                // present so existing items win over catalog autocomplete.
                if !filteredQuickItems.isEmpty {
                    Section {
                        ForEach(filteredQuickItems) { item in
                            itemRow(for: item)
                        }
                    }
                }

                // Catalog autocomplete: products the user doesn't have
                // yet that match the query. Tap → creates the QuickItem
                // and adds to basket in one shot.
                if !catalogSuggestions.isEmpty {
                    Section {
                        ForEach(catalogSuggestions) { product in
                            catalogSuggestionRow(for: product)
                        }
                    } header: {
                        // Tiny tertiary caption — gives the section
                        // structure without taking a row's height of
                        // its own. Consistent with the rest of the
                        // app's quieter section headers.
                        Text(String(localized: "search.catalog.header",
                                    defaultValue: "Suggestions"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }

                // Fallback empty state — only when nothing matches in
                // either the user's items OR the catalog.
                if filteredQuickItems.isEmpty && catalogSuggestions.isEmpty {
                    Section {
                        emptySearchContent
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }

                if shouldShowManualAddButton {
                    Section { manualAddButton }
                }
            } else {
                Section {
                    TipView(addItemTip)
                        .tipBackground(Color("CardBackground"))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
                }

                // Regulars row is always visible. Empty state shows a
                // pulsing "+" that opens the bulk-pin picker — calmer
                // than hiding the section entirely, and discoverable.
                Section {
                    TopUsedShortcutsView(
                        items: topShortcutItems,
                        inBasketNames: basketItemNames,
                        onTapItem: toggleShortcutItemInBasket,
                        onAddAll: addAllRegulars,
                        onPickFavorites: { showFavoritesPicker = true },
                        onToggleItemPin: togglePinForShortcut
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // Cold-start: Pantry staples (universal items everyone
                // tends to buy). Once the user has built up enough
                // Regulars + pins to be "established", this slot
                // switches to a personalised "More you've bought" row
                // sourced from their purchase history.
                if topShortcutItems.count < 6 {
                    Section {
                        PantryStaplesRail(
                            inBasketNames: basketItemNames,
                            onTap: addPantryStaple,
                            onAddAll: addAllPantryStaples
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else if !basketSuggestions.isEmpty {
                    Section {
                        BasketSuggestionsRow(
                            items: basketSuggestions,
                            inBasketNames: basketItemNames,
                            quantitiesByName: basketQuantitiesByName,
                            onTap: toggleQuickItemInBasket,
                            onIncrement: incrementQuickItemInBasket,
                            onTogglePin: togglePin
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                ForEach(Array(sectionedQuickItems.enumerated()), id: \.element.id) { index, section in
                    Section {
                        // Header rendered as a regular row so it scrolls
                        // with the content instead of pinning to the
                        // top of the viewport.
                        categorySectionHeader(for: section)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        if expandedCategories.contains(section.category) {
                            sectionContent(for: section)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .transition(.opacity.combined(
                                    with: .move(edge: .top)
                                ))
                        }
                    }

                    // Banner sits one category deep — after the first
                    // hero browse section, before the rest. Past the
                    // initial discovery flow, still very much mid-feed.
                    if index == 0 && !AdsConfiguration.hideForScreenshots {
                        Section {
                            InlineBannerSection()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // Compact section spacing tightens the gap between the user's
        // matches, the catalog suggestions header, and the manual-add
        // row so the search list reads as one stack instead of stacked
        // cards. Doesn't affect the home browse list, which renders
        // its own custom spacing per-section.
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color("LaunchBackground"))
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: basketItems.count)
    }


    private func itemTile(for item: QuickItem) -> some View {
        let editable = isUserCreated(item)
        return QuickItemTile(
            item: item,
            isInBasket: basketItemNames.contains(item.name.lowercased()),
            quantity: basketQuantitiesByName[item.name.lowercased()] ?? 0,
            isEditable: editable,
            // Tap toggles. The long-press affordance is now a system
            // `Menu` (pin / add-one-more / edit / delete); the increment
            // is reachable from there for the rare "I want 2 milks" case.
            action: { toggleQuickItemInBasket(item) },
            onLongPress: { incrementQuickItemInBasket(item) },
            onTogglePin: { togglePin(item) },
            onEdit: editable ? { editingQuickItem = item } : nil,
            onDelete: editable ? { deleteUserQuickItem(item) } : nil
        )
    }

    private func chipFor(_ item: QuickItem) -> some View {
        QuickItemChip(
            item: item,
            isInBasket: basketItemNames.contains(item.name.lowercased()),
            quantity: basketQuantitiesByName[item.name.lowercased()] ?? 0,
            action: { toggleQuickItemInBasket(item) },
            onLongPress: { incrementQuickItemInBasket(item) },
            onTogglePin: { togglePin(item) }
        )
    }

    /// Layout content for a category section. Featured tile leads in
    /// grid + carousel layouts; chip rows skip it (they're compact by
    /// design). The header is rendered separately via Section's header
    /// slot so the system disclosure chevron and expand/collapse
    /// behaviour work out of the box on `.sidebar` listStyle.
    @ViewBuilder
    private func sectionContent(for section: QuickItemSection) -> some View {
        let items = section.items
        let featured = items.first
        let rest = Array(items.dropFirst())

        switch section.category.layout {
        case .grid(let columns):
            VStack(spacing: 12) {
                if let featured {
                    // 136 matches `FeaturedQuickItemTile`'s new default
                    // (-15% from the old 160) so the featured slot
                    // guides scanning instead of dominating it.
                    featuredTile(for: featured, width: nil, height: 136)
                }
                if !rest.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                        spacing: 12
                    ) {
                        ForEach(rest) { itemTile(for: $0) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

        case .carousel(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if let featured {
                        // Featured tile fills both carousel rows
                        // (2 × 108 + 10 = 226). Wider than the
                        // standard 130pt tile so it reads as the headline.
                        featuredTile(for: featured, width: 210, height: 226)
                    }
                    if !rest.isEmpty {
                        LazyHGrid(
                            rows: Array(repeating: GridItem(.fixed(108), spacing: 10), count: rows),
                            spacing: 10
                        ) {
                            ForEach(rest) { item in
                                itemTile(for: item).frame(width: 130)
                            }
                        }
                    }
                }
                // Symmetric inset so both the first and last tile have
                // breathing room from the screen edges.
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()

        case .chipRow:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { chipFor($0) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .padding(.vertical, 6)
        }
    }

    /// Compact featured-tile factory that wires the standard quantity /
    /// basket-state lookups so callers don't repeat them.
    private func featuredTile(for item: QuickItem, width: CGFloat?, height: CGFloat) -> some View {
        let editable = isUserCreated(item)
        return FeaturedQuickItemTile(
            item: item,
            isInBasket: basketItemNames.contains(item.name.lowercased()),
            quantity: basketQuantitiesByName[item.name.lowercased()] ?? 0,
            isEditable: editable,
            metaText: featuredMetaText(for: item),
            action: { toggleQuickItemInBasket(item) },
            onLongPress: { incrementQuickItemInBasket(item) },
            onTogglePin: { togglePin(item) },
            onEdit: editable ? { editingQuickItem = item } : nil,
            onDelete: editable ? { deleteUserQuickItem(item) } : nil,
            width: width,
            height: height
        )
    }

    /// "Bought 8×" when the user has purchase history for this item;
    /// `nil` otherwise so the tile falls back to its default "Featured"
    /// caption. Subtle metadata, never a metric dashboard.
    private func featuredMetaText(for item: QuickItem) -> String? {
        let key = item.name.lowercased()
        let total = completedEntries
            .filter { $0.name.lowercased() == key }
            .reduce(0) { $0 + $1.quantity }
        guard total >= 2 else { return nil }
        return String(
            localized: "featured.bought_count_format",
            defaultValue: "Bought \(total)×",
            comment: "Featured-tile caption when the user has purchased this item before. %lld is the total quantity."
        )
    }

    /// Tappable section header with a rotating chevron. Built custom
    /// (rather than relying on `Section(isExpanded:)`) so we can keep
    /// `.plain` listStyle, which lets the horizontal scrolls inside
    /// each section extend all the way to the screen edge.
    private func categorySectionHeader(for section: QuickItemSection) -> some View {
        let isExpanded = expandedCategories.contains(section.category)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                if isExpanded {
                    expandedCategories.remove(section.category)
                } else {
                    expandedCategories.insert(section.category)
                }
            }
            let collapsed = Set(QuickItemCategory.allCases).subtracting(expandedCategories)
            collapsedCategoryKeys = collapsed.map(\.rawValue).sorted().joined(separator: ",")
        } label: {
            HStack(spacing: 12) {
                CategoryHeaderIcon(category: section.category)

                Text(section.category.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(.label))
                    .textCase(nil)
                    .tracking(-0.2)

                Text("\(section.items.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .monospacedDigit()
                    .textCase(nil)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptySearchContent: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                String(localized: "home.empty_search.title"),
                systemImage: "magnifyingglass",
                description: Text("home.empty_search.description")
            )

            manualAddButton
                .padding(.horizontal, 20)
        }
        .padding(.top, 40)
    }

    /// Row-style accent button for "Create '<query>'". Matches the
    /// rhythm of `itemRow` / `catalogSuggestionRow` so it sits inside
    /// the search list as one more option rather than a chunky
    /// bordered pill at the bottom.
    private var manualAddButton: some View {
        Button {
            showManualAddSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, alignment: .center)

                Text(
                    String(
                        localized: "action.create_format",
                        defaultValue: "Create \"%@\"",
                        locale: locale
                    )
                    .replacingOccurrences(of: "%@", with: trimmedSearch)
                )
                .foregroundStyle(Color.accentColor)
                .fontWeight(.medium)
                .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(trimmedSearch.isEmpty)
    }

    @ViewBuilder
    private var basketDestination: some View {
        let view = BasketView(manager: basketManager, onCompletion: {
            showLoggedPill()
            // Pop back to home after the completion animation finishes.
            showBasket = false
        })
        if #available(iOS 18.0, *) {
            view.navigationTransition(.zoom(sourceID: "basket", in: basketZoom))
        } else {
            view
        }
    }

    private var shouldShowManualAddButton: Bool {
        // Surface "Create X" whenever the search has content to show
        // (own items OR catalog suggestions) but nothing exact matches —
        // so the user can always create a fully custom variant the
        // catalog doesn't carry.
        isSearching
            && !hasExactNameMatch
            && (!filteredQuickItems.isEmpty || !catalogSuggestions.isEmpty)
    }

    private func recomputeCategoryUsage() {
        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedCategoryUsage = completedEntries.reduce(into: [:]) { result, entry in
            guard let item = itemsByName[entry.name.lowercased()] else { return }
            result[item.category, default: 0] += entry.quantity
        }
    }

    private func sectionSort(lhs: QuickItemSection, rhs: QuickItemSection) -> Bool {
        // Sort categories by usage so the user's most-bought lanes
        // lead. Ties fall back to the canonical browse order. `.custom`
        // no longer gets a leading slot — items added via the catalog
        // / manual flow land in their real category, so there's no
        // benefit to prioritising `.custom` here.
        if lhs.usageCount == rhs.usageCount {
            return fallbackOrder(for: lhs.category) < fallbackOrder(for: rhs.category)
        }
        return lhs.usageCount > rhs.usageCount
    }

    private func fallbackOrder(for category: QuickItemCategory) -> Int {
        QuickItemCategory.orderedBrowseCategories.firstIndex(of: category) ?? .max
    }

    private func syncExpandedCategories() {
        let visibleSet = Set(visibleCategories)
        let defaults = HomeBrowseState.defaultExpandedCategories(for: sectionedQuickItems.map(\.category))

        if !collapsedCategoryKeys.isEmpty {
            // Restore from persisted state: visible categories minus the collapsed ones
            let collapsedRaws = Set(collapsedCategoryKeys.split(separator: ",").map(String.init))
            let restored = visibleSet.filter { !collapsedRaws.contains($0.rawValue) }
            expandedCategories = restored.isEmpty ? defaults : restored
        } else {
            // No persisted state — expand all visible by default
            expandedCategories = expandedCategories.intersection(visibleSet)
            if expandedCategories.isEmpty { expandedCategories = defaults }
        }
    }

    private func itemRow(for item: QuickItem) -> some View {
        let quantity = basketQuantitiesByName[item.name.lowercased()] ?? 0
        let isInBasket = quantity > 0
        let displayName = ProductDisplayNameProvider.displayName(for: item.name)

        return Button {
            addQuickItemToBasket(item)
        } label: {
            HStack(spacing: 12) {
                Text(item.emoji)
                    .font(.title3)
                    .frame(width: 28, alignment: .center)

                Text(displayName)
                    .foregroundStyle(.primary)
                    .opacity(isInBasket ? 0.55 : 1)

                Spacer(minLength: 8)

                // Quiet trailing meta — no loud checkmark badge. In-basket
                // is signalled by the dimmed name + a tertiary inline
                // caption (with ×N when the user has stacked more than
                // one). History hint shows when not yet added.
                if isInBasket {
                    Text(quantity > 1
                         ? String(localized: "search.row.in_basket_count_format",
                                  defaultValue: "in basket · ×\(quantity)")
                         : String(localized: "search.row.in_basket",
                                  defaultValue: "in basket"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(quantity)))
                } else if let hint = hintText(for: item) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: quantity)
        }
        .buttonStyle(.plain)
    }

    /// One row in the search "Suggestions" section. Same visual
    /// vocabulary as `itemRow` so the search list reads as one cohesive
    /// stack — the structural difference (user's items vs. catalog) is
    /// carried by the section header, not by row chrome. Trailing
    /// category caption hints "this is from the catalog" without
    /// needing a coloured accent disc.
    private func catalogSuggestionRow(for product: Product) -> some View {
        let category = QuickItemCategory(rawValue: product.category) ?? .custom
        return Button {
            // Add to user's library and basket in one shot. The
            // existing helper dedupes by name (case-insensitive) so
            // this is safe even if the catalog and the user race.
            saveManualQuickItem(product.name, product.emoji, category, true)
        } label: {
            HStack(spacing: 12) {
                Text(product.emoji)
                    .font(.title3)
                    .frame(width: 28, alignment: .center)

                Text(product.name)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(category.title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addRecipeIngredients(_ ingredients: [RecipeIngredient], recipeName: String) {
        guard !ingredients.isEmpty else { return }

        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for ingredient in ingredients {
            let key = ingredient.name.lowercased()
            let resolvedName = itemsByName[key]?.name.capitalized ?? ingredient.name.capitalized
            let resolvedEmoji = itemsByName[key]?.emoji ?? ingredient.emoji

            if let existing = basketItems.first(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
                existing.quantity += ingredient.quantity
                if existing.recipeName == nil { existing.recipeName = recipeName }
            } else {
                modelContext.insert(BasketItem(
                    name: resolvedName,
                    emoji: resolvedEmoji,
                    quantity: ingredient.quantity,
                    recipeName: recipeName
                ))
            }
        }

        try? modelContext.save()
    }

    private func saveManualQuickItem(_ name: String, _ emoji: String, _ category: QuickItemCategory, _ addToBasket: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Dedup by *canonical* product key, not by raw name. "Egg" and
        // "Eggs" collapse to the same `product.eggs` key, so tapping
        // the catalog's "Eggs" suggestion when the seed already gave
        // the user "Egg" reuses the existing row instead of creating
        // a second entry that just looks identical in the UI.
        let canonicalKey = ProductDisplayNameProvider.canonicalKey(for: trimmedName)
        if let existingItem = quickItems.first(where: {
            ProductDisplayNameProvider.canonicalKey(for: $0.name) == canonicalKey
        }) {
            if addToBasket {
                addQuickItemToBasket(existingItem)
            }
            searchText = ""
            return
        }

        let newQuickItem = QuickItem(
            name: trimmedName.capitalized,
            emoji: emoji,
            sortOrder: quickItems.count,
            category: category
        )
        modelContext.insert(newQuickItem)

        if addToBasket {
            let previousQuantity = basketManager.addItem(newQuickItem, in: modelContext, basketItems: basketItems)
            recordLastAdd(item: newQuickItem, previousQuantity: previousQuantity)
        }

        try? modelContext.save()
        searchText = ""
    }

    private func addQuickItemToBasket(_ item: QuickItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // Tactile confirmation — matches the Regulars / Pantry widget add feel.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let previousQuantity = basketManager.addItem(item, in: modelContext, basketItems: basketItems)
        recordLastAdd(item: item, previousQuantity: previousQuantity)
        pulseBasketButton()
        addItemTip.invalidate(reason: .actionPerformed)
    }

    /// Tile-tap behaviour: toggle membership.
    /// If the item is already in the basket, remove it entirely (regardless of quantity).
    /// Otherwise, add it via the normal add path.
    private func toggleQuickItemInBasket(_ item: QuickItem) {
        let alreadyInBasket = basketItemNames.contains(item.name.lowercased())
        guard alreadyInBasket else {
            addQuickItemToBasket(item)
            return
        }

        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        basketManager.removeItem(named: item.name, in: modelContext, basketItems: basketItems)
        // Removal invalidates undo — last add no longer represents current state.
        lastAdd = nil
        pulseBasketButton()
    }

    /// Tile long-press: always increments quantity by 1, whether the item is
    /// in the basket already or not. `BasketManager.addItem` handles both —
    /// it either inserts a new BasketItem or bumps the existing quantity.
    private func incrementQuickItemInBasket(_ item: QuickItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let previousQuantity = basketManager.addItem(item, in: modelContext, basketItems: basketItems)
        recordLastAdd(item: item, previousQuantity: previousQuantity)
        pulseBasketButton()
        addItemTip.invalidate(reason: .actionPerformed)
    }

    private func pulseBasketButton() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) {
            basketButtonScale = 1.1
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65).delay(0.15)) {
            basketButtonScale = 1
        }
    }

    /// "Add all" affordance on the Regulars row. Adds every regular not
    /// already in the basket. Bulk operation, so we clear the undo-record
    /// (single-item undo isn't meaningful here).
    private func addAllRegulars() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let inBasket = basketItemNames
        for shortcut in topShortcutItems where !inBasket.contains(shortcut.name.lowercased()) {
            if let item = quickItems.first(where: { $0.id == shortcut.id }) {
                addQuickItemToBasket(item)
            }
        }
        lastAdd = nil
    }

    /// Adds a curated staple to the basket.
    ///
    /// Prefers an existing `QuickItem` match (preserves category metadata and
    /// flows through the same add path as the rest of the home screen).
    /// Falls back to inserting a bare `BasketItem` when no matching QuickItem
    /// exists in the user's seed/custom set.
    private func addPantryStaple(_ staple: PantryStaple) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        if let match = quickItems.first(where: { $0.name.caseInsensitiveCompare(staple.name) == .orderedSame }) {
            addQuickItemToBasket(match)
            return
        }

        // Fallback: no matching QuickItem — insert a BasketItem directly.
        let previousQuantity: Int
        if let existing = basketItems.first(where: { $0.name.caseInsensitiveCompare(staple.name) == .orderedSame }) {
            previousQuantity = existing.quantity
            existing.quantity += 1
        } else {
            previousQuantity = 0
            modelContext.insert(BasketItem(name: staple.name, emoji: staple.emoji, quantity: 1))
        }
        try? modelContext.save()

        lastAdd = LastAddRecord(
            name: staple.name,
            displayName: ProductDisplayNameProvider.displayName(for: staple.name),
            emoji: staple.emoji,
            previousQuantity: previousQuantity,
            addedAt: Date()
        )
        pulseBasketButton()
    }

    /// Tap on a Regulars avatar — toggles the underlying QuickItem's basket
    /// membership, matching the grid tile's behaviour.
    private func toggleShortcutItemInBasket(_ shortcut: TopUsedShortcutItem) {
        guard let item = quickItems.first(where: { $0.id == shortcut.id }) else { return }
        toggleQuickItemInBasket(item)
    }

    /// Resolves a shortcut back to its underlying `QuickItem` and flips
    /// the `pinned` flag. Used by the avatar's long-press menu so the
    /// user can unpin a regular without leaving the home screen.
    private func togglePinForShortcut(_ shortcut: TopUsedShortcutItem) {
        guard let item = quickItems.first(where: { $0.id == shortcut.id }) else { return }
        togglePin(item)
    }

    /// "Add all" affordance on the pantry rail. Adds every staple that isn't
    /// already in the basket. Bulk add, so we clear the undo-record afterwards
    /// (single-item undo isn't meaningful for a many-item add).
    private func addAllPantryStaples() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let inBasket = basketItemNames
        for staple in PantryStaple.all where !inBasket.contains(staple.id) {
            addPantryStaple(staple)
        }
        lastAdd = nil
    }

    private func addRecentBasketFromHome(_ basket: RecentBasketSummary) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        _ = basketManager.addRecentBasket(basket, in: modelContext, basketItems: basketItems)
        // Bulk add — undo isn't well-defined for many items, so clear it.
        lastAdd = nil
        pulseBasketButton()
    }

    private func addRecentItemFromHome(_ item: RecentBasketItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let previousQuantity = basketItems
            .first { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }?
            .quantity ?? 0
        basketManager.addRecentItem(item, in: modelContext, basketItems: basketItems)
        lastAdd = LastAddRecord(
            name: item.name,
            displayName: ProductDisplayNameProvider.displayName(for: item.name),
            emoji: item.emoji,
            previousQuantity: previousQuantity,
            addedAt: Date()
        )
        pulseBasketButton()
    }

    /// Snapshot a freshly-added QuickItem so we can offer to undo it.
    /// Called from every single-item add path; bulk paths clear `lastAdd` instead.
    private func recordLastAdd(item: QuickItem, previousQuantity: Int) {
        lastAdd = LastAddRecord(
            name: item.name,
            displayName: ProductDisplayNameProvider.displayName(for: item.name),
            emoji: item.emoji,
            previousQuantity: previousQuantity,
            addedAt: Date()
        )
    }

    /// Triggered by `BasketView.onCompletion`. Briefly surfaces a "Logged"
    /// pill at the top of home and clears any lingering `lastAdd` so the
    /// undo affordance doesn't reach back into a basket that no longer exists.
    private func showLoggedPill() {
        lastAdd = nil
        loggedPillDismissTask?.cancel()

        withAnimation(.taplistTransition) {
            loggedPillVisible = true
        }

        loggedPillDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            withAnimation(.taplistTransition) {
                loggedPillVisible = false
            }
        }
    }

    /// Undo the most recent add: either restore the previous quantity, or
    /// remove the item entirely if it wasn't in the basket before. No-op if
    /// `lastAdd` is gone (stale, removed, or already undone).
    private func performUndoLastAdd() {
        guard let record = lastAdd else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        basketManager.undoAddItem(
            named: record.name,
            previousQuantity: record.previousQuantity,
            in: modelContext,
            basketItems: basketItems
        )
        lastAdd = nil
    }

    private func hideRecentBasketFromHome(_ basket: RecentBasketSummary) {
        basketManager.removeRecentBasket(
            basket,
            completedBaskets: completedBaskets,
            completedEntries: completedEntries,
            in: modelContext
        )
    }

    /// Toggles `isStarred` on the underlying `CompletedBasket`. Starred
    /// baskets float to the top of their section in history — a tiny,
    /// lightweight "recurring shop" surface.
    private func toggleBasketStar(_ basket: RecentBasketSummary) {
        guard let stored = completedBaskets.first(where: { $0.id == basket.id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stored.isStarred.toggle()
        try? modelContext.save()
    }

    /// Stores a user-supplied nickname on the underlying `CompletedBasket`.
    /// An empty string clears the name and reinstates the auto-label.
    private func renameCompletedBasket(_ basket: RecentBasketSummary, to newName: String) {
        guard let stored = completedBaskets.first(where: { $0.id == basket.id }) else { return }
        stored.customName = newName.isEmpty ? nil : newName
        try? modelContext.save()
    }

    private func hintText(for item: QuickItem) -> String? {
        guard let hint = basketManager.purchaseHint(for: item.name, from: purchaseHints) else {
            return nil
        }

        return String(localized: "home.hint.top_count_format", defaultValue: "Top %lldx", locale: locale)
            .replacingOccurrences(of: "%lld", with: "\(hint.totalQuantity)")
    }

    /// Lowercased set of every seeded default item name. An item whose
    /// name is *not* in this set is a user creation — regardless of
    /// whether the user filed it under `.custom`, `.produce`, etc. —
    /// and therefore editable / deletable.
    private static let defaultSeedNames: Set<String> = Set(
        TapBasketApp.defaultQuickItems.map { $0.name.lowercased() }
    )

    /// True when the user can edit / delete this item. Anything not in
    /// the original seed catalogue counts as user-created.
    private func isUserCreated(_ item: QuickItem) -> Bool {
        !Self.defaultSeedNames.contains(item.name.lowercased())
    }

    /// Flips `item.pinned`. Pinned items surface at the top of the
    /// Regulars row regardless of purchase frequency.
    private func togglePin(_ item: QuickItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            item.pinned.toggle()
        }
        try? modelContext.save()
    }

    /// Removes a user-created item and any matching basket row. Refuses
    /// to delete seed items as a safety net even if called by mistake.
    private func deleteUserQuickItem(_ item: QuickItem) {
        guard isUserCreated(item) else { return }

        if let matchingBasketItem = basketItems.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
            modelContext.delete(matchingBasketItem)
        }

        modelContext.delete(item)
        try? modelContext.save()
    }

    /// Applies edits from the manual-add sheet (in edit mode) to an
    /// existing custom QuickItem. Keeps the matching `BasketItem` (if
    /// any) in sync so its visible name doesn't go stale.
    private func updateCustomQuickItem(
        _ item: QuickItem,
        name: String,
        emoji: String,
        category: QuickItemCategory
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalizedName = trimmed.capitalized
        let oldName = item.name

        // Renaming: update the linked basket entry too so the user
        // doesn't end up with a basket row showing the old name.
        if oldName.caseInsensitiveCompare(normalizedName) != .orderedSame,
           let basketRow = basketItems.first(where: { $0.name.caseInsensitiveCompare(oldName) == .orderedSame }) {
            basketRow.name = normalizedName
            basketRow.emoji = emoji
        } else if let basketRow = basketItems.first(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            // No rename, but emoji may have changed.
            basketRow.emoji = emoji
        }

        item.name = normalizedName
        item.emoji = emoji
        item.category = category
        try? modelContext.save()
    }

    #if DEBUG
    // MARK: - Debug menu

    @ViewBuilder
    private var debugMenuSheet: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show AI Recipe Button", isOn: Binding(
                        get: { FeatureFlags.aiRecipeEnabled },
                        set: { FeatureFlags.aiRecipeEnabled = $0; isRecipeAvailable = $0 }
                    ))
                    .tint(.green)
                } header: {
                    Text("Feature Flags")
                } footer: {
                    Text("Changes persist across launches via UserDefaults.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDebugMenu = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    #endif
}

#Preview {
    MainGridView()
        .modelContainer(PreviewContainer.make())
}
