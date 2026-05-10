import SwiftUI
import SwiftData
import TipKit

struct BasketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\BasketItem.name, order: .forward)]) private var basketItems: [BasketItem]

    let manager: BasketManager
    /// Fired once the completion overlay has finished playing. Parent uses this
    /// to surface a brief post-completion confirmation on the home screen.
    var onCompletion: (() -> Void)? = nil

    @State private var noteEditorItem: BasketItem?
    @State private var isCompletingBasket = false
    @State private var showCompletionBadge = false
    @State private var isPreparingShare = false
    @State private var shareImage: UIImage?

    private let swipeToDeleteTip = SwipeToDeleteTip()
    private let shareBasketTip = ShareBasketTip()

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
        return order.map { (name: $0, items: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle(Text("basket.screen_title"))
                .toolbar { toolbarContent }
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
                BasketCompletionOverlay()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    ))
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            basketSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("LaunchBackground"))
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: basketItems.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: recipeGroups.map(\.name))
        .onAppear {
            SwipeToDeleteTip.basketItemCount = basketItems.count
            ShareBasketTip.basketItemCount = basketItems.count
        }
        .onChange(of: basketItems.count) { _, count in
            SwipeToDeleteTip.basketItemCount = count
            ShareBasketTip.basketItemCount = count
        }
    }

    @ViewBuilder
    private var basketSection: some View {
        // Hero header — only when basket has items. Replaces the small section title.
        if !basketItems.isEmpty {
            Section {
                BasketSummaryHeader(items: basketItems)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        Section {
            TipView(swipeToDeleteTip)
                .tipBackground(Color("CardBackground"))
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if basketItems.isEmpty {
            Section {
                ContentUnavailableView(
                    String(localized: "basket.empty.title"),
                    systemImage: "basket",
                    description: Text("basket.empty.description")
                )
                .transition(.opacity)
                .listRowBackground(Color.clear)
            }
        } else {
            if !regularItems.isEmpty {
                Section {
                    rows(for: regularItems)
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

    private func recipeSectionHeader(name: String, itemCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(name.capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
                .textCase(nil)

            Text("\(itemCount)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(.tertiaryLabel))
                .monospacedDigit()
                .textCase(nil)

            Spacer()
        }
        .padding(.vertical, 2)
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
            .listRowSeparatorTint(Color.accentColor.opacity(0.12))
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
        }
        .onDelete { offsets in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                for index in offsets {
                    manager.delete(items[index], in: modelContext)
                }
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
            // Primary CTA: complete basket — tinted accent, prominent
            Button {
                completeCurrentBasket()
            } label: {
                Label(String(localized: "action.complete"), systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color("BrandGreen"))
            .disabled(basketItems.isEmpty || isCompletingBasket)
            .accessibilityLabel(Text("action.complete"))

            // Secondary: share + clear collapsed into a Menu
            Menu {
                if let image = shareImage, !isPreparingShare {
                    let swiftUIImage = Image(uiImage: image)
                    ShareLink(
                        item: swiftUIImage,
                        preview: SharePreview(
                            String(localized: "basket.share.title", defaultValue: "Shopping List"),
                            image: swiftUIImage
                        )
                    ) {
                        Label(String(localized: "action.share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
                    }
                }

                Button(role: .destructive) {
                    manager.clearBasket(basketItems, in: modelContext)
                } label: {
                    Label(String(localized: "action.clear_basket"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
            }
            .menuStyle(.borderlessButton)
            .popoverTip(shareBasketTip)
            .disabled(basketItems.isEmpty || isCompletingBasket)
        }
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

    private func completeCurrentBasket() {
        guard !basketItems.isEmpty, !isCompletingBasket else { return }
        isCompletingBasket = true

        // Show overlay first so its multi-stage animation + haptics begin immediately,
        // then commit the data change. The overlay's own animation arc is ~900ms; we
        // hold it on screen for ~1.6s total so the user reads the "saved" subtitle
        // before it dismisses.
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            showCompletionBadge = true
        }

        manager.completeBasket(basketItems, in: modelContext)

        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.32)) {
                    showCompletionBadge = false
                }
                isCompletingBasket = false
                onCompletion?()
            }
        }
    }


}

#Preview {
    BasketView(manager: BasketManager())
        .modelContainer(PreviewContainer.make())
}
