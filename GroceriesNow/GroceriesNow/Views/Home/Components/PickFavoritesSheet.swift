import SwiftUI

/// Lightweight bulk-pin sheet reached from the empty-state "+" in the
/// Regulars row. Lists every `QuickItem` with a one-tap pin toggle and
/// a system search field.
///
/// Deliberately a flat `List` with a single interaction (tap row →
/// toggle pin). No multi-step flow, no edit mode, no settings vibe.
struct PickFavoritesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [QuickItem]
    /// Toggles `item.pinned`. The host is responsible for persisting.
    let onTogglePin: (QuickItem) -> Void

    @State private var search: String = ""

    /// Dedup pass — two `QuickItem` rows whose names canonicalise to
    /// the same product (e.g. "Egg" + "Eggs", both → `product.eggs`)
    /// would render as visually-identical rows. Collapse them, keeping
    /// the pinned one when there's a tie so the user's explicit
    /// choice survives. The underlying SwiftData rows are not deleted
    /// here — that's the seed-migration's job — this is presentation
    /// defence in case migration hasn't run for some user's data yet.
    private var dedupedItems: [QuickItem] {
        var seen: Set<String> = []
        var result: [QuickItem] = []
        result.reserveCapacity(items.count)
        // Sort so pinned items win the dedup race; ties fall back to
        // existing array order.
        let ordered = items.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return false
        }
        for item in ordered {
            let key = ProductDisplayNameProvider.canonicalKey(for: item.name)
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        // Restore the original sort order (sortOrder asc) so the
        // picker scrolls in the user's expected sequence.
        return result.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var filtered: [QuickItem] {
        let pool = dedupedItems
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pool }
        return pool.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmed)
                || item.emoji.contains(trimmed)
        }
    }

    private var pinnedCount: Int {
        items.filter(\.pinned).count
    }

    var body: some View {
        NavigationStack {
            List {
                if pinnedCount == 0 && search.isEmpty {
                    Section {
                        Text("favorites_picker.hint")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Section {
                    ForEach(filtered) { item in
                        row(for: item)
                    }
                } header: {
                    if !search.isEmpty {
                        Text(String(
                            format: String(localized: "favorites_picker.results_count",
                                           defaultValue: "%lld matches"),
                            filtered.count
                        ))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color("LaunchBackground"))
            .searchable(
                text: $search,
                prompt: Text("favorites_picker.search_prompt")
            )
            .navigationTitle("favorites_picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "action.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func row(for item: QuickItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                onTogglePin(item)
            }
        } label: {
            HStack(spacing: 14) {
                Text(item.emoji)
                    .font(.title2)
                    .frame(width: 32)

                Text(ProductDisplayNameProvider.displayName(for: item.name))
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: item.pinned ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.pinned ? Color.accentColor : Color(.tertiaryLabel))
                    .symbolEffect(.bounce, options: .nonRepeating, value: item.pinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
