import SwiftUI
import SwiftData

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

    private let minimumRecentBasketCount = 3

    private var recentBaskets: [RecentBasketSummary] {
        manager.recentBasketSummaries(baskets: completedBaskets, entries: completedEntries)
    }

    private var shouldShowRecentHistory: Bool {
        recentBaskets.count >= minimumRecentBasketCount
    }

    var body: some View {
        NavigationStack {
            listContent
                .scaleEffect(isCompletingBasket ? 0.988 : 1)
                .overlay { completionOverlay }
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
                .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isCompletingBasket)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: showCompletionBadge)
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
        .animation(.easeInOut(duration: 0.22), value: basketItems.count)
    }

    @ViewBuilder
    private var completionOverlay: some View {
        if showCompletionBadge {
            ZStack {
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white, Color.green)

                    Text(String(localized: "action.complete"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var basketSection: some View {
        Section(String(localized: "basket.section.current")) {
            if basketItems.isEmpty {
                ContentUnavailableView(
                    String(localized: "basket.empty.title"),
                    systemImage: "basket",
                    description: Text("basket.empty.description")
                )
                .transition(.opacity)
            } else {
                basketRows
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var recentHistorySection: some View {
        Section {
            RecentCompletedBasketsView(
                baskets: recentBaskets,
                onAddBasket: addRecentBasket,
                onAddItem: addRecentItem,
                onHideBasket: hideRecentBasket
            )
            .padding(.horizontal, -16)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var basketRows: some View {
        ForEach(basketItems) { item in
            BasketRowView(
                item: item,
                onToggleChecked: { manager.toggle(item, in: modelContext) },
                onIncrement: { manager.increment(item, in: modelContext) },
                onDecrement: { manager.decrement(item, in: modelContext) },
                onEditNote: { noteEditorItem = item }
            )
        }
        .onDelete(perform: deleteItems)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(String(localized: "action.done")) {
                dismiss()
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                completeCurrentBasket()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
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

        withAnimation(.spring(response: 0.2, dampingFraction: 0.88)) {
            isCompletingBasket = true
            showCompletionBadge = true
        }

        manager.completeBasket(basketItems, in: modelContext)

        Task {
            try? await Task.sleep(for: .milliseconds(2420))
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            manager.delete(basketItems[index], in: modelContext)
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
