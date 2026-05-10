import SwiftUI
import StoreKit

struct ProPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let purchaseManager: PurchaseManager

    private var priceString: String {
        purchaseManager.product?.displayPrice ?? "$2.99"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    features
                        .padding(.top, 32)
                    purchaseButton
                        .padding(.top, 32)
                    restoreButton
                        .padding(.top, 12)
                    disclaimer
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
            }
            .background(Color("LaunchBackground"))
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.secondarySystemFill), in: Circle())
                    }
                    .accessibilityLabel(Text("action.close"))
                }
            }
        }
        .task { await purchaseManager.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.15), Color.green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 32)

            VStack(spacing: 6) {
                Text("Taplist Pro")
                    .font(.title.bold())

                Text("Unlock AI-powered shopping lists")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Feature list

    private var features: some View {
        VStack(spacing: 12) {
            featureRow(
                icon: "sparkles",
                color: .green,
                title: "AI Recipe Import",
                description: "Describe any recipe — Taplist builds your shopping list instantly."
            )
            featureRow(
                icon: "wand.and.stars",
                color: .purple,
                title: "Smart Ingredient Matching",
                description: "AI suggestions match items you already have in your product list."
            )
            featureRow(
                icon: "arrow.triangle.2.circlepath",
                color: .orange,
                title: "Recipe History",
                description: "Quickly re-run your favourite recipes without typing again."
            )
        }
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(colors: [color.opacity(0.85), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: color.opacity(0.3), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Purchase button

    private var purchaseButton: some View {
        Button {
            Task { await purchaseManager.purchase() }
        } label: {
            Group {
                if purchaseManager.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Unlock for \(priceString)")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .disabled(purchaseManager.isLoading || purchaseManager.product == nil)
        .shadow(color: .green.opacity(0.35), radius: 8, y: 4)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await purchaseManager.restorePurchases() }
        } label: {
            Text("Restore Purchase")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .disabled(purchaseManager.isLoading)
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("One-time purchase · No subscription · Works fully on-device")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}
