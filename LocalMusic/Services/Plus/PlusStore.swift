import Foundation
import StoreKit

/// ChibiAudio Plus — auto-renewable monthly StoreKit product.
///
/// Product ID: `com.chibitek.ChibiAudio.plus.monthly` ($1.99/mo).
/// Unlocks: no ads, all visualizer modes, CarPlay / Watch stubs.
@Observable
@MainActor
final class PlusStore {

    static let productID = AppBranding.plusMonthlyProductID
    static let displayPriceFallback = "$1.99"

    private(set) var product: Product?
    private(set) var isPlusActive = false
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var purchaseInFlight = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await _ in StoreKit.Transaction.updates {
                await self?.refreshEntitlements()
            }
        }
        Task { await bootstrap() }
    }

    deinit {
        updatesTask?.cancel()
    }

    var displayPrice: String {
        product?.displayPrice ?? Self.displayPriceFallback
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        await loadProduct()
        await refreshEntitlements()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if products.isEmpty {
                Log.ui.warning("Plus product not found: \(Self.productID)")
            }
        } catch {
            lastError = error.localizedDescription
            Log.ui.error("Plus product load failed: \(error.localizedDescription)")
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID {
                active = true
                break
            }
        }
        isPlusActive = active
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            lastError = "Plus isn’t available to purchase right now. Try again later."
            await loadProduct()
            return false
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Couldn’t verify the purchase."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                lastError = nil
                return isPlusActive
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            Log.ui.error("Plus purchase failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastError = nil
            return isPlusActive
        } catch {
            lastError = error.localizedDescription
            Log.ui.error("Plus restore failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Test / preview helper — does not touch StoreKit.
    func setPlusActiveForTesting(_ active: Bool) {
        isPlusActive = active
    }
}
