import SwiftUI
import SwiftData
import TipKit

struct BasketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\BasketItem.name, order: .forward)]) private var basketItems: [BasketItem]
    @Query(sort: [SortDescriptor(\CompletedBasket.completedAt, order: .reverse)]) private var completedBaskets: [CompletedBasket]
    @Query(sort: [SortDescriptor(\CompletedBasketEntry.completedAt, order: .reverse)]) private var completedEntries: [CompletedBasketEntry]

    let manager: BasketManager

    @State private var feedbackMessage: String?
    @State private var noteEditorItem: BasketItem?
    @State private var isCompletingBasket = false
    @State private var showCompletionBadge = false
    @State private var isPreparingShare = false
    @State private var shareImage: UIImage?

    private let swipeToDeleteTip = SwipeToDeleteTip()
    private let shareBasketTip = ShareBasketTip()

    private var recentBaskets: [RecentBasketSummary] {
        manager.recentBasketSummaries(baskets: completedBaskets, entries: completedEntries)
    }

    private var shouldShowRecentHistory: Bool {
        !recentBaskets.isEmpty
    }

    private var regularItems: [BasketItem] {
        basketItems.filter { $0.recipeName == nil }
    }

    /// Recipe groups in insertion order (first seen name comes first).
    private var recipeGroups: [(name: String, items: [BasketItem])] {
        var dict: [String: [BasketItem]] = [:]
        var order: [String] = []
        for item in basketItems {
            guard let name = item.recipeName else { continue }
            if dict[name] == nil { order.append(name) }
            dict[name, default: []].append(item)
        }
        return order.map { (name: $0, items: dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle(Text("basket.screen_title"))
                .toolbar { toolbarContent }
                .alert(Text("basket.feedback.updated_title"), isPresented: isShowingFeedbackAlert) {
                    Button(String(localized: "action.done")) {}
                } message: {
                    Text(feedbackMessage ?? "")
                }
                .sheet(item: $noteEditorItem) { item in
                    BasketItemNoteEditorView(
                        itemName: item.name,
                        initialNote: item.note,
                        onSave: { note in
                            manager.saveNote(note, for: item, in: modelContext)
                        }
                    )
                    .presentationDetents([.medium])
                }
                .task(id: basketItems.count) { await prepareShareImage() }
        }
        .overlay {
            if showCompletionBadge {
                completionOverlay
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            basketSection

            if shouldShowRecentHistory {
                recentHistorySection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("LaunchBackground"))
        .onAppear {
            SwipeToDeleteTip.basketItemCount = basketItems.count
            ShareBasketTip.basketItemCount = basketItems.count
        }
        .onChange(of: basketItems.count) { _, count in
            SwipeToDeleteTip.basketItemCount = count
            ShareBasketTip.basketItemCount = count
        }
    }

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 84, height: 84)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce.up.byLayer, value: showCompletionBadge)
                }

                VStack(spacing: 5) {
                    Text("Basket completed!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Your items have been saved to history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.green.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var basketSection: some View {
        Section {
            TipView(swipeToDeleteTip)
                .tipBackground(Color("CardBackground"))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
        }

        if basketItems.isEmpty {
            Section {
                ContentUnavailableView(
                    String(localized: "basket.empty.title"),
                    systemImage: "basket",
                    description: Text("basket.empty.description")
                )
                .transition(.opacity)
            } header: {
                basketSectionHeader(itemCount: 0)
            }
        } else {
            if !regularItems.isEmpty {
                Section {
                    rows(for: regularItems)
                } header: {
                    basketSectionHeader(itemCount: regularItems.count)
                }
            }

            ForEach(recipeGroups, id: \.name) { group in
                Section {
                    rows(for: group.items)
                } header: {
                    recipeSectionHeader(name: group.name, itemCount: group.items.count)
                }
            }
        }
    }

    private func basketSectionHeader(itemCount: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "basket.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [Color.green.mix(with: .white, by: 0.18), Color.green],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: Color.green.opacity(0.35), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("basket.section.current")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .textCase(nil)
                if itemCount > 0 {
                    Text("\(itemCount) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func recipeSectionHeader(name: String, itemCount: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [Color.purple.mix(with: .white, by: 0.18), Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: Color.purple.opacity(0.35), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(name.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .textCase(nil)
                Text("\(itemCount) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var recentHistorySection: some View {
        Section {
            RecentCompletedBasketsView(
                baskets: recentBaskets,
                onAddBasket: addRecentBasket,
                onAddItem: addRecentItem,
                onHideBasket: hideRecentBasket
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func rows(for items: [BasketItem]) -> some View {
        ForEach(items) { item in
            BasketRowView(
                item: item,
                onToggleChecked: { manager.toggle(item, in: modelContext) },
                onIncrement: { manager.increment(item, in: modelContext) },
                onDecrement: { manager.decrement(item, in: modelContext) },
                onEditNote: { noteEditorItem = item }
            )
            .listRowBackground(Color("CardBackground"))
            .listRowSeparatorTint(Color.green.opacity(0.12))
        }
        .onDelete { offsets in
            for index in offsets {
                manager.delete(items[index], in: modelContext)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(String(localized: "action.done")) {
                dismiss()
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Group {
                if let image = shareImage, !isPreparingShare {
                    let swiftUIImage = Image(uiImage: image)
                    ShareLink(
                        item: swiftUIImage,
                        preview: SharePreview(
                            String(localized: "basket.share.title", defaultValue: "Shopping List"),
                            image: swiftUIImage
                        )
                    ) {
                        shareButtonIcon(loading: false)
                    }
                    .popoverTip(shareBasketTip)
                } else {
                    shareButtonIcon(loading: isPreparingShare)
                }
            }
            .disabled(basketItems.isEmpty || isCompletingBasket)

            Button {
                completeCurrentBasket()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(
                            colors: [Color.green.mix(with: .white, by: 0.2), Color.green],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
            }
            .disabled(basketItems.isEmpty || isCompletingBasket)
            .accessibilityLabel(Text("action.complete"))

            Button(role: .destructive) {
                manager.clearBasket(basketItems, in: modelContext)
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .disabled(basketItems.isEmpty || isCompletingBasket)
            .accessibilityLabel(Text("action.clear_basket"))
        }
    }

    private func shareButtonIcon(loading: Bool) -> some View {
        ZStack {
            Color.green.clipShape(Circle())
            if loading {
                ProgressView().tint(.white).scaleEffect(0.8)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
    }

    @MainActor
    private func prepareShareImage() async {
        guard !basketItems.isEmpty else { shareImage = nil; return }
        isPreparingShare = true
        await Task.yield()

        let regular = regularItems.map { BasketItemSnapshot(name: $0.name, emoji: $0.emoji, quantity: $0.quantity, note: $0.note) }
        let groups = recipeGroups.map { group in
            RecipeGroupSnapshot(name: group.name, items: group.items.map {
                BasketItemSnapshot(name: $0.name, emoji: $0.emoji, quantity: $0.quantity, note: $0.note)
            })
        }

        shareImage = BasketExporter.renderImage(regularItems: regular, recipeGroups: groups)
        isPreparingShare = false
    }

    private var isShowingFeedbackAlert: Binding<Bool> {
        Binding(
            get: { feedbackMessage != nil },
            set: { newValue in
                if !newValue {
                    feedbackMessage = nil
                }
            }
        )
    }

    private func completeCurrentBasket() {
        guard !basketItems.isEmpty, !isCompletingBasket else { return }
        isCompletingBasket = true

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showCompletionBadge = true
        }

        manager.completeBasket(basketItems, in: modelContext)

        Task {
            try? await Task.sleep(for: .milliseconds(1800))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCompletionBadge = false
                }
                isCompletingBasket = false
            }
        }
    }


    private func addRecentItem(_ item: RecentBasketItem) {
        manager.addRecentItem(item, in: modelContext, basketItems: basketItems)
    }

    private func addRecentBasket(_ basket: RecentBasketSummary) {
        let result = manager.addRecentBasket(basket, in: modelContext, basketItems: basketItems)
        feedbackMessage = feedbackMessage(for: result)
    }

    private func hideRecentBasket(_ basket: RecentBasketSummary) {
        manager.removeRecentBasket(
            basket,
            completedBaskets: completedBaskets,
            completedEntries: completedEntries,
            in: modelContext
        )
    }

    private func feedbackMessage(for result: BulkAddResult) -> String? {
        guard result.hasChanges else { return nil }

        switch (result.insertedCount, result.mergedCount) {
        case let (inserted, merged) where inserted > 0 && merged > 0:
            return String(localized: "basket.feedback.added_updated_format", defaultValue: "Added %lld new items. Updated %lld items already in your basket.", locale: locale)
                .replacingOccurrences(of: "%lld", with: "\(inserted)", options: [], range: String(localized: "basket.feedback.added_updated_format", defaultValue: "Added %lld new items. Updated %lld items already in your basket.", locale: locale).range(of: "%lld"))
                .replacingOccurrences(of: "%lld", with: "\(merged)")
        case let (_, merged) where merged > 0:
            return String(localized: "basket.feedback.all_updated")
        case let (inserted, _) where inserted > 0:
            return String(localized: "basket.feedback.added_items_format", defaultValue: "Added %lld items to your basket.", locale: locale)
                .replacingOccurrences(of: "%lld", with: "\(inserted)")
        default:
            return nil
        }
    }
}

#Preview {
    BasketView(manager: BasketManager())
        .modelContainer(PreviewContainer.make())
}
