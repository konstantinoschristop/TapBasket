import SwiftUI

/// History sheet listing recent shopping trips. Each basket is one compact row
/// — bubble preview + date + count + ellipsis. The whole row is a `Menu`
/// trigger; the menu itself is the only interaction surface.
///
/// Menu contents per basket:
/// * One button per item — tap to add that single item to the current basket.
/// * "Add all" — bulk-adds the whole shop and dismisses the sheet.
/// * "Hide this shop" — destructive, removes the basket from the list.
///
/// No inline expand/collapse, no per-row state. Items live entirely inside the
/// menu, so the list stays dense and scannable regardless of basket size.
struct RecentBasketsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let baskets: [RecentBasketSummary]
    /// Lowercased names of items currently in the active basket — drives the
    /// "Add all" suppression when every item in a past shop is already added.
    let inBasketNames: Set<String>
    let onAddBasket: (RecentBasketSummary) -> Void
    let onAddItem: (RecentBasketItem) -> Void
    let onHideBasket: (RecentBasketSummary) -> Void

    // MARK: - State

    /// Snapshot of baskets taken on first appear. Isolates the list from parent
    /// re-renders triggered by SwiftData writes (every onAddItem call).
    @State private var displayedBaskets: [RecentBasketSummary] = []
    @State private var displayLimit: Int = 10

    private let pageSize = 10

    private var visibleBaskets: [RecentBasketSummary] {
        Array(displayedBaskets.prefix(displayLimit))
    }

    private var hasMore: Bool {
        displayLimit < displayedBaskets.count
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
            // Snapshot once — subsequent parent re-renders won't touch this.
            if displayedBaskets.isEmpty {
                displayedBaskets = baskets
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if displayedBaskets.isEmpty {
            emptyState
        } else {
            List {
                ForEach(visibleBaskets) { basket in
                    basketRow(for: basket)
                        .listRowBackground(Color("CardBackground"))
                }

                if hasMore {
                    showMoreRow
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color("LaunchBackground"))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "recent_baskets.empty.title"),
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: Text("recent_baskets.empty.description")
        )
    }

    // MARK: - Show-more row

    private var showMoreRow: some View {
        let remaining = baskets.count - displayLimit
        let nextBatch = min(pageSize, remaining)
        return Button {
            withAnimation(.taplistTransition) {
                displayLimit += pageSize
            }
        } label: {
            HStack(spacing: 8) {
                Spacer()
                Text("Show \(nextBatch) more")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color("CardBackground"))
    }

    // MARK: - Basket row

    private func basketRow(for basket: RecentBasketSummary) -> some View {
        let isToday = Calendar.current.isDateInToday(basket.completedAt)
        let totalQuantity = basket.items.reduce(0) { $0 + $1.quantity }
        // When every item in this basket is already in the active basket,
        // "Add all" is a no-op — suppress it so the menu only offers
        // meaningful actions.
        let allItemsAlreadyInBasket = basket.items.allSatisfy {
            inBasketNames.contains($0.name.lowercased())
        }

        return Menu {
            // Items as tappable buttons — picking adds that single item to
            // the current basket. Sheet stays open so the user can keep
            // picking from the same or other shops.
            ForEach(basket.items) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAddItem(item)
                } label: {
                    Text("\(item.emoji) \(ProductDisplayNameProvider.displayName(for: item.name))")
                }
            }

            Section {
                if !allItemsAlreadyInBasket {
                    Button {
                        onAddBasket(basket)
                        dismiss()
                    } label: {
                        Label("Add all \(basket.items.count) items", systemImage: "cart.badge.plus")
                    }
                }

                Button(role: .destructive) {
                    onHideBasket(basket)
                    withAnimation(.taplistTransition) {
                        displayedBaskets.removeAll { $0.id == basket.id }
                    }
                } label: {
                    Label("Hide this shop", systemImage: "eye.slash")
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                BasketItemBubbles(emojis: basket.items.map(\.emoji), size: .compact)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(relativeDateString(basket.completedAt))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)

                        if isToday {
                            Text("history.today_pill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color("BrandGreen"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color("BrandGreen").opacity(0.15), in: Capsule())
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }
                    }

                    Text(itemSummaryLabel(count: basket.items.count, totalQuantity: totalQuantity))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(.secondaryLabel))
                        .textCase(nil)
                        .monospacedDigit()
                }

                Spacer()

                // Visible affordance — signals tappable + that more options
                // live behind the row.
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting

    /// "8 items" when every item is qty 1, "8 items · 12 total" when at least
    /// one item has qty > 1. Avoids the redundant "8 items · 8 total" case.
    private func itemSummaryLabel(count: Int, totalQuantity: Int) -> String {
        let countLabel = String(
            localized: "recent_baskets.item_count_format",
            defaultValue: "\(count) items",
            locale: locale
        )
        guard totalQuantity > count else { return countLabel }
        let totalLabel = String(
            localized: "history.total_qty_format",
            defaultValue: "\(totalQuantity) total",
            locale: locale
        )
        return "\(countLabel) · \(totalLabel)"
    }

    private func relativeDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
