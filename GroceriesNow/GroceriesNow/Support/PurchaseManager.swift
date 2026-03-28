import StoreKit
import Observation

@Observable @MainActor
final class PurchaseManager {

    // MARK: - Product ID
    // Register this exact ID in App Store Connect → In-App Purchases → Non-Consumable
    static let proProductID = "k.christopoulos.Taplist.pro"

    // MARK: - State
    private(set) var isPro: Bool = false
    private(set) var product: Product?
    private(set) var isLoading: Bool = false
    private(set) var purchaseError: String?

    nonisolated(unsafe) private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first
        } catch {
            purchaseError = error.localizedDescription
        }

        await refreshPurchaseStatus()
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else { return }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshPurchaseStatus()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement check

    func refreshPurchaseStatus() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID && transaction.revocationDate == nil {
                isPro = true
                return
            }
        }
        isPro = false
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                do {
                    let transaction = try await MainActor.run { try self.checkVerified(result) }
                    await transaction.finish()
                    await self.refreshPurchaseStatus()
                } catch {
                    // Invalid transaction — ignore
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
