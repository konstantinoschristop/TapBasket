import SwiftUI
import SwiftData
import TipKit

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

    @State private var basketManager = BasketManager()
    @State private var showBasket = false
    @State private var searchText = ""
    @State private var showManualAddSheet = false
    @State private var expandedCategories = Set<QuickItemCategory>()
    @State private var activeContextualSuggestionID: String?
    @State private var contextualTriggerName: String?
    @State private var contextualSuggestionTask: Task<Void, Never>?
    @State private var contextualSuggestionDuration: TimeInterval = 4.5

    @State private var activeSnackBarState: SnackBarState?
    @State private var queuedSnackBarStates: [SnackBarState] = []
    @State private var snackBarTask: Task<Void, Never>?
    @State private var snackBarDisplayDuration: TimeInterval = 2.6
    @State private var basketButtonScale: CGFloat = 1
    @State private var cachedCategoryUsage: [QuickItemCategory: Int] = [:]
    @Environment(PurchaseManager.self) private var purchaseManager
    @State private var showRecipeSheet = false
    @State private var showPaywall = false
    @State private var isRecipeAvailable = false

    private let addItemTip = AddItemTip()
    private let recipeAITip = RecipeAITip()

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    private var isShowingPopupOverlay: Bool {
        activeSnackBarState != nil || !contextualBoughtTogetherItems.isEmpty
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

    private var topShortcutItems: [TopUsedShortcutItem] {
        let shortcuts = basketManager.topUsedShortcuts(from: completedEntries)
        guard !shortcuts.isEmpty else { return [] }

        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return shortcuts.compactMap { shortcut -> TopUsedShortcutItem? in
            guard let item = itemsByName[shortcut.itemName.lowercased()] else { return nil }
            guard !basketItemNames.contains(item.name.lowercased()) else { return nil }
            return TopUsedShortcutItem(
                id: item.id,
                name: ProductDisplayNameProvider.displayName(for: item.name),
                emoji: item.emoji,
                totalQuantity: shortcut.totalQuantity,
                category: item.category
            )
        }
    }

    private var contextualBoughtTogetherItems: [BoughtTogetherWidgetItem] {
        guard let activeContextualSuggestionID, let contextualTriggerName else { return [] }

        let suggestions = basketManager.contextualBoughtTogetherSuggestions(
            triggeredBy: contextualTriggerName,
            entries: completedEntries,
            basketItems: basketItems,
            limit: 2
        )

        let itemsByName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let inBasket = basketItemNames

        return suggestions.compactMap { suggestion in
            guard suggestion.id == activeContextualSuggestionID else { return nil }

            let remainingItems = suggestion.itemNames.compactMap { name -> QuickItem? in
                let key = name.lowercased()
                guard let item = itemsByName[key], !inBasket.contains(key) else { return nil }
                return item
            }

            guard !remainingItems.isEmpty else { return nil }

            return BoughtTogetherWidgetItem(
                id: suggestion.id,
                title: remainingItems
                    .map { ProductDisplayNameProvider.displayName(for: $0.name) }
                    .joined(separator: " + "),
                subtitle: suggestionSubtitle(for: suggestion, remainingCount: remainingItems.count),
                emojiSummary: remainingItems.map(\.emoji).joined(separator: " ")
            )
        }
    }

    private var basketTriggerName: String {
        activeSnackBarState?.undoName ?? contextualTriggerName ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                scrollContent
                    .opacity(isShowingPopupOverlay ? 0.5 : 1)

                overlayControls
            }
            .navigationTitle(Text("home.navigation_title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .searchable(text: $searchText, prompt: Text("home.search_prompt"))
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
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
            }
            .sheet(isPresented: $showBasket) {
                BasketView(manager: basketManager)
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
            .onAppear(perform: syncExpandedCategories)
            .onAppear {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    isRecipeAvailable = true
                }
                #endif
            }
            .onChange(of: completedEntries, initial: true) { _, _ in recomputeCategoryUsage() }
            .onChange(of: quickItems) { _, _ in recomputeCategoryUsage() }
            .onChange(of: visibleCategories, initial: true) { _, _ in
                syncExpandedCategories()
            }
            .onChange(of: basketItems.map(\.name)) { _, _ in
                clearInvalidContextualSuggestion()
            }
        }
    }

    private var overlayControls: some View {
        VStack(spacing: 8) {
            if let state = activeSnackBarState {
                AddItemSnackBarView(
                    title: state.title,
                    progress: state.progress,
                    onUndo: undoLastAdd
                )
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !contextualBoughtTogetherItems.isEmpty {
                contextualSuggestionOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            basketButton
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: activeSnackBarState != nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.92), value: contextualBoughtTogetherItems.map(\.id))
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
                            onTapItem: addShortcutItemToBasket,
                            onAddAll: { topShortcutItems.forEach { addShortcutItemToBasket($0) } }
                        )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                ForEach(sectionedQuickItems) { section in
                    Section(isExpanded: expandedBinding(for: section.category)) {
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(section.items) { item in
                                itemTile(for: item)
                            }
                        }
                        .padding(.horizontal, 4)
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
        .animation(.easeInOut(duration: 0.22), value: basketItems.count)
    }


    private var contextualSuggestionOverlay: some View {
        BoughtTogetherWidgetView(items: contextualBoughtTogetherItems, onTapItem: addBoughtTogetherWidgetItemToBasket)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func itemTile(for item: QuickItem) -> some View {
        QuickItemTile(
            item: item,
            hintText: hintText(for: item),
            isInBasket: basketItemNames.contains(item.name.lowercased()),
            action: {
                addQuickItemToBasket(item)
            },
            onDelete: item.category == .custom ? {
                deleteCustomQuickItem(item)
            } : nil
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
        let label = HStack(spacing: 8) {
            Image(systemName: "basket.fill")
            Text(String(localized: "home.basket_button_format", defaultValue: "Basket (%lld)", locale: locale).replacingOccurrences(of: "%lld", with: "\(basketManager.totalItemCount(from: basketItems))"))
                .fontWeight(.semibold)
        }
        .font(.headline)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)

        Button {
            showBasket = true
        } label: {
            label
                .adaptiveGlass(in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .scaleEffect(basketButtonScale)
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded { expandedCategories.insert(category) }
                    else { expandedCategories.remove(category) }
                }
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
        let tint = categoryTintColor(for: section.category)
        return HStack(spacing: 12) {
            // App-icon-style square with gradient
            Image(systemName: section.category.systemImageName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [tint.mix(with: .white, by: 0.15), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: tint.opacity(0.35), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.category.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(.label))
                    .textCase(nil)

                Text("\(section.items.count) items")
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
                    .textCase(nil)
            }

            Spacer()

            if section.usageCount > 0 {
                Text("Top \(section.usageCount)×")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12), in: Capsule())
                    .textCase(nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func categoryTintColor(for category: QuickItemCategory) -> Color {
        switch category.tintName {
        case "green":  return .green
        case "red":    return .red
        case "orange": return .orange
        case "cyan":   return .cyan
        case "indigo": return .indigo
        case "teal":   return .teal
        case "pink":   return .pink
        case "gray":   return .gray
        case "purple": return .purple
        default:       return .blue
        }
    }

    private func syncExpandedCategories() {
        let visibleSet = Set(visibleCategories)
        let defaults = HomeBrowseState.defaultExpandedCategories(for: sectionedQuickItems.map(\.category))

        if expandedCategories.isEmpty {
            expandedCategories = defaults
            return
        }

        expandedCategories = expandedCategories.intersection(visibleSet)

        if expandedCategories.isEmpty {
            expandedCategories = defaults
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
            showSingleItemSnackBar(for: newQuickItem, previousQuantity: previousQuantity)
            updateContextualSuggestions(for: newQuickItem.name)
        }

        try? modelContext.save()
        searchText = ""
    }

    private func addQuickItemToBasket(_ item: QuickItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let previousQuantity = basketManager.addItem(item, in: modelContext, basketItems: basketItems)
        showSingleItemSnackBar(for: item, previousQuantity: previousQuantity)
        updateContextualSuggestions(for: item.name)
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

    private func addBoughtTogetherWidgetItemToBasket(_ item: BoughtTogetherWidgetItem) {
        guard let contextualTriggerName,
              let suggestion = basketManager.contextualBoughtTogetherSuggestions(
                triggeredBy: contextualTriggerName,
                entries: completedEntries,
                basketItems: basketItems,
                limit: 2
              ).first(where: { $0.id == item.id }) else { return }

        let result = basketManager.addBoughtTogetherSuggestion(suggestion, quickItems: quickItems, in: modelContext, basketItems: basketItems)
        showBulkAddSnackBar(result: result, emojiSummary: item.emojiSummary, affectedNames: suggestion.itemNames)
        clearInvalidContextualSuggestion()
    }

    private func suggestionSubtitle(for suggestion: BoughtTogetherSuggestion, remainingCount: Int) -> String {
        if remainingCount == 1 {
            return String(localized: "suggestion.subtitle.single")
        }
        return String(localized: "suggestion.subtitle.multiple")
    }

    private func updateContextualSuggestions(for itemName: String) {
        let suggestions = basketManager.contextualBoughtTogetherSuggestions(
            triggeredBy: itemName,
            entries: completedEntries,
            basketItems: basketItems,
            limit: 1
        )

        guard let suggestion = suggestions.first else {
            activeContextualSuggestionID = nil
            contextualTriggerName = nil
            contextualSuggestionTask?.cancel()
            contextualSuggestionTask = nil
            return
        }

        contextualSuggestionTask?.cancel()
        activeContextualSuggestionID = suggestion.id
        contextualTriggerName = itemName

        contextualSuggestionTask = Task {
            try? await Task.sleep(for: .seconds(contextualSuggestionDuration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeContextualSuggestionID = nil
                    contextualTriggerName = nil
                }
                contextualSuggestionTask = nil
            }
        }
    }

    private func clearInvalidContextualSuggestion() {
        guard let activeContextualSuggestionID, let contextualTriggerName else { return }

        let suggestions = basketManager.contextualBoughtTogetherSuggestions(
            triggeredBy: contextualTriggerName,
            entries: completedEntries,
            basketItems: basketItems,
            limit: 2
        )

        if !suggestions.contains(where: { $0.id == activeContextualSuggestionID }) {
            self.activeContextualSuggestionID = nil
            self.contextualTriggerName = nil
            contextualSuggestionTask?.cancel()
            contextualSuggestionTask = nil
        }
    }

    private func showSingleItemSnackBar(for item: QuickItem, previousQuantity: Int) {
        let displayName = ProductDisplayNameProvider.displayName(for: item.name)
        let format = String(localized: "snackbar.added_item_format", defaultValue: "Added %@ %@", locale: locale)
        let title = format
            .replacingOccurrences(of: "%@", with: item.emoji, options: [], range: format.range(of: "%@"))
            .replacingOccurrences(of: "%@", with: displayName)

        showSnackBar(
            title: title,
            previousQuantity: previousQuantity,
            undoName: item.name
        )
    }

    private func showBulkAddSnackBar(result: BulkAddResult, emojiSummary: String, affectedNames: [String]) {
        guard result.hasChanges else { return }

        let title: String
        switch (result.insertedCount, result.mergedCount) {
        case let (_, merged) where result.insertedCount > 0 && merged > 0:
            title = String(localized: "snackbar.bulk_added_some_updated_format", defaultValue: "Added some. Updated %lld already in basket", locale: locale)
                .replacingOccurrences(of: "%lld", with: "\(merged)")
        case let (_, merged) where merged > 0:
            title = String(localized: "snackbar.bulk_already_in_basket_updated_format", defaultValue: "Already in basket. Updated %lld", locale: locale)
                .replacingOccurrences(of: "%lld", with: "\(merged)")
        default:
            title = String(localized: "snackbar.bulk_added_default_format", defaultValue: "Added %@", locale: locale)
                .replacingOccurrences(of: "%@", with: emojiSummary)
        }

        showSnackBar(
            title: title,
            previousQuantity: 0,
            undoName: nil,
            basketSnapshot: affectedNames
        )
    }

    private func showSnackBar(
        title: String,
        previousQuantity: Int,
        undoName: String?,
        basketSnapshot: [String] = []
    ) {
        let newState = SnackBarState(
            id: UUID(),
            title: title,
            undoName: undoName,
            previousQuantity: previousQuantity,
            basketSnapshot: basketSnapshot,
            progress: 1
        )

        // Always present immediately, replacing any active or queued snackbar.
        // This prevents toast buildup when items are added rapidly.
        queuedSnackBarStates = []
        presentSnackBar(newState)
    }

    private func presentSnackBar(_ state: SnackBarState) {
        snackBarTask?.cancel()
        activeSnackBarState = state

        snackBarTask = Task {
            let start = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, 1 - (elapsed / snackBarDisplayDuration))

                await MainActor.run {
                    guard var visibleState = activeSnackBarState, visibleState.id == state.id else { return }
                    visibleState.progress = remaining
                    activeSnackBarState = visibleState
                }

                if remaining <= 0 {
                    break
                }

                try? await Task.sleep(for: .milliseconds(16))
            }

            await MainActor.run {
                guard activeSnackBarState?.id == state.id else { return }
                advanceSnackBarQueue()
            }
        }
    }

    private func advanceSnackBarQueue() {
        snackBarTask?.cancel()
        snackBarTask = nil
        activeSnackBarState = nil

        guard !queuedSnackBarStates.isEmpty else { return }
        let nextState = queuedSnackBarStates.removeFirst()
        presentSnackBar(nextState)
    }

    private func undoLastAdd() {
        guard let state = activeSnackBarState else { return }
        snackBarTask?.cancel()

        if let undoName = state.undoName {
            basketManager.undoAddItem(named: undoName, previousQuantity: state.previousQuantity, in: modelContext, basketItems: basketItems)
        } else {
            let currentItems = basketItems
            let targetNames = Set(state.basketSnapshot.map { $0.lowercased() })

            for item in currentItems where targetNames.contains(item.name.lowercased()) {
                if item.quantity > 1 {
                    item.quantity -= 1
                } else {
                    modelContext.delete(item)
                }
            }
            try? modelContext.save()
        }

        clearInvalidContextualSuggestion()
        advanceSnackBarQueue()
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

        clearInvalidContextualSuggestion()
    }
}


private struct SnackBarState: Identifiable, Equatable {
    let id: UUID
    var title: String
    var undoName: String?
    var previousQuantity: Int
    var basketSnapshot: [String]
    var progress: Double
}

#Preview {
    MainGridView()
        .modelContainer(PreviewContainer.make())
}
