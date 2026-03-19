import SwiftUI
import SwiftData

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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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

    private var categoryUsage: [QuickItemCategory: Int] {
        let quickItemByName = Dictionary(uniqueKeysWithValues: quickItems.map { ($0.name.lowercased(), $0) })

        return completedEntries.reduce(into: [QuickItemCategory: Int]()) { result, entry in
            guard let item = quickItemByName[entry.name.lowercased()] else { return }
            result[item.category, default: 0] += entry.quantity
        }
    }

    private var sectionedQuickItems: [QuickItemSection] {
        QuickItemCategory.orderedBrowseCategories
            .compactMap { category in
                let items = quickItems.filter { $0.category == category }
                guard !items.isEmpty else { return nil }
                return QuickItemSection(
                    category: category,
                    items: items,
                    usageCount: categoryUsage[category, default: 0]
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

        return shortcuts.compactMap { shortcut in
            guard let item = quickItems.first(where: {
                $0.name.caseInsensitiveCompare(shortcut.itemName) == .orderedSame
            }) else {
                return nil
            }

            return TopUsedShortcutItem(
                id: item.id,
                name: ProductDisplayNameProvider.displayName(for: item.name),
                emoji: item.emoji,
                totalQuantity: shortcut.totalQuantity
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

        return suggestions.compactMap { suggestion in
            guard suggestion.id == activeContextualSuggestionID else { return nil }

            let remainingItems = suggestion.itemNames.compactMap { name in
                quickItems.first { quickItem in
                    quickItem.name.caseInsensitiveCompare(name) == .orderedSame &&
                    !basketItems.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
                }
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

                popupBackdrop

                overlayControls
            }
            .navigationTitle(Text("home.navigation_title"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: Text("home.search_prompt"))
            .sheet(isPresented: $showBasket) {
                BasketView(manager: basketManager)
            }
            .sheet(isPresented: $showManualAddSheet) {
                ManualQuickItemSheet(initialName: trimmedSearch, onSave: saveManualQuickItem)
            }
            .onAppear(perform: syncExpandedCategories)
            .onChange(of: visibleCategories, initial: true) { _, _ in
                syncExpandedCategories()
            }
            .onChange(of: basketItems.map(\.name)) { _, _ in
                clearInvalidContextualSuggestion()
            }
        }
    }

    @ViewBuilder
    private var popupBackdrop: some View {
        if isShowingPopupOverlay {
            Color.black
                .opacity(0.08)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.14), value: isShowingPopupOverlay)
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
        ScrollView {
            if filteredQuickItems.isEmpty, isSearching {
                emptySearchContent
            } else if isSearching {
                searchResultsSection
            } else {
                browseSections
            }

            if shouldShowManualAddButton {
                manualAddButton
                    .padding(.top, 12)
                    .padding(.horizontal)
            }

            Spacer(minLength: 100)
        }
    }

    private var searchResultsSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredQuickItems) { item in
                itemTile(for: item)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    private var browseSections: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            if !topShortcutItems.isEmpty {
                TopUsedShortcutsView(items: topShortcutItems, onTapItem: addShortcutItemToBasket)
            }

            ForEach(sectionedQuickItems) { section in
                sectionView(for: section)

            }
        }
        .padding(.top, 16)
    }

    private var contextualSuggestionOverlay: some View {
        BoughtTogetherWidgetView(items: contextualBoughtTogetherItems, onTapItem: addBoughtTogetherWidgetItemToBasket)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sectionView(for section: QuickItemSection) -> some View {
        CollapsibleQuickItemSection(
            title: section.category.title,
            systemImageName: section.category.systemImageName,
            tintName: section.category.tintName,
            itemCount: section.items.count,
            usageCount: section.usageCount,
            isExpanded: isExpanded(section.category),
            onToggle: {
                toggleSection(section.category)
            }
        ) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(section.items) { item in
                    itemTile(for: item)
                }
            }
        }
        .padding(.horizontal)
    }

    private func itemTile(for item: QuickItem) -> some View {
        QuickItemTile(
            item: item,
            hintText: hintText(for: item),
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

    private var basketButton: some View {
        Button {
            showBasket = true
        } label: {
            HStack(spacing: 8) {
                Text("🧺")
                Text(String(localized: "home.basket_button_format", defaultValue: "Basket (%lld)", locale: locale).replacingOccurrences(of: "%lld", with: "\(basketManager.totalItemCount(from: basketItems))"))
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color(.separator).opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        }
    }

    private var shouldShowManualAddButton: Bool {
        isSearching && !hasExactNameMatch && !filteredQuickItems.isEmpty
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
        let previousQuantity = basketManager.addItem(item, in: modelContext, basketItems: basketItems)
        showSingleItemSnackBar(for: item, previousQuantity: previousQuantity)
        updateContextualSuggestions(for: item.name)
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

        if activeSnackBarState == nil {
            presentSnackBar(newState)
        } else {
            queuedSnackBarStates.append(newState)
        }
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
