//
//  PaywallViewModel.swift
//  AIVideo
//
//  ViewModel for the paywall view
//

import Combine
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
    private var cancellable: AnyCancellable?

    init() {
        // Sync products from SubscriptionManager (may already be loaded at app launch)
        products = subscriptionManager.products
        cancellable = subscriptionManager.$products
            .dropFirst() // skip initial value (already assigned above)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.products = $0 }
    }

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

    /// Load plan info from backend; reload StoreKit products only if not yet available
    func loadProducts() async {
        isLoading = true

        // Fetch backend plan info in parallel
        async let backendPlans: () = planService.fetchPlans()

        // If SubscriptionManager hasn't loaded products yet (e.g. slow network at launch),
        // trigger a load now as fallback
        if products.isEmpty {
            await subscriptionManager.loadContent()
        }

        _ = await backendPlans
        planInfos = planService.plans

        isLoading = false
    }

    /// Purchase selected plan
    func purchase() async {
        // If products still haven't loaded, try once more
        if products.isEmpty {
            await subscriptionManager.loadContent()
        }

        guard let product = selectedProduct else {
            error = "Unable to load subscription. Please check your internet connection and try again."
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
