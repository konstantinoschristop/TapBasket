import SwiftUI

/// Image-renderable representation of a basket for the share sheet.
///
/// Mirrors the in-app aesthetic: warm cream page, flat `CardBackground`
/// rows, muted olive accent, BrandGreen for completion-style cues,
/// hairline separators. No saturated gradients or decorative circles
/// — the share image should read as the same product, not a brochure.
///
/// Colors are hardcoded here (rather than asset-references) because
/// this view renders to a `UIImage` via `ImageRenderer` and we want
/// deterministic output regardless of the user's appearance mode.
struct BasketShareView: View {
    let basketName: String?
    let regularItems: [BasketItemSnapshot]
    let recipeGroups: [RecipeGroupSnapshot]

    // MARK: - Palette (locked sRGB; no light/dark variants in renders)

    private let pageBackground = Color(red: 0.957, green: 0.945, blue: 0.926) // LaunchBackground light
    private let cardBackground = Color(red: 0.980, green: 0.973, blue: 0.961) // CardBackground light
    private let olive          = Color(red: 0.486, green: 0.537, blue: 0.404) // AccentColor light
    private let oliveSoft      = Color(red: 0.486, green: 0.537, blue: 0.404).opacity(0.10)
    private let brandGreen     = Color(red: 0.13,  green: 0.62,  blue: 0.44)  // BrandGreen
    private let brandGreenSoft = Color(red: 0.88,  green: 0.97,  blue: 0.92)
    private let separator      = Color(red: 0.85,  green: 0.84,  blue: 0.81)
    private let primaryInk     = Color(red: 0.10,  green: 0.10,  blue: 0.10)
    private let secondaryInk   = Color(red: 0.40,  green: 0.40,  blue: 0.38)
    private let tertiaryInk    = Color(red: 0.58,  green: 0.58,  blue: 0.55)

    // MARK: - Layout

    private let pageWidth: CGFloat = 390
    private let hPad: CGFloat = 20

    private var totalCount: Int {
        regularItems.count + recipeGroups.reduce(0) { $0 + $1.items.count }
    }

    private var dateString: String {
        Date.now.formatted(date: .long, time: .omitted)
    }

    private var titleText: String {
        if let name = basketName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return String(localized: "basket.share.heading", defaultValue: "Shopping List")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 12) {
                if !regularItems.isEmpty {
                    itemsCard(items: regularItems)
                }
                ForEach(recipeGroups, id: \.name) { group in
                    recipeGroupCard(group)
                }
            }
            .padding(.horizontal, hPad)
            .padding(.top, 18)
            .padding(.bottom, 12)

            footer
        }
        .frame(width: pageWidth)
        .background(pageBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(primaryInk)
                        .lineLimit(2)
                    Text(dateString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryInk)
                }
                Spacer(minLength: 8)
                countPill
            }
        }
        .padding(.horizontal, hPad)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var countPill: some View {
        Text("\(totalCount) \(totalCount == 1 ? "item" : "items")")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(olive)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(oliveSoft)
            .clipShape(Capsule())
    }

    // MARK: - Items card

    private func itemsCard(items: [BasketItemSnapshot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.name) { index, item in
                itemRow(item)
                if index < items.count - 1 {
                    separator.frame(height: 0.5).padding(.leading, 60)
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    // MARK: - Recipe group card

    private func recipeGroupCard(_ group: RecipeGroupSnapshot) -> some View {
        VStack(spacing: 0) {
            // Quiet group header — sparkles + name in olive, no
            // colored bar or coloured fill. Reads as "this is a
            // recipe" without competing with the basket header.
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(olive)
                Text(group.name.capitalized)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(olive)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            separator.frame(height: 0.5).padding(.leading, 16)

            ForEach(Array(group.items.enumerated()), id: \.element.name) { index, item in
                itemRow(item)
                if index < group.items.count - 1 {
                    separator.frame(height: 0.5).padding(.leading, 60)
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    // MARK: - Item row

    private func itemRow(_ item: BasketItemSnapshot) -> some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(oliveSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(primaryInk)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(tertiaryInk)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(brandGreen)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
            .foregroundColor(olive.opacity(0.7))
        }
        .padding(.horizontal, hPad)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }
}
