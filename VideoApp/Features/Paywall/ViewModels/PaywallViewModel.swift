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
    @Published var selectedPlan: SubscriptionPlan = .yearly
    @Published var isLoading = false
    @Published var isPurchasing = false
    @Published var error: String?
    @Published var showError = false
    @Published var purchaseComplete = false
    
    // MARK: - Private
    private let subscriptionManager = SubscriptionManager.shared
    private let planService = SubscriptionPlanService.shared
    
    // MARK: - Computed Properties
    
    var weeklyProduct: Product? {
        products.first { $0.id == SubscriptionPlan.weekly.productId }
    }
    
    var yearlyProduct: Product? {
        products.first { $0.id == SubscriptionPlan.yearly.productId }
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
    
    // MARK: - Initialization
    
    init() {
        // Observe products from subscription manager
        subscriptionManager.$products
            .assign(to: &$products)
        
        subscriptionManager.$isLoading
            .assign(to: &$isLoading)
        
        // Observe plan infos from plan service
        planService.$plans
            .assign(to: &$planInfos)
    }
    
    // MARK: - Public Methods
    
    /// Load products from App Store and plan info from backend
    func loadProducts() async {
        async let storeProducts: () = subscriptionManager.loadContent()
        async let backendPlans: () = planService.fetchPlans()
        
        // Load both in parallel
        _ = await (storeProducts, backendPlans)
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
        let plan: AnalyticsEvent.SubscriptionPlan = selectedPlan == .weekly ? .weekly : .yearly
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
