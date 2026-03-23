//
//  PaywallViewModel.swift
//  AIVideo
//
//  ViewModel for the paywall view
//

import Foundation
import StoreKit

@MainActor
final class PaywallViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var products: [Product] = []
    @Published var planInfos: [SubscriptionPlanInfo] = []
    @Published var selectedPlan: SubscriptionPlan = .monthly
    @Published var isLoading = false
    @Published var isPurchasing = false
    @Published var error: String?
    @Published var showError = false
    @Published var purchaseComplete = false

    // MARK: - Private
    private let subscriptionManager = SubscriptionManager.shared
    private let planService = SubscriptionPlanService.shared
    private static let maxRetries = 3

    // MARK: - Computed Properties

    var weeklyProduct: Product? {
        products.first { $0.id == SubscriptionPlan.weekly.productId }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionPlan.monthly.productId }
    }

    var selectedProduct: Product? {
        products.first { $0.id == selectedPlan.productId }
    }

    /// Get plan info for a subscription plan
    func planInfo(for plan: SubscriptionPlan) -> SubscriptionPlanInfo? {
        planInfos.first { $0.appleProductId == plan.productId }
    }

    /// Get limit description for selected plan (e.g., "10 videos per week")
    var selectedPlanLimitDescription: String {
        planInfo(for: selectedPlan)?.limitDescription ?? selectedPlan.defaultLimitDescription
    }

    // MARK: - Public Methods

    /// Load products directly from StoreKit and plan info from backend
    func loadProducts() async {
        isLoading = true

        let productIds = BrandConfig.allProductIds
        print("🔄 PaywallViewModel: Loading products for IDs: \(productIds)")

        // Load backend plans in parallel (optional, don't block on it)
        async let backendPlans: () = planService.fetchPlans()

        // Load StoreKit products with silent retry
        for attempt in 1...Self.maxRetries {
            do {
                let storeProducts = try await Product.products(for: productIds)

                if !storeProducts.isEmpty {
                    self.products = storeProducts.sorted(by: { $0.price > $1.price })
                    // Also update the shared manager so purchases work
                    subscriptionManager.updateProducts(self.products)
                    print("✅ PaywallViewModel: Loaded \(storeProducts.count) products")
                    for p in storeProducts {
                        print("  → \(p.id): \(p.displayPrice)")
                    }
                    break
                } else {
                    print("⚠️ PaywallViewModel: Attempt \(attempt)/\(Self.maxRetries) — empty products")
                }
            } catch {
                print("❌ PaywallViewModel: Attempt \(attempt)/\(Self.maxRetries) — \(error)")
            }

            if attempt < Self.maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }

        // Wait for backend plans
        _ = await backendPlans
        planInfos = planService.plans

        isLoading = false
    }

    /// Purchase selected plan
    func purchase() async {
        guard let product = selectedProduct else {
            error = "Unable to load product"
            showError = true
            return
        }

        isPurchasing = true

        // Track start
        let plan: AnalyticsEvent.SubscriptionPlan = selectedPlan == .weekly ? .weekly : .monthly
        Analytics.track(.purchaseStarted(plan: plan))

        // Create a delegate wrapper to handle callbacks
        let delegateWrapper = PurchaseDelegateWrapper()
        subscriptionManager.delegate = delegateWrapper

        delegateWrapper.onSuccess = { [weak self] productId, transactionId in
            self?.isPurchasing = false
            self?.purchaseComplete = true
            HapticManager.shared.success()
        }

        delegateWrapper.onError = { [weak self] error in
            self?.isPurchasing = false

            // Don't show error for user cancellation
            if let iapError = error as? IAPError, iapError == .cancelledByUser {
                return
            }

            self?.error = (error as? IAPError)?.message ?? error.localizedDescription
            self?.showError = true
            HapticManager.shared.error()
        }

        await subscriptionManager.purchaseProduct(product: product)
    }

    /// Restore purchases
    func restore() async {
        isPurchasing = true

        let delegateWrapper = PurchaseDelegateWrapper()
        subscriptionManager.delegate = delegateWrapper

        delegateWrapper.onRestored = { [weak self] productId in
            self?.isPurchasing = false
            self?.purchaseComplete = true
            HapticManager.shared.success()
        }

        delegateWrapper.onError = { [weak self] error in
            self?.isPurchasing = false
            self?.error = (error as? IAPError)?.message ?? error.localizedDescription
            self?.showError = true
            HapticManager.shared.error()
        }

        await subscriptionManager.restorePurchases()
    }

    /// Select a plan
    func selectPlan(_ plan: SubscriptionPlan) {
        HapticManager.shared.selection()
        selectedPlan = plan
    }
}

// MARK: - Delegate Wrapper

@MainActor
private class PurchaseDelegateWrapper: SubscriptionManagerDelegate {
    var onSuccess: ((String, UInt64) -> Void)?
    var onRestored: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func purchasedSuccessfully(with productId: String, transactionId: UInt64) {
        onSuccess?(productId, transactionId)
    }

    func restoredSuccessfully(with productId: String) {
        onRestored?(productId)
    }

    func errorOccurred(error: Error) {
        onError?(error)
    }
}
