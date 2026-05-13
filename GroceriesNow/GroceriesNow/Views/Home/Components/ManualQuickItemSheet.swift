import SwiftUI

/// Create-or-edit form for a user-supplied `QuickItem`.
///
/// Built as a `ScrollView`-driven custom form (not a stock `List`) so the
/// hero preview tile, category chip row, and emoji grid can live in one
/// vertical rhythm without each landing inside a separate grouped-list
/// section. Same control set as before — name, emoji, category,
/// optional add-to-basket toggle — just better organised.
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
    @FocusState private var nameFocused: Bool

    init(
        initialName: String,
        initialEmoji: String = "🛒",
        initialCategory: QuickItemCategory = .custom,
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
                VStack(spacing: 18) {
                    previewTile
                    nameSection
                    categorySection
                    emojiSection
                    if showAddToBasketOption {
                        addToBasketSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color("LaunchBackground"))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                if name.isEmpty {
                    nameFocused = true
                }
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

    // MARK: - Live preview tile

    /// Shows the user the exact tile they'll get — emoji bottom-right,
    /// label top-left, same gradient card as the standard tile.
    private var previewTile: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(normalizedEmoji)
                .font(.system(size: 88))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                .padding(.bottom, 8)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("manual_add.preview.label")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text(displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color("CardBackground"),
                            Color.accentColor.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color(.separator).opacity(0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: emoji)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: displayName)
    }

    // MARK: - Name

    private var nameSection: some View {
        sectionCard(titleKey: "manual_add.section.name") {
            TextField(
                String(localized: "manual_add.name_placeholder", defaultValue: "Item name"),
                text: $name
            )
            .focused($nameFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(.body)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color("LaunchBackground"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        sectionCard(titleKey: "manual_add.section.category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickItemCategory.orderedBrowseCategories) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
            .overlay {
                Capsule().stroke(Color.accentColor.opacity(selected ? 0 : 0.25), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Emoji picker

    private var emojiSection: some View {
        sectionCard(titleKey: "manual_add.section.emoji") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                    ForEach(emojiOptions, id: \.self) { option in
                        emojiCell(option)
                    }
                }

                customEmojiField
            }
        }
    }

    /// Free-text emoji input — lets the user paste or type any emoji
    /// the curated grid doesn't include (📿, 🪒, country flags, custom
    /// stickers, …). The binding marks the emoji as deliberately picked
    /// only when the user actually types here; programmatic writes from
    /// the auto-suggest path go straight to `emoji` and don't trip it.
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
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color("LaunchBackground"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
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
                    selected ? Color.accentColor.opacity(0.18) : Color("LaunchBackground"),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            selected ? Color.accentColor : Color(.separator).opacity(0.25),
                            lineWidth: selected ? 1.5 : 0.5
                        )
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add-to-basket toggle

    private var addToBasketSection: some View {
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
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("CardBackground"))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
        }
    }

    // MARK: - Section shell

    /// Card with a small uppercase header above its content. Keeps the
    /// vertical rhythm consistent without leaning on `List`.
    @ViewBuilder
    private func sectionCard<Content: View>(
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color("CardBackground"))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "action.cancel")) { dismiss() }
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

    /// Curated grid of grocery-relevant emojis. Bigger than the previous
    /// 16 so the user is less likely to have to type one in.
    private var emojiOptions: [String] {
        [
            "🛒", "🥛", "🍞", "🥚", "🧀", "🧈", "🥣", "💧", "🧂",
            "🍅", "🥔", "🥕", "🥒", "🥬", "🥦", "🫑", "🧅", "🧄", "🫚",
            "🍄", "🥑", "🍎", "🍌", "🍇", "🍊", "🍋", "🍓", "🫐",
            "🍍", "🥝", "🥥", "🍑", "🍗", "🥩", "🐟", "🥓", "🌭", "🥡",
            "🫘", "🥜", "🍚", "🍝", "🌾", "☕️", "🍵", "🍯",
            "🍫", "🍪", "🍟", "🍿", "🥐", "🥯", "🧇", "🥞", "🍰",
            "🍕", "🍨", "🧃", "🥤", "🍺", "🍷",
            "🧴", "🧺", "🧽", "🗑️", "🧻", "🧼", "🪥"
        ]
    }

    // MARK: - Smart emoji suggestion

    /// Cheap keyword match to suggest an emoji as the user types. Only
    /// applied while the user hasn't deliberately picked one — once
    /// they tap an emoji cell, auto-suggest is silenced.
    static func suggestEmoji(for name: String) -> String? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        for (keyword, em) in keywordMap where lower.contains(keyword) {
            return em
        }
        return nil
    }

    /// Ordered most-specific-first so multi-word matches don't get
    /// shadowed by a shorter keyword. e.g. "peanut butter" must match
    /// before plain "butter".
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
