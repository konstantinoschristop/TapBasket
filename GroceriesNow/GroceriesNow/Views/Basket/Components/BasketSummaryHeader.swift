import SwiftUI
import SwiftData

/// Hero header at the top of the Basket screen.
///
/// Big metric on top (total quantity), thin progress bar below, and an explicit
/// caption that reads "3 of 8 checked · 5 to go" so progress is obvious without
/// needing to decode a fraction. Switches to "All done" when complete.
struct BasketSummaryHeader: View {
    let totalQuantity: Int
    let checkedCount: Int
    let totalCount: Int

    init(items: [BasketItem]) {
        self.totalQuantity = items.reduce(0) { $0 + $1.quantity }
        self.checkedCount = items.filter(\.isChecked).count
        self.totalCount = items.count
    }

    private var remaining: Int {
        max(0, totalCount - checkedCount)
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(checkedCount) / Double(totalCount)
    }

    private var isComplete: Bool {
        totalCount > 0 && checkedCount == totalCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            metrics
            // Progress bar is always present — gives the header a stable
            // vertical rhythm and shows the user the empty track from
            // the start so they understand what's coming.
            progressTrack
            caption
        }
        .animation(.taplistTransition, value: progress)
    }

    // MARK: - Metric line

    private var metrics: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(totalQuantity)")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Color(.label))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(totalQuantity)))

            Text(itemsLabel)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color(.secondaryLabel))

            Spacer()
        }
    }

    // MARK: - Progress bar

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))

                Capsule()
                    .fill(Color("BrandGreen"))
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 6)
    }

    // MARK: - Caption (explanation)

    @ViewBuilder
    private var caption: some View {
        if totalCount == 0 {
            EmptyView()
        } else if isComplete {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color("BrandGreen"))
                Text("basket.summary.all_done")
                    .foregroundStyle(Color("BrandGreen"))
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
        } else {
            HStack(spacing: 0) {
                Text("\(checkedCount) of \(totalCount) checked")
                    .foregroundStyle(Color(.secondaryLabel))
                Text("  ·  ")
                    .foregroundStyle(Color(.tertiaryLabel))
                Text("\(remaining) to go")
                    .foregroundStyle(Color(.label))
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.subheadline)
            .monospacedDigit()
        }
    }

    private var itemsLabel: String {
        totalQuantity == 1 ? "item" : "items"
    }
}
