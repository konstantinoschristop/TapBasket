import SwiftUI

struct SmartStartView: View {
    let items: [QuickItem]
    let onTapItem: (QuickItem) -> Void
    let onAddAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            chipsScroll
        }
        .padding(16)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("smart_start.title")
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text("smart_start.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAddAll) {
                Text("action.add_all")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.spring(scale: 0.94))
        }
    }

    private var chipsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button { onTapItem(item) } label: {
                        HStack(spacing: 6) {
                            Text(item.emoji).font(.body)
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color("LaunchBackground"), in: Capsule())
                        .overlay(Capsule().stroke(Color(.separator).opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.spring)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}
