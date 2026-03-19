import SwiftUI

struct ManualQuickItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    let onSave: (_ name: String, _ emoji: String, _ category: QuickItemCategory, _ addToBasket: Bool) -> Void

    @State private var name: String
    @State private var emoji: String = "🛒"
    @State private var category: QuickItemCategory = .custom
    @State private var addToBasket = true

    init(
        initialName: String,
        onSave: @escaping (_ name: String, _ emoji: String, _ category: QuickItemCategory, _ addToBasket: Bool) -> Void
    ) {
        self.initialName = initialName
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                productFields
                categoryPicker
                basketOption
                emojiSuggestions
            }
            .navigationTitle("New Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    private var productFields: some View {
        Section("Product") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            TextField("Emoji", text: $emoji)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var categoryPicker: some View {
        Section("Category") {
            Picker("Category", selection: $category) {
                ForEach(QuickItemCategory.orderedBrowseCategories) { category in
                    Text(category.title)
                        .tag(category)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var basketOption: some View {
        Section {
            Toggle("Add to basket now", isOn: $addToBasket)
        }
    }

    private var emojiSuggestions: some View {
        Section("Quick emoji") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(emojiOptions, id: \.self) { option in
                    Button {
                        emoji = option
                    } label: {
                        Text(option)
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(emoji == option ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                onSave(trimmedName, normalizedEmoji, category, addToBasket)
                dismiss()
            }
            .disabled(trimmedName.isEmpty)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmoji: String {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmoji.isEmpty ? "🛒" : String(trimmedEmoji.prefix(2))
    }

    private var emojiOptions: [String] {
        ["🛒", "🥛", "🍞", "🥚", "🧀", "🥬", "🍎", "🍌", "🍅", "🥔", "🍗", "🍚", "🍝", "☕️", "🍺", "🍪"]
    }
}

extension QuickItemCategory: Identifiable {
    var id: String { rawValue }
}
