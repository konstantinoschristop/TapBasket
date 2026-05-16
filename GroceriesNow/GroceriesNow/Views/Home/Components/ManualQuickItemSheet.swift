import SwiftUI

/// Create-or-edit form for a user-supplied `QuickItem`.
///
/// Built as a `ScrollView`-driven custom form (not a stock `List`) so
/// the live preview tile, category chip row and emoji grid share one
/// vertical rhythm. Visual language matches the home grid: flat warm
/// `CardBackground` fill, hairline borders, olive accent — no
/// gradients, no boxed-in section cards, no enterprise chrome.
struct ManualQuickItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    let initialEmoji: String
    let initialCategory: QuickItemCategory
    let showAddToBasketOption: Bool
    let title: String
    let onSave: (_ name: String, _ emoji: String, _ category: QuickItemCategory, _ addToBasket: Bool) -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var category: QuickItemCategory
    @State private var addToBasket: Bool
    /// Tracks whether the user has manually picked an emoji; once true,
    /// we stop auto-suggesting based on the name so we don't override
    /// their deliberate choice.
    @State private var emojiManuallyPicked: Bool = false
    /// When `false`, the emoji grid is capped at a starter set so the
    /// sheet stays compact. The user expands to the full curated list
    /// via the "Show more" affordance.
    @State private var showAllEmojis: Bool = false
    @FocusState private var nameFocused: Bool

    init(
        initialName: String,
        initialEmoji: String = "🛒",
        // Default to `.pantry` — the broadest shelf-stable bucket and
        // the most useful catch-all when the user hasn't given us a
        // signal. `.custom` is no longer a default landing spot;
        // manually-added items now file under a real category alongside
        // catalog-driven additions.
        initialCategory: QuickItemCategory = .pantry,
        showAddToBasketOption: Bool = true,
        title: String = String(localized: "manual_add.title.new", defaultValue: "New Product"),
        onSave: @escaping (_ name: String, _ emoji: String, _ category: QuickItemCategory, _ addToBasket: Bool) -> Void
    ) {
        self.initialName = initialName
        self.initialEmoji = initialEmoji
        self.initialCategory = initialCategory
        self.showAddToBasketOption = showAddToBasketOption
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _emoji = State(initialValue: initialEmoji)
        _category = State(initialValue: initialCategory)
        _addToBasket = State(initialValue: showAddToBasketOption)
        _emojiManuallyPicked = State(initialValue: initialEmoji != "🛒")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    previewTile
                    nameSection
                    if suggestionsEnabled && !catalogMatches.isEmpty {
                        suggestionsSection
                    }
                    categorySection
                    emojiSection
                    if showAddToBasketOption {
                        addToBasketRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color("LaunchBackground"))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                if name.isEmpty { nameFocused = true }
            }
            .onChange(of: name) { _, newValue in
                guard !emojiManuallyPicked else { return }
                if let suggested = Self.suggestEmoji(for: newValue) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        emoji = suggested
                    }
                }
            }
        }
    }

    // MARK: - Inline catalog suggestions

    /// Catalog autocompletes are shown only when the sheet was opened
    /// without an initial name — i.e. the user tapped the My Items "+"
    /// cell, not "Create X" from the search results. When they came
    /// from search, they've already seen and bypassed catalog
    /// suggestions for that query; surfacing them again would feel
    /// redundant. Stateless because it depends only on the init input.
    private var suggestionsEnabled: Bool {
        initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Up to 4 ranked catalog matches for what the user is currently
    /// typing. Returns `[]` when the field is too short for the catalog
    /// to be useful (the threshold lives inside `ProductCatalog`).
    private var catalogMatches: [Product] {
        ProductCatalog.shared.suggestions(for: trimmedName, limit: 4)
    }

    /// Inline matches under the name field. Tapping a suggestion
    /// commits it immediately with the catalog's emoji + category —
    /// same one-tap directness as the search-results flow.
    private var suggestionsSection: some View {
        section(titleKey: "manual_add.section.suggestions") {
            VStack(spacing: 6) {
                ForEach(catalogMatches) { product in
                    suggestionRow(product)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85),
                       value: catalogMatches.map(\.id))
        }
    }

    private func suggestionRow(_ product: Product) -> some View {
        Button {
            acceptSuggestion(product)
        } label: {
            HStack(spacing: 12) {
                Text(product.emoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color("CardBackground"), in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(suggestedCategory(for: product).title)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.10), in: Circle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Commits a catalog suggestion directly: hands the canonical
    /// name + emoji + category to the parent's `onSave` and closes
    /// the sheet. The user's current `addToBasket` toggle is honoured
    /// — opening the sheet still defaults that to on, so the typical
    /// "add this thing" path stays one tap.
    private func acceptSuggestion(_ product: Product) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSave(product.name, product.emoji, suggestedCategory(for: product), addToBasket)
        dismiss()
    }

    /// Resolve the catalog's category string back into a
    /// `QuickItemCategory`, falling back to `.custom` if the JSON ever
    /// drifts ahead of the enum.
    private func suggestedCategory(for product: Product) -> QuickItemCategory {
        QuickItemCategory(rawValue: product.category) ?? .custom
    }

    // MARK: - Live preview tile

    /// Real-time preview that mirrors the exact look of a `QuickItemTile`
    /// on the home grid: flat warm `CardBackground` fill, hairline
    /// border, sticker-shadow emoji bottom-right, name top-left.
    /// What you see here is what you get.
    private var previewTile: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(normalizedEmoji)
                .font(.system(size: 88))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                .padding(.bottom, 6)
                .padding(.trailing, 8)

            Text(displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: emoji)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: displayName)
    }

    // MARK: - Sections (inline, no card wrappers)

    private var nameSection: some View {
        section(titleKey: "manual_add.section.name") {
            TextField(
                String(localized: "manual_add.name_placeholder", defaultValue: "Item name"),
                text: $name
            )
            .focused($nameFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(.body)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
            }
        }
    }

    private var categorySection: some View {
        section(titleKey: "manual_add.section.category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pickerCategories) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(.vertical, 2)
            }
            // Negative outer padding so the chip row can bleed to the
            // sheet's full content width; the inner HStack provides the
            // edge inset to align with other sections.
            .padding(.horizontal, -20)
            .safeAreaPadding(.horizontal, 20)
        }
    }

    /// Picker categories — the standard browse order without `.custom`.
    /// Items the user creates manually now land in a real category
    /// (essentials, produce, pantry, etc.) just like catalog-driven
    /// additions do, so the home screen doesn't need a dedicated
    /// "My Items" bucket. If the user is editing an existing item that
    /// was filed as `.custom` before this rule, we make sure that
    /// option is still visible (last) so they can pick a new home
    /// without being silently blocked from saving.
    private var pickerCategories: [QuickItemCategory] {
        let standard = QuickItemCategory.orderedBrowseCategories.filter { $0 != .custom }
        return category == .custom ? standard + [.custom] : standard
    }

    private func categoryChip(_ cat: QuickItemCategory) -> some View {
        let selected = (cat == category)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                category = cat
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                Text(cat.title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color(.systemBackground) : Color.accentColor)
            .background {
                Capsule().fill(selected ? Color.accentColor : Color.accentColor.opacity(0.12))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Emoji picker

    private var emojiSection: some View {
        section(titleKey: "manual_add.section.emoji") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                    ForEach(visibleEmojiOptions, id: \.self) { option in
                        emojiCell(option)
                    }
                }

                if fullEmojiOptions.count > starterEmojiCount {
                    showMoreEmojisButton
                }

                customEmojiField
            }
        }
    }

    /// Small inline "Show more / Show less" toggle for the emoji
    /// grid — keeps the default sheet height tight while still
    /// surfacing the full curated set on demand.
    private var showMoreEmojisButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showAllEmojis.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(showAllEmojis
                     ? String(localized: "manual_add.emoji.show_less", defaultValue: "Show less")
                     : String(localized: "manual_add.emoji.show_more", defaultValue: "Show more"))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: showAllEmojis ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emojiCell(_ option: String) -> some View {
        let selected = (option == emoji)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                emoji = option
                emojiManuallyPicked = true
            }
        } label: {
            Text(option)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? Color.accentColor.opacity(0.15) : Color("CardBackground"),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selected ? Color.accentColor : Color(.separator).opacity(0.25),
                            lineWidth: selected ? 1.5 : 0.5
                        )
                }
        }
        .buttonStyle(.plain)
    }

    /// Free-text emoji input — paste or type any emoji the curated
    /// grid doesn't include. Wrapping the binding in a custom one
    /// means only direct user input here marks the emoji as
    /// "manually picked"; auto-suggest writes still flow through.
    private var customEmojiField: some View {
        let userInput = Binding<String>(
            get: { emoji },
            set: { newValue in
                emoji = newValue
                emojiManuallyPicked = true
            }
        )

        return HStack(spacing: 10) {
            Text(normalizedEmoji)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.10), in: Circle())

            TextField(
                String(localized: "manual_add.custom_emoji.placeholder", defaultValue: "Type or paste any emoji"),
                text: userInput
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
            }
        }
    }

    // MARK: - Add-to-basket toggle

    private var addToBasketRow: some View {
        Toggle(isOn: $addToBasket) {
            VStack(alignment: .leading, spacing: 2) {
                Text("manual_add.add_to_basket")
                    .font(.subheadline.weight(.semibold))
                Text("manual_add.add_to_basket.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(Color("BrandGreen"))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.30), lineWidth: 0.5)
        }
    }

    // MARK: - Section shell (inline title + content)

    /// Lightweight section: small uppercase caption then inline
    /// content. No outer card chrome — the sheet is the container.
    @ViewBuilder
    private func section<Content: View>(
        titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleKey)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, 4)

            content()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel(Text("action.cancel"))
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "action.save")) {
                onSave(trimmedName, normalizedEmoji, category, addToBasket)
                dismiss()
            }
            .fontWeight(.semibold)
            .disabled(trimmedName.isEmpty)
        }
    }

    // MARK: - Derived values

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayName: String {
        let trimmed = trimmedName
        if trimmed.isEmpty {
            return String(localized: "manual_add.preview.name_placeholder", defaultValue: "Your item")
        }
        return trimmed.capitalized
    }

    private var normalizedEmoji: String {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmoji.isEmpty ? "🛒" : String(trimmedEmoji.prefix(2))
    }

    /// Default number of emojis shown in the compact grid. The user
    /// can expand to the full list via "Show more".
    private let starterEmojiCount = 21

    /// What actually renders in the grid — starter set by default,
    /// full set when the user has tapped "Show more". If the user has
    /// picked an emoji that isn't in the starter set, surface it too
    /// so the selection isn't hidden behind the toggle.
    private var visibleEmojiOptions: [String] {
        if showAllEmojis { return fullEmojiOptions }
        let starter = Array(fullEmojiOptions.prefix(starterEmojiCount))
        if starter.contains(emoji) { return starter }
        // Selected emoji isn't in the starter set — append it so the
        // user always sees their current pick.
        return fullEmojiOptions.contains(emoji) ? starter + [emoji] : starter
    }

    /// Curated grocery-relevant emoji set. The first 21 are the
    /// "starter" subset that satisfies the vast majority of adds; the
    /// rest are revealed by "Show more".
    private var fullEmojiOptions: [String] {
        [
            // Starter set (first 21) — one of each major group.
            "🛒", "🥛", "🍞", "🥚", "🧀", "🧈", "🥣",
            "🍅", "🥔", "🥕", "🥬", "🧅", "🍄", "🥑",
            "🍎", "🍌", "🍗", "🥩", "🐟", "🍝", "☕️",
            // Full set continues —
            "💧", "🧂", "🥒", "🥦", "🫑", "🧄", "🫚",
            "🍇", "🍊", "🍋", "🍓", "🫐", "🍍", "🥝", "🥥", "🍑",
            "🥓", "🌭", "🥡", "🫘", "🥜",
            "🍚", "🌾", "🍵", "🍯", "🍫", "🍪", "🍟", "🍿",
            "🥐", "🥯", "🧇", "🥞", "🍰", "🍕", "🍨",
            "🧃", "🥤", "🍺", "🍷",
            "🧴", "🧺", "🧽", "🗑️", "🧻", "🧼", "🪥"
        ]
    }

    // MARK: - Smart emoji suggestion

    /// Cheap keyword match to suggest an emoji as the user types. Only
    /// fires while the user hasn't deliberately picked one — tapping
    /// a cell or typing in the free-text input silences it.
    static func suggestEmoji(for name: String) -> String? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        for (keyword, em) in keywordMap where lower.contains(keyword) {
            return em
        }
        return nil
    }

    /// Ordered most-specific-first so multi-word matches don't get
    /// shadowed by a shorter keyword. e.g. "peanut butter" must
    /// match before plain "butter".
    private static let keywordMap: [(String, String)] = [
        ("peanut butter", "🥜"), ("almond milk", "🥛"), ("oat milk", "🥛"),
        ("cherry tomato", "🍅"), ("sweet potato", "🥔"), ("ice cream", "🍨"),
        ("olive oil", "🫒"), ("soy sauce", "🍶"), ("tomato sauce", "🍅"),
        ("paper towel", "🧻"), ("toilet paper", "🧻"), ("dish soap", "🧴"),
        ("hand soap", "🧼"), ("toothpaste", "🪥"),
        ("milk", "🥛"), ("bread", "🍞"), ("egg", "🥚"), ("cheese", "🧀"),
        ("butter", "🧈"), ("yogurt", "🥣"), ("water", "💧"), ("salt", "🧂"),
        ("oil", "🫒"), ("tomato", "🍅"), ("potato", "🥔"), ("carrot", "🥕"),
        ("cucumber", "🥒"), ("lettuce", "🥬"), ("spinach", "🥬"),
        ("broccoli", "🥦"), ("pepper", "🫑"), ("onion", "🧅"),
        ("garlic", "🧄"), ("ginger", "🫚"), ("mushroom", "🍄"),
        ("avocado", "🥑"), ("apple", "🍎"), ("banana", "🍌"),
        ("grape", "🍇"), ("orange", "🍊"), ("lemon", "🍋"),
        ("strawberr", "🍓"), ("blueberr", "🫐"), ("raspberr", "🫐"),
        ("pineapple", "🍍"), ("kiwi", "🥝"), ("coconut", "🥥"),
        ("peach", "🍑"), ("watermelon", "🍉"), ("melon", "🍈"),
        ("chicken", "🍗"), ("steak", "🥩"), ("meat", "🥩"),
        ("salmon", "🐟"), ("tuna", "🐟"), ("fish", "🐟"),
        ("bacon", "🥓"), ("sausage", "🌭"), ("ham", "🥓"),
        ("tofu", "🥡"), ("bean", "🫘"), ("lentil", "🫘"),
        ("nut", "🥜"), ("almond", "🥜"), ("walnut", "🥜"),
        ("rice", "🍚"), ("pasta", "🍝"), ("flour", "🌾"),
        ("sugar", "🍚"), ("oat", "🥣"), ("coffee", "☕️"),
        ("tea", "🍵"), ("cereal", "🥣"), ("biscuit", "🍪"),
        ("cookie", "🍪"), ("honey", "🍯"), ("jam", "🍓"),
        ("ketchup", "🍅"), ("mayo", "🥚"), ("mustard", "🌭"),
        ("vinegar", "🫙"), ("frozen", "🧊"), ("pizza", "🍕"),
        ("juice", "🧃"), ("soda", "🥤"), ("water", "💧"),
        ("beer", "🍺"), ("wine", "🍷"), ("chocolate", "🍫"),
        ("chip", "🍟"), ("popcorn", "🍿"), ("croissant", "🥐"),
        ("bagel", "🥯"), ("waffle", "🧇"), ("pancake", "🥞"),
        ("cake", "🍰"), ("doughnut", "🍩"), ("donut", "🍩"),
        ("pie", "🥧"), ("soap", "🧼"), ("detergent", "🧺"),
        ("sponge", "🧽"), ("trash", "🗑️"), ("tissue", "🧻"),
        ("shampoo", "🧴")
    ]
}

extension QuickItemCategory: Identifiable {
    var id: String { rawValue }
}
