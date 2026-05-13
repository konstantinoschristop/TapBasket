import SwiftUI

/// One-line capsule that briefly surfaces after the user adds an item:
///
///     "🥖 Bread added · + 🥛 Milk"
///
/// The right-hand side is tappable — tap to add the suggestion to the
/// basket. Auto-dismisses after a short window. Replaces the heavier
/// "bought-together" widgets with a single, calm interaction.
///
/// Design intent: never modal, never blocks, never demands attention.
/// If it isn't acted on inside ~2.5s, it slides away.
struct InlineSuggestionPill: View {
    let addedEmoji: String
    let addedName: String
    /// The suggested item — `nil` means no recommendation, in which
    /// case the pill renders only the confirmation half.
    let suggestionEmoji: String?
    let suggestionName: String?
    let onTapSuggestion: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Confirmation chunk on the left.
            HStack(spacing: 6) {
                Text(addedEmoji).font(.body)
                Text(addedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color("BrandGreen"))
            }
            .padding(.leading, 14)
            .padding(.vertical, 10)

            // Suggestion chunk on the right — only rendered if a
            // recommendation came back from the engine.
            if let emoji = suggestionEmoji, let name = suggestionName {
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: 0.5, height: 22)
                    .padding(.horizontal, 12)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTapSuggestion()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text(emoji).font(.body)
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer(minLength: 14)
            }
        }
        .background {
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("inline_suggestion.a11y_dismiss")) { onDismiss() }
    }
}
