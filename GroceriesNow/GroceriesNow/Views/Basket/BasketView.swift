import SwiftUI
import SwiftData
import TipKit

struct BasketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\BasketItem.name, order: .forward)]) private var basketItems: [BasketItem]
    /// Saved-for-later pool. Most recently saved first — newest
    /// reminders rise to the top of the section.
    @Query(sort: [SortDescriptor(\SavedForLaterItem.savedAt, order: .reverse)]) private var savedForLaterItems: [SavedForLaterItem]

    let manager: BasketManager
    /// Fired once the completion overlay has finished playing. Parent uses this
    /// to surface a brief post-completion confirmation on the home screen.
    var onCompletion: (() -> Void)? = nil

    @State private var noteEditorItem: BasketItem?
    @State private var isCompletingBasket = false
    @State private var showCompletionBadge = false
    @State private var isPreparingShare = false
    @State private var shareImage: UIImage?

    /// Optional nickname for the *current* basket. Carries through to
    /// the `CompletedBasket.customName` on completion and clears so the
    /// next shop starts fresh. Persists across launches in case the
    /// user names a shop early and adds items over multiple sessions.
    @AppStorage("currentBasketName") private var currentBasketName: String = ""
    @State private var isRenamingBasket: Bool = false
    @State private var basketNameDraft: String = ""

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
        listContent
            // Set a navigation title for accessibility / large-title
            // fallback, but visually it's replaced by the principal
            // toolbar item below so the user can tap-to-rename.
            .navigationTitle(Text(displayedBasketTitle))
            .navigationBarTitleDisplayMode(.inline)
            // Hide the system back button — the leading "Done" button handles dismissal.
            .navigationBarBackButtonHidden(true)
            .alert(
                String(localized: "basket.rename_alert.title", defaultValue: "Name this shop"),
                isPresented: $isRenamingBasket
            ) {
                TextField(
                    String(localized: "basket.rename_alert.placeholder",
                           defaultValue: "e.g. Sunday shop"),
                    text: $basketNameDraft
                )
                .textInputAutocapitalization(.words)
                Button(String(localized: "action.cancel"), role: .cancel) { }
                Button(String(localized: "action.save")) {
                    currentBasketName = basketNameDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
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
            .task(id: basketItems.count) {
                // Defer the image render until after the zoom transition settles —
                // starting it immediately competes for CPU/GPU time mid-animation.
                try? await Task.sleep(for: .milliseconds(400))
                await prepareShareImage()
            }
            .overlay {
                if showCompletionBadge {
                    BasketCompletionOverlay()
                        // Fade-only on the wrapper so the dim backdrop
                        // doesn't scale-up to fullscreen. The popup card
                        // itself springs in via its own internal state
                        // animation.
                        .transition(.opacity)
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
            // One-shot per session: drop saved items older than 14
            // days so the section can't accumulate stale memory.
            manager.purgeExpiredSaved(in: modelContext)
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

        // Saved-for-later — quiet section below the live basket. Lets
        // the user park "changed my mind, but maybe next time" items
        // without losing them. Auto-expires after 14 days via the
        // launch-time purge in `BasketManager`.
        if !savedForLaterItems.isEmpty {
            Section {
                ForEach(savedForLaterItems) { saved in
                    savedForLaterRow(saved)
                        .listRowBackground(Color("CardBackground"))
                        .listRowSeparatorTint(Color.accentColor.opacity(0.12))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                }
            } header: {
                savedForLaterHeader(itemCount: savedForLaterItems.count)
            }
        }

        // Inline banner — sits at the natural end of the list so it
        // never overlays an item. The user scrolls past their basket
        // contents to reveal the ad.
        if !AdsConfiguration.hideForScreenshots && !basketItems.isEmpty {
            Section {
                InlineBannerSection()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// Quiet header for the "Saved for later" section — same
    /// silhouette as the recipe header (small accent glyph + title +
    /// count) so the section reads as a peer rather than an
    /// attention-seeking secondary surface.
    private func savedForLaterHeader(itemCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bookmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(String(localized: "basket.saved.header.title",
                        defaultValue: "Saved for later"))
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

    /// Row inside the saved section. Tap to restore. Leading tint
    /// stays neutral — this isn't a primary surface, just a quiet
    /// memory. Trailing swipe forgets the item permanently.
    private func savedForLaterRow(_ saved: SavedForLaterItem) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                manager.restoreSaved(saved, in: modelContext, basketItems: basketItems)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Text(saved.emoji)
                    .font(.title3)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductDisplayNameProvider.displayName(for: saved.name))
                        .font(.body)
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)

                    Text(savedCaption(for: saved))
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.uturn.backward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(
            String(localized: "basket.saved.row.a11y_restore_format",
                   defaultValue: "Restore \(ProductDisplayNameProvider.displayName(for: saved.name)) to basket")
        ))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    manager.deleteSaved(saved, in: modelContext)
                }
            } label: {
                Label(String(localized: "basket.saved.row.forget",
                             defaultValue: "Forget"),
                      systemImage: "trash")
            }
        }
    }

    /// "Saved 2 days ago · was ×3" / "Saved today" — the quantity
    /// suffix is suppressed when it'd just say "×1" (the common case),
    /// so the caption stays short by default.
    private func savedCaption(for saved: SavedForLaterItem) -> String {
        let relative = saved.savedAt.formatted(
            .relative(presentation: .named, unitsStyle: .wide)
        )
        let head = String(
            localized: "basket.saved.row.timestamp_format",
            defaultValue: "Saved \(relative)"
        )
        guard saved.quantity > 1 else { return head }
        return String(
            localized: "basket.saved.row.timestamp_qty_format",
            defaultValue: "\(head) · was ×\(saved.quantity)"
        )
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
                onEditNote: { noteEditorItem = item },
                onSaveForLater: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        manager.saveForLater(item, in: modelContext)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                },
                onDelete: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        manager.delete(item, in: modelContext)
                    }
                }
            )
            .listRowBackground(Color("CardBackground"))
            .listRowSeparatorTint(Color.accentColor.opacity(0.12))
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Tappable title with inline pencil — opens the rename alert.
        // Replaces the default navigation title.
        ToolbarItem(placement: .principal) {
            Button {
                basketNameDraft = currentBasketName
                isRenamingBasket = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayedBasketTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("basket.rename_alert.title"))
        }

        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel(Text("action.done"))
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

        let trimmedName = currentBasketName.trimmingCharacters(in: .whitespacesAndNewlines)
        shareImage = BasketExporter.renderImage(
            basketName: trimmedName.isEmpty ? nil : trimmedName,
            regularItems: regular,
            recipeGroups: groups
        )
        isPreparingShare = false
    }

    /// Custom name if the user has set one, falling back to the
    /// default "Basket" localized title.
    private var displayedBasketTitle: String {
        let trimmed = currentBasketName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "basket.screen_title")
            : trimmed
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

        manager.completeBasket(
            basketItems,
            customName: currentBasketName,
            in: modelContext
        )

        // Reset the per-basket nickname so the next shop starts blank.
        currentBasketName = ""

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
