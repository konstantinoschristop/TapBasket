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

/// State for the ephemeral post-add suggestion pill. Captures the item
/// that triggered the suggestion + the recommended partner so the pill
/// has everything it needs without re-querying on render.
private struct SuggestionPayload {
    let addedName: String           // canonical (basket-item) name of the just-added item
    let addedDisplayName: String    // localized display
    let addedEmoji: String
    let suggestion: PartnerSuggestion?

    struct PartnerSuggestion {
        /// Canonical (lowercased) name as returned by `RecommendationEngine`.
        let canonical: String
        let displayName: String
        let emoji: String
        /// Stable key for `RecommendationEngine.recordIgnored` so the
        /// engine can decay this pair's score when the pill is dismissed
        /// without being acted on.
        let suggestionID: String
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
    /// Ephemeral post-add suggestion pill. Set whenever the user adds
    /// an item; cleared when the user acts on it, dismisses it, or the
    /// auto-dismiss timer fires.
    @State private var pendingSuggestion: SuggestionPayload? = nil
    @State private var suggestionDismissTask: Task<Void, Never>?
    @State private var cachedCategoryUsage: [QuickItemCategory: Int] = [:]
    @State private var showRecipeSheet = false
    @State private var showRecentBasketsSheet = false
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
        guard !shortcuts.isEmpty else { return [] }

        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Note: we deliberately don't filter out items already in the basket.
        // Regulars are essential affordances — they belong on the home screen
        // permanently. The avatar shows an "added" state instead.
        return shortcuts.compactMap { shortcut -> TopUsedShortcutItem? in
            guard let item = itemsByName[shortcut.itemName.lowercased()] else { return nil }
            return TopUsedShortcutItem(
                id: item.id,
                name: ProductDisplayNameProvider.displayName(for: item.name),
                emoji: item.emoji,
                totalQuantity: shortcut.totalQuantity,
                category: item.category
            )
        }
    }

    var body: some View {
        NavigationStack {
            scrollContent
                .overlay(alignment: .top) {
                    loggedPill
                }
                .overlay(alignment: .bottom) {
                    suggestionPill
                        .padding(.bottom, 16)
                        .padding(.horizontal, 20)
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
            .sheet(isPresented: $showRecentBasketsSheet) {
                RecentBasketsSheet(
                    baskets: recentBasketSummaries,
                    inBasketNames: basketItemNames,
                    onAddBasket: addRecentBasketFromHome,
                    onAddItem: addRecentItemFromHome,
                    onHideBasket: hideRecentBasketFromHome
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
    /// Ephemeral capsule shown at the bottom of the home screen after an
    /// add: confirms the action and, if the recommendation engine has a
    /// suggestion, offers it as a one-tap follow-up. Auto-dismisses
    /// after ~2.5s; an ignored suggestion is penalised in the engine.
    @ViewBuilder
    private var suggestionPill: some View {
        if let payload = pendingSuggestion {
            InlineSuggestionPill(
                addedEmoji: payload.addedEmoji,
                addedName: payload.addedDisplayName,
                suggestionEmoji: payload.suggestion?.emoji,
                suggestionName: payload.suggestion?.displayName,
                onTapSuggestion: { acceptSuggestion(payload) },
                onDismiss: { dismissSuggestion(payload, asIgnored: true) }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

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
                if filteredQuickItems.isEmpty {
                    Section {
                        emptySearchContent
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                } else {
                    Section {
                        ForEach(filteredQuickItems) { item in
                            itemRow(for: item)
                        }
                    }
                    if shouldShowManualAddButton {
                        Section { manualAddButton }
                            .listRowBackground(Color.clear)
                    }
                }
            } else {
                Section {
                    TipView(addItemTip)
                        .tipBackground(Color("CardBackground"))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
                }

                if !topShortcutItems.isEmpty {
                    Section {
                        TopUsedShortcutsView(
                            items: topShortcutItems,
                            inBasketNames: basketItemNames,
                            onTapItem: toggleShortcutItemInBasket,
                            onAddAll: addAllRegulars
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                // Universal "anyone would buy" rail — sits below the
                // personalised Regulars row. Items already in the basket
                // fade out of the loop.
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
            // Tap toggles: add if out, remove if in. Long-press increments
            // (the rare case). The tile suppresses the tap-on-release after
            // a successful long-press so the toggle never fires accidentally.
            action: { toggleQuickItemInBasket(item) },
            onLongPress: { incrementQuickItemInBasket(item) },
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
            onLongPress: { incrementQuickItemInBasket(item) }
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
                    featuredTile(for: featured, width: nil, height: 150)
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
                // Leading-only inset so the first tile has breathing
                // room from the screen edge, but tiles scroll cleanly
                // *off* the trailing edge instead of stopping short.
                .padding(.leading, 20)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()

        case .chipRow:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { chipFor($0) }
                }
                .padding(.leading, 20)
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
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
        }
        .padding(.top, 40)
    }

    private var manualAddButton: some View {
        Button {
            showManualAddSheet = true
        } label: {
            Label {
                Text(String(localized: "action.create_format", defaultValue: "Create \"%@\"", locale: locale).replacingOccurrences(of: "%@", with: trimmedSearch))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            } icon: {
                Image(systemName: "plus.circle.fill")
            }
        }
        .buttonStyle(.bordered)
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
        isSearching && !hasExactNameMatch && !filteredQuickItems.isEmpty
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
        if lhs.category == .custom, rhs.category != .custom {
            return true
        }

        if rhs.category == .custom, lhs.category != .custom {
            return false
        }

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

        return Button {
            addQuickItemToBasket(item)
        } label: {
            HStack(spacing: 14) {
                Text(item.emoji)
                    .font(.title2)
                    .frame(width: 36, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductDisplayNameProvider.displayName(for: item.name))
                        .foregroundStyle(.primary)

                    if let hint = hintText(for: item) {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // In-basket badge — same vocabulary as QuickItemTile and the
                // Regulars avatars: BrandGreen checkmark with optional ×N
                // counter when the user taps to add more than one.
                if isInBasket {
                    HStack(spacing: 5) {
                        if quantity > 1 {
                            Text("×\(quantity)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color("BrandGreen"))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(quantity)))
                        }
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color("BrandGreen"), in: Circle())
                            .symbolEffect(.bounce, options: .nonRepeating, value: quantity)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: quantity)
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

        if let existingItem = quickItems.first(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
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
        scheduleSuggestionPill(for: item)
    }

    // MARK: - Inline suggestion pill

    /// Fetches a partner suggestion for the just-added item, packages
    /// it for the pill, and starts the auto-dismiss timer. Safe to call
    /// every single-item add; resolves to a confirmation-only pill (no
    /// suggestion chunk) when the engine has nothing relevant.
    private func scheduleSuggestionPill(for item: QuickItem) {
        // Exclude everything currently in the basket *and* the item we
        // just added, so the engine doesn't suggest something the user
        // already has.
        var excluded = basketItemNames
        excluded.insert(item.name.lowercased())

        let partnerCanonical = RecommendationEngine.shared.bestSuggestion(
            for: item.name,
            excluding: excluded,
            in: modelContext
        )

        let partner: SuggestionPayload.PartnerSuggestion? = partnerCanonical.flatMap { canonical in
            // Try to resolve the partner to an existing QuickItem so we
            // can use its emoji; fall back to a generic if not found.
            let resolved = quickItems.first {
                $0.name.lowercased() == canonical.lowercased()
            }
            let displayName = ProductDisplayNameProvider.displayName(for: resolved?.name ?? canonical)
            let emoji = resolved?.emoji ?? "🛒"
            let sortedPair = [item.name.lowercased(), canonical.lowercased()].sorted()
            return .init(
                canonical: canonical,
                displayName: displayName,
                emoji: emoji,
                suggestionID: sortedPair.joined(separator: "|")
            )
        }

        let payload = SuggestionPayload(
            addedName: item.name,
            addedDisplayName: ProductDisplayNameProvider.displayName(for: item.name),
            addedEmoji: item.emoji,
            suggestion: partner
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            pendingSuggestion = payload
        }

        suggestionDismissTask?.cancel()
        suggestionDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            dismissSuggestion(payload, asIgnored: true)
        }
    }

    /// Adds the suggested partner via the standard `addQuickItemToBasket`
    /// path, then dismisses the pill. The recursive call re-triggers
    /// `recordLastAdd`, which would schedule *another* pill — that's
    /// fine: the new pill replaces the current one and chains the
    /// shopping flow naturally.
    private func acceptSuggestion(_ payload: SuggestionPayload) {
        guard let partner = payload.suggestion else { return }
        suggestionDismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            pendingSuggestion = nil
        }
        if let match = quickItems.first(where: {
            $0.name.caseInsensitiveCompare(partner.canonical) == .orderedSame
        }) {
            addQuickItemToBasket(match)
        }
    }

    /// Hides the pill. When `asIgnored` is true, also tells the engine
    /// to decay this pair's score so the same suggestion isn't surfaced
    /// repeatedly when the user keeps not engaging with it.
    private func dismissSuggestion(_ payload: SuggestionPayload, asIgnored: Bool) {
        suggestionDismissTask?.cancel()
        if asIgnored, let partner = payload.suggestion {
            RecommendationEngine.shared.recordIgnored(suggestionID: partner.suggestionID)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            pendingSuggestion = nil
        }
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
