import SwiftUI

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct RecipeBasketSheet: View {
    @Environment(\.dismiss) private var dismiss

    let quickItems: [QuickItem]
    let onAdd: (_ recipeName: String, _ ingredients: [RecipeIngredient]) -> Void

    @State private var service = RecipeBasketService()
    @State private var recipeText = ""
    @State private var resolvedIngredients: [RecipeIngredient] = []
    @State private var selectedNames: Set<String> = []
    @State private var recentRecipes: [String] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                recipeInputSection

                // Recent recipes — shown only when idle with empty text field
                if !recentRecipes.isEmpty && recipeText.trimmingCharacters(in: .whitespaces).isEmpty
                    && !service.isLoading && !service.hasSearched {
                    recentSection
                }

                // Spinner only when loading with nothing to show yet
                if service.isLoading && resolvedIngredients.isEmpty {
                    loadingRow
                }

                // Ingredients appear as they stream in
                if !resolvedIngredients.isEmpty {
                    ingredientsSection
                }

                // Post-generation states
                if !service.isLoading {
                    if let error = service.errorMessage {
                        errorRow(error)
                    } else if service.isInvalidDish {
                        notARecipeRow
                    } else if service.hasSearched && resolvedIngredients.isEmpty {
                        emptyRow
                    }
                }
            }
            .navigationTitle(String(localized: "recipe.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if !resolvedIngredients.isEmpty {
                    addButton
                }
            }
            // Text field cleared — reset to initial state
            .onChange(of: recipeText) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    service.cancel()
                    resolvedIngredients = []
                    selectedNames = []
                    service.reset()
                }
            }
            // New generation starting — reset everything
            .onChange(of: service.isLoading) { _, loading in
                if loading {
                    resolvedIngredients = []
                    selectedNames = []
                }
            }
            // Don't save invalid dish queries to history
            .onChange(of: service.isInvalidDish) { _, invalid in
                if invalid {
                    // clear any streamed-in state so nothing leaks through
                    resolvedIngredients = []
                    selectedNames = []
                }
            }
            // Streaming update — add new arrivals to selection, preserve deselections
            .onChange(of: service.ingredients) { _, new in
                let previousNames = Set(resolvedIngredients.map { $0.name.lowercased() })
                let resolved = new.map { resolve($0) }
                let newOnes = resolved.filter { !previousNames.contains($0.name.lowercased()) }
                resolvedIngredients = resolved
                for ingredient in newOnes {
                    selectedNames.insert(ingredient.name.lowercased())
                }
            }
        }
        .onAppear {
            isInputFocused = true
            recentRecipes = RecipeHistory.all
        }
        .onChange(of: service.hasSearched) { _, searched in
            // Save to history after a successful generation
            if searched && !service.ingredients.isEmpty {
                let trimmed = recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
                RecipeHistory.save(trimmed)
                recentRecipes = RecipeHistory.all
            }
        }
        .onDisappear { service.cancel() }
    }

    // MARK: - Name resolution

    /// Matches an AI-suggested ingredient against the user's existing quick items.
    /// Prefers an existing item if its name appears within the AI name, or vice-versa
    /// (e.g. "kalamata olives" → "olives", "feta cheese" → "feta").
    private func resolve(_ ingredient: RecipeIngredient) -> RecipeIngredient {
        let aiName = ingredient.name.lowercased()
        guard let match = quickItems.first(where: {
            let qn = $0.name.lowercased()
            return aiName.contains(qn) || qn.contains(aiName)
        }) else { return ingredient }
        return RecipeIngredient(name: match.name, emoji: match.emoji, quantity: ingredient.quantity)
    }

    // MARK: - Sections

    private var recipeInputSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField(String(localized: "recipe.sheet.input_placeholder"), text: $recipeText)
                    .autocorrectionDisabled()
                    .focused($isInputFocused)
                    .onSubmit { generate() }

                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Button(action: generate) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(recipeText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.secondary
                                : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(recipeText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } footer: {
            if !service.isAvailable {
                Text(String(localized: "recipe.sheet.ai_unavailable"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingRow: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "recipe.sheet.loading"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(resolvedIngredients) { ingredient in
                ingredientRow(ingredient)
            }
        } header: {
            HStack(spacing: 6) {
                Text("\(resolvedIngredients.count) ingredients")
                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.55)
                }
                Spacer()
                let allSelected = selectedNames.count == resolvedIngredients.count
                Button(allSelected
                    ? String(localized: "recipe.sheet.deselect_all")
                    : String(localized: "recipe.sheet.select_all")
                ) {
                    if allSelected {
                        selectedNames.removeAll()
                    } else {
                        selectedNames = Set(resolvedIngredients.map { $0.name.lowercased() })
                    }
                }
                .font(.caption)
                .textCase(nil)
            }
        }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        let isSelected = selectedNames.contains(ingredient.name.lowercased())
        return Button {
            if isSelected {
                selectedNames.remove(ingredient.name.lowercased())
            } else {
                selectedNames.insert(ingredient.name.lowercased())
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                Text(ingredient.emoji)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ProductDisplayNameProvider.displayName(for: ingredient.name))
                        .foregroundStyle(.primary)
                    if ingredient.quantity > 1 {
                        Text("×\(ingredient.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        Section(String(localized: "recipe.sheet.recent")) {
            ForEach(recentRecipes, id: \.self) { recipe in
                Button {
                    recipeText = recipe
                    generate()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        Text(recipe)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .foregroundStyle(.tertiary)
                            .imageScale(.small)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    RecipeHistory.remove(recentRecipes[index])
                }
                recentRecipes = RecipeHistory.all
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notARecipeRow: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife.slash")
                        .foregroundStyle(.orange)
                    Text(String(localized: "recipe.sheet.not_a_recipe"))
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                }
                Text(String(localized: "recipe.sheet.not_a_recipe_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyRow: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(String(localized: "recipe.sheet.empty"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        let count = selectedNames.count
        let label: String = {
            if count == 0 {
                return String(localized: "recipe.sheet.add_disabled")
            } else if count == 1 {
                return String(localized: "recipe.sheet.add_one_item")
            } else {
                return String(format: String(localized: "recipe.sheet.add_items_format"), count)
            }
        }()
        return Button {
            let selected = resolvedIngredients.filter { selectedNames.contains($0.name.lowercased()) }
            onAdd(recipeText.trimmingCharacters(in: .whitespacesAndNewlines), selected)
            dismiss()
        } label: {
            Text(label)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    count == 0 ? Color.secondary.opacity(0.2) : Color.accentColor,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                // Color(.systemBackground) inverts with the accent (charcoal in
                // light, white in dark) so the label always reads.
                .foregroundStyle(count == 0 ? Color.secondary : Color(.systemBackground))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "action.cancel")) {
                service.cancel()
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func generate() {
        let trimmed = recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !service.isLoading else { return }
        isInputFocused = false
        service.suggest(for: trimmed)
    }
}
#endif
