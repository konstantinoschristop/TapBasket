import SwiftUI

struct BasketShareView: View {
    let regularItems: [BasketItemSnapshot]
    let recipeGroups: [RecipeGroupSnapshot]

    private let pageWidth: CGFloat = 390
    private let hPad: CGFloat = 20

    private let green      = Color(red: 0.13, green: 0.62, blue: 0.44)
    private let greenDeep  = Color(red: 0.07, green: 0.44, blue: 0.32)
    private let greenLight = Color(red: 0.88, green: 0.97, blue: 0.92)
    private let amber      = Color(red: 0.88, green: 0.56, blue: 0.16)
    private let amberLight = Color(red: 1.00, green: 0.96, blue: 0.87)

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
        .background(Color(red: 0.96, green: 0.99, blue: 0.97)) // very soft green tint
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            // Gradient banner
            LinearGradient(
                colors: [greenDeep, green],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 130)

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 160, height: 160)
                .offset(x: 140, y: 40)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 100, height: 100)
                .offset(x: -130, y: 50)

            // Content
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("🛒")
                            .font(.system(size: 26))
                        Text("Shopping List")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text(dateString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.70))
                }
                Spacer()
                Text("\(totalCount) \(totalCount == 1 ? "item" : "items")")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, hPad + 4)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Items Card

    private func itemsCard(items: [BasketItemSnapshot]) -> some View {
        VStack(spacing: 0) {
            // Green accent bar at top of card
            green.frame(height: 3)

            ForEach(Array(items.enumerated()), id: \.element.name) { index, item in
                itemRow(item, tint: green, circleBg: greenLight)
                if index < items.count - 1 {
                    Color(white: 0.93).frame(height: 0.5).padding(.leading, 64)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Recipe Group Card

    private func recipeGroupCard(_ group: RecipeGroupSnapshot) -> some View {
        VStack(spacing: 0) {
            // Amber accent bar
            amber.frame(height: 3)

            // Recipe header row
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(amber)
                Text(group.name.capitalized)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(amber)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(amberLight)

            ForEach(Array(group.items.enumerated()), id: \.element.name) { index, item in
                itemRow(item, tint: amber, circleBg: amberLight)
                if index < group.items.count - 1 {
                    Color(white: 0.93).frame(height: 0.5).padding(.leading, 64)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Item Row

    private func itemRow(_ item: BasketItemSnapshot, tint: Color, circleBg: Color) -> some View {
        HStack(spacing: 14) {
            Text(item.emoji)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .background(circleBg)
                .clipShape(Circle())

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

            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12))
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
            HStack(spacing: 5) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Taplist")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(green.opacity(0.6))
        }
        .padding(.horizontal, hPad + 4)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}
