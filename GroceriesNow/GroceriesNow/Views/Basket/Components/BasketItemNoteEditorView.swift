import SwiftUI

struct BasketItemNoteEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let itemName: String
    let initialNote: String?
    let onSave: (String?) -> Void

    @State private var noteText: String

    init(itemName: String, initialNote: String?, onSave: @escaping (String?) -> Void) {
        self.itemName = itemName
        self.initialNote = initialNote
        self.onSave = onSave
        _noteText = State(initialValue: initialNote ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section(itemName) {
                    TextField(String(localized: "basket_item_note.add_note"), text: $noteText, axis: .vertical)
                        .lineLimit(3...5)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color("LaunchBackground"))
            .navigationTitle(Text("basket_item_note.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save")) {
                        onSave(noteText)
                        dismiss()
                    }
                }
            }
        }
    }
}