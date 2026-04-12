import StoreKit
import SwiftUI

/// Centralized StoreKit 2 manager — single source of truth for subscription state.
@MainActor
final class StoreManager: ObservableObject {

    static let shared = StoreManager()

    // MARK: - Product IDs

    static let weeklyID = "com.shabbatclock.app.premium.weekly"
    static let yearlyID = "com.shabbatclock.app.premium.yearly"
    static let subscriptionGroupID = "premium_group"

    private let productIDs: Set<String> = [weeklyID, yearlyID]

    // MARK: - Published State

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var subscriptionStatus: Product.SubscriptionInfo.RenewalState?
    @Published private(set) var isLoading = false

    /// Whether the user has an active premium subscription.
    var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    /// The weekly product (if loaded).
    var weeklyProduct: Product? {
        products.first { $0.id == Self.weeklyID }
    }

    /// The yearly product (if loaded).
    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyID }
    }

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?

    // MARK: - Init

    private init() {
        transactionListener = listenForTransactions()

        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: productIDs)
            // Sort so yearly appears first (higher value)
            products = loaded.sorted { $0.price > $1.price }
        } catch {
            print("[StoreManager] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            guard let transaction = try? verification.payloadValue else {
                print("[StoreManager] Transaction verification failed")
                return false
            }
            await grantEntitlement(for: transaction)
            await transaction.finish()
            await updatePurchasedProducts()
            syncAppStorage()
            return true

        case .userCancelled:
            return false

        case .pending:
            // Ask to Buy or payment issue — delivered via Transaction.updates later
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        try? await AppStore.sync()
        await updatePurchasedProducts()
        syncAppStorage()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await verificationResult in StoreKit.Transaction.updates {
                await self?.handleTransaction(verificationResult)
            }
        }
    }

    private func handleTransaction(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = try? result.payloadValue else {
            print("[StoreManager] Unverified transaction")
            return
        }

        if transaction.revocationDate != nil {
            // Refunded — revoke access
            purchasedProductIDs.remove(transaction.productID)
        } else {
            await grantEntitlement(for: transaction)
        }

        await transaction.finish()
        await updatePurchasedProducts()
        syncAppStorage()
    }

    // MARK: - Entitlements

    private func grantEntitlement(for transaction: StoreKit.Transaction) async {
        guard transaction.revocationDate == nil else {
            purchasedProductIDs.remove(transaction.productID)
            return
        }
        purchasedProductIDs.insert(transaction.productID)
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue,
                  transaction.revocationDate == nil else {
                continue
            }
            purchased.insert(transaction.productID)
        }

        purchasedProductIDs = purchased
        syncAppStorage()

        // Update subscription status
        await updateSubscriptionStatus()
    }

    private func updateSubscriptionStatus() async {
        guard let statuses = try? await Product.SubscriptionInfo.status(
            for: Self.subscriptionGroupID
        ) else {
            subscriptionStatus = nil
            return
        }

        // Use the most favorable status
        subscriptionStatus = statuses.first?.state
    }

    // MARK: - AppStorage Sync

    /// Keeps the legacy @AppStorage("isPremium") in sync so existing views
    /// that read it directly continue to work without refactoring every view.
    private func syncAppStorage() {
        UserDefaults.standard.set(isPremium, forKey: "isPremium")
    }

    // MARK: - Helpers

    /// Formatted savings percentage for yearly vs weekly.
    var yearlySavingsPercent: Int {
        guard let weekly = weeklyProduct, let yearly = yearlyProduct else { return 0 }
        let weeklyAnnual = weekly.price * 52
        guard weeklyAnnual > 0 else { return 0 }
        let savings = (weeklyAnnual - yearly.price) / weeklyAnnual * 100
        return NSDecimalNumber(decimal: savings).intValue
    }
}
