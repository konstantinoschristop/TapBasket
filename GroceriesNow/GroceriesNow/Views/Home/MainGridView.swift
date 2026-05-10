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
    @State private var smartStartItems: [QuickItem] = []
    @Environment(PurchaseManager.self) private var purchaseManager
    @State private var showRecipeSheet = false
    @State private var showPaywall = false
    @State private var showRecentBasketsSheet = false
    @State private var isRecipeAvailable = false
    #if DEBUG
    @State private var showDebugMenu = false
    @AppStorage("flag_aiRecipeRequiresPro") private var aiRecipeRequiresPro: Bool = true
    #endif
    @AppStorage("collapsedCategoryKeys") private var collapsedCategoryKeys: String = ""

    private let addItemTip = AddItemTip()
    private let recipeAITip = RecipeAITip()

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
                .overlay(alignment: .top) {
                    loggedPill
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
                            if FeatureFlags.aiRecipeRequiresPro && !purchaseManager.isPro {
                                showPaywall = true
                            } else {
                                showRecipeSheet = true
                                recipeAITip.invalidate(reason: .actionPerformed)
                            }
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
            .sheet(isPresented: $showBasket) {
                BasketView(manager: basketManager, onCompletion: showLoggedPill)
            }
            .sheet(isPresented: $showManualAddSheet) {
                ManualQuickItemSheet(initialName: trimmedSearch, onSave: saveManualQuickItem)
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
            .sheet(isPresented: $showPaywall) {
                ProPaywallSheet(purchaseManager: purchaseManager)
                    .presentationDetents([.large])
            }
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
            .onChange(of: basketItems.map(\.name)) { _, _ in
                refreshSmartStart()
            }
            .onChange(of: completedEntries.count) { _, _ in refreshSmartStart() }
            .onAppear { refreshSmartStart() }
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

    /// Floating bottom controls. No heavy bar background — the basket button itself
    /// is a glass capsule that floats over the scroll content. `safeAreaInset` still
    /// pushes scroll content up by the bar's height so nothing is hidden behind it.
    ///
    /// When the basket is empty, the button fades + scales out smoothly. We keep
    /// it MOUNTED (rather than conditionally rendering) so the safeAreaInset's
    /// height doesn't collapse mid-transition — that collapse was clipping the
    /// button's capsule + shadow to its shrinking container, leaving a brief
    /// frame artifact at the bottom edge. Tradeoff is a small reserved space
    /// when empty, which is invisible since `basketButton` already styles
    /// itself as inert (`.disabled(isEmpty)`).
    private var bottomBar: some View {
        basketButton
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(basketItems.isEmpty ? 0 : 1)
            .scaleEffect(basketItems.isEmpty ? 0.85 : 1)
            .animation(.taplistTransition, value: basketItems.isEmpty)
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
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                }

                if !topShortcutItems.isEmpty {
                    Section {
                        TopUsedShortcutsView(
                            items: topShortcutItems,
                            inBasketNames: basketItemNames,
                            onTapItem: toggleShortcutItemInBasket,
                            onAddAll: { topShortcutItems.forEach { addShortcutItemToBasket($0) } }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                if !smartStartItems.isEmpty {
                    Section {
                        SmartStartView(
                            items: smartStartItems,
                            onTapItem: addQuickItemToBasket,
                            onAddAll: { smartStartItems.forEach { addQuickItemToBasket($0) } }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                ForEach(sectionedQuickItems) { section in
                    Section(isExpanded: expandedBinding(for: section.category)) {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(section.items) { item in
                                itemTile(for: item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(.zero))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } header: {
                        categorySectionHeader(for: section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color("LaunchBackground"))
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: basketItems.count)
    }


    private func itemTile(for item: QuickItem) -> some View {
        QuickItemTile(
            item: item,
            isInBasket: basketItemNames.contains(item.name.lowercased()),
            quantity: basketQuantitiesByName[item.name.lowercased()] ?? 0,
            // Tap toggles: add if out, remove if in. Long-press increments
            // (the rare case). The tile suppresses the tap-on-release after
            // a successful long-press so the toggle never fires accidentally.
            action: { toggleQuickItemInBasket(item) },
            onLongPress: { incrementQuickItemInBasket(item) },
            onDelete: item.category == .custom ? { deleteCustomQuickItem(item) } : nil
        )
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
    private var basketButton: some View {
        let count = basketManager.totalItemCount(from: basketItems)
        let isEmpty = count == 0

        Button {
            showBasket = true
        } label: {
            HStack(spacing: 12) {
                // Bubbles are the focal element. When empty the button is
                // hidden via opacity, so the icon is just an intermediate
                // state during the fade.
                if !basketItems.isEmpty {
                    BasketItemBubbles(emojis: basketItems.map(\.emoji), size: .standard)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "basket.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 62, height: 62)
                        .transition(.scale.combined(with: .opacity))
                }

                // Stat-style typography: count is the hero, label is a small
                // tracked uppercase caption underneath.
                VStack(alignment: .leading, spacing: -1) {
                    Text("\(count)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: count)

                    Text("home.basket_button.label")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
            }
            .foregroundStyle(isEmpty ? Color(.tertiaryLabel) : Color(.label))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            // No maxWidth — pill hugs its content. fixedSize gives it priority
            // over any ambient parent stretching (e.g. safeAreaInset).
            .fixedSize(horizontal: true, vertical: false)
            .adaptiveGlass(in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
            .contentShape(Capsule())
            .animation(.taplistTransition, value: basketItems.isEmpty)
        }
        .buttonStyle(.spring(scale: 0.97))
        .disabled(isEmpty)
        .scaleEffect(basketButtonScale)
        // Long-press surfaces an Undo affordance for the most recent add.
        // Empty when there's nothing to undo, so SwiftUI suppresses the menu.
        .contextMenu {
            if let record = lastAdd, record.isFresh {
                let label = String(localized: "action.undo_format", defaultValue: "Undo %@", locale: locale)
                    .replacingOccurrences(of: "%@", with: "\(record.emoji) \(record.displayName)")
                Button(role: .destructive, action: performUndoLastAdd) {
                    Label(label, systemImage: "arrow.uturn.backward")
                }
            }
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

    private func isExpanded(_ category: QuickItemCategory) -> Bool {
        expandedCategories.contains(category)
    }

    private func toggleSection(_ category: QuickItemCategory) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private func expandedBinding(for category: QuickItemCategory) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { expanded in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    if expanded { expandedCategories.insert(category) }
                    else { expandedCategories.remove(category) }
                }
                // Persist collapsed set (store collapsed, not expanded, so default is all-expanded)
                let collapsed = Set(QuickItemCategory.allCases).subtracting(expandedCategories)
                collapsedCategoryKeys = collapsed.map(\.rawValue).sorted().joined(separator: ",")
            }
        )
    }

    private func itemRow(for item: QuickItem) -> some View {
        Button {
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
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categorySectionHeader(for section: QuickItemSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.category.systemImageName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(section.category.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(.label))
                .textCase(nil)
                .tracking(-0.2)

            Text("\(section.items.count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.tertiaryLabel))
                .monospacedDigit()
                .textCase(nil)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func refreshSmartStart() {
        smartStartItems = SmartStartEngine.shared.items(
            quickItems: quickItems,
            basketItems: basketItems,
            in: modelContext
        )
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

    private func addShortcutItemToBasket(_ shortcut: TopUsedShortcutItem) {
        guard let item = quickItems.first(where: { $0.id == shortcut.id }) else { return }
        addQuickItemToBasket(item)
    }

    /// Tap on a Regulars avatar — toggles the underlying QuickItem's basket
    /// membership, matching the grid tile's behaviour.
    private func toggleShortcutItemInBasket(_ shortcut: TopUsedShortcutItem) {
        guard let item = quickItems.first(where: { $0.id == shortcut.id }) else { return }
        toggleQuickItemInBasket(item)
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

    private func hintText(for item: QuickItem) -> String? {
        guard let hint = basketManager.purchaseHint(for: item.name, from: purchaseHints) else {
            return nil
        }

        return String(localized: "home.hint.top_count_format", defaultValue: "Top %lldx", locale: locale)
            .replacingOccurrences(of: "%lld", with: "\(hint.totalQuantity)")
    }

    private func deleteCustomQuickItem(_ item: QuickItem) {
        guard item.category == .custom else { return }

        if let matchingBasketItem = basketItems.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
            modelContext.delete(matchingBasketItem)
        }

        modelContext.delete(item)
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
                    Toggle("Require Pro for AI Recipe", isOn: $aiRecipeRequiresPro)
                        .tint(.green)
                } header: {
                    Text("Feature Flags")
                } footer: {
                    Text("Changes persist across launches via UserDefaults.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("isPro")
                        Spacer()
                        Text(purchaseManager.isPro ? "true" : "false")
                            .foregroundStyle(.secondary)
                    }
                    Button("Restore Purchases") {
                        Task { await purchaseManager.restorePurchases() }
                    }
                } header: {
                    Text("Purchase Manager")
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
