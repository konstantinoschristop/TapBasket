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
            Text(item.emoji)
                .font(.title2)
                .scaleEffect(item.isChecked ? 0.92 : 1)
                .frame(width: 30)

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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onEditNote() } label: {
                Label(hasNote ? "Edit note" : "Add note", systemImage: "note.text")
            }
            .tint(Color.accentColor)
        }
        .contextMenu {
            Button { onEditNote() } label: {
                Label(hasNote ? "Edit note" : "Add note", systemImage: "note.text")
            }
            Button { onToggleChecked() } label: {
                Label(item.isChecked ? "Uncheck" : "Mark checked",
                      systemImage: item.isChecked ? "circle" : "checkmark.circle")
            }
        }
    }
}
