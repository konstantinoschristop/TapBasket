import SwiftUI

struct BasketShareView: View {
    let regularItems: [BasketItemSnapshot]
    let recipeGroups: [RecipeGroupSnapshot]

    private let pageWidth: CGFloat = 390
    private let hPad: CGFloat = 20

    private var totalCount: Int {
        regularItems.count + recipeGroups.reduce(0) { $0 + $1.items.count }
    }

    private var dateString: String {
        Date.now.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 10) {
                if !regularItems.isEmpty {
                    itemsCard(items: regularItems)
                }
                ForEach(recipeGroups, id: \.name) { group in
                    recipeGroupCard(group)
                }
            }
            .padding(.horizontal, hPad)
            .padding(.top, 20)
            .padding(.bottom, 4)
            footer
        }
        .frame(width: pageWidth)
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("🛒 Shopping List")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.10))
                Text(dateString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer()
            Text("\(totalCount) \(totalCount == 1 ? "item" : "items")")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.13, green: 0.60, blue: 0.42))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.13, green: 0.60, blue: 0.42).opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.horizontal, hPad + 4)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Items Card

    private func itemsCard(items: [BasketItemSnapshot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.name) { index, item in
                itemRow(item)
                if index < items.count - 1 {
                    Color(white: 0.92).frame(height: 0.5).padding(.leading, 64)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Recipe Group Card

    private func recipeGroupCard(_ group: RecipeGroupSnapshot) -> some View {
        VStack(spacing: 0) {
            // Recipe header row
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.88, green: 0.56, blue: 0.16))
                Text(group.name.capitalized)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.88, green: 0.56, blue: 0.16))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 1.0, green: 0.96, blue: 0.88))

            // Items
            ForEach(Array(group.items.enumerated()), id: \.element.name) { index, item in
                itemRow(item)
                if index < group.items.count - 1 {
                    Color(white: 0.92).frame(height: 0.5).padding(.leading, 64)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Item Row

    private func itemRow(_ item: BasketItemSnapshot) -> some View {
        HStack(spacing: 14) {
            // Emoji in soft circle
            Text(item.emoji)
                .font(.system(size: 20))
                .frame(width: 34, height: 34)
                .background(Color(red: 0.94, green: 0.95, blue: 0.97))
                .clipShape(Circle())

            // Name + note
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.08))
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Color(white: 0.52))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Quantity badge
            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.13, green: 0.60, blue: 0.42))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.13, green: 0.60, blue: 0.42).opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("GroceriesNow")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Color(white: 0.62))
        }
        .padding(.horizontal, hPad + 4)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}
