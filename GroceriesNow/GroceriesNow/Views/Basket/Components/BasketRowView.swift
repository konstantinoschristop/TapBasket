import SwiftUI

/// A single row in the basket list.
///
/// Layout: emoji · name (struck through when checked) + optional note line ·
/// trailing quantity stepper. Tap row toggles checked. Note editing and delete
/// move to the row's context menu and leading-edge swipe action so the row
/// itself stays uncluttered.
struct BasketRowView: View {
    let item: BasketItem
    let onToggleChecked: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onEditNote: () -> Void
    let onSaveForLater: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Brief BrandGreen wash that plays when the user just checked the row off.
    /// Fades out automatically after the animation, leaving the row in its
    /// dimmed/struck-through "checked" state.
    @State private var checkPulse = false

    private var displayName: String {
        ProductDisplayNameProvider.displayName(for: item.name)
    }

    private var hasNote: Bool {
        item.note?.isEmpty == false
    }

    var body: some View {
        HStack(spacing: 12) {
            // Leading completion indicator — empty circle when pending,
            // BrandGreen filled checkmark when done. Makes "tap to mark
            // off" obvious without adding any other chrome to the row.
            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isChecked ? Color("BrandGreen") : Color(.tertiaryLabel))
                .symbolEffect(.bounce, options: .nonRepeating, value: item.isChecked)
                .accessibilityHidden(true)

            Text(item.emoji)
                .font(.title2)
                .scaleEffect(item.isChecked ? 0.92 : 1)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.body)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? Color(.secondaryLabel) : Color(.label))
                        .lineLimit(1)

                    if hasNote {
                        Image(systemName: "note.text")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: item.note)

            Spacer(minLength: 8)

            QuantityStepperView(
                quantity: item.quantity,
                onDecrement: onDecrement,
                onIncrement: onIncrement
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        // BrandGreen wash on tick — the row briefly glows green to reward the
        // check-off, then settles into the dimmed checked state.
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("BrandGreen"))
                .opacity(checkPulse ? 0.18 : 0)
                .padding(.horizontal, -8)
                .animation(.taplistTap, value: checkPulse)
        }
        .opacity(item.isChecked ? 0.55 : 1)
        .animation(.taplistTap, value: item.isChecked)
        .onTapGesture {
            // Only pulse when transitioning UNchecked → checked. Unchecking
            // shouldn't celebrate. Skip the pulse under reduce-motion — the
            // dimmed state + strikethrough already communicate the toggle.
            if !item.isChecked && !reduceMotion {
                checkPulse = true
                Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    await MainActor.run { checkPulse = false }
                }
            }
            onToggleChecked()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isChecked ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(Text(item.isChecked
            ? String(localized: "basket.row.a11y_checked", defaultValue: "Checked")
            : String(localized: "basket.row.a11y_unchecked", defaultValue: "Not checked")))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onEditNote() } label: {
                Label(hasNote
                      ? String(localized: "basket.row.edit_note", defaultValue: "Edit note")
                      : String(localized: "basket.row.add_note", defaultValue: "Add note"),
                      systemImage: "note.text")
            }
            .tint(Color.accentColor)
        }
        // Trailing edge carries the two "I'm done with this row in
        // its current state" actions. Delete is declared first so
        // it's the full-swipe target (matches iOS Mail / Reminders
        // conventions — destructive on full swipe). Save sits to
        // the left of Delete on a partial swipe.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "action.delete", defaultValue: "Delete"),
                      systemImage: "trash")
            }

            Button {
                onSaveForLater()
            } label: {
                Label(String(localized: "basket.row.save_for_later",
                             defaultValue: "Save"),
                      systemImage: "bookmark")
            }
            .tint(Color.accentColor)
        }
        .contextMenu {
            Button { onEditNote() } label: {
                Label(hasNote
                      ? String(localized: "basket.row.edit_note", defaultValue: "Edit note")
                      : String(localized: "basket.row.add_note", defaultValue: "Add note"),
                      systemImage: "note.text")
            }
            Button { onToggleChecked() } label: {
                Label(item.isChecked
                      ? String(localized: "basket.row.uncheck", defaultValue: "Uncheck")
                      : String(localized: "basket.row.mark_checked", defaultValue: "Mark checked"),
                      systemImage: item.isChecked ? "circle" : "checkmark.circle")
            }
            Button { onSaveForLater() } label: {
                Label(String(localized: "basket.row.save_for_later",
                             defaultValue: "Save for later"),
                      systemImage: "bookmark")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label(String(localized: "action.delete", defaultValue: "Delete"),
                      systemImage: "trash")
            }
        }
    }
}
