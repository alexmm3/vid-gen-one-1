//
//  SubscriptionManager.swift
//  AIVideo
//
//  Singleton managing StoreKit 2 subscription operations
//  Adapted from templates-reference
//

import Foundation
import StoreKit

// MARK: - SubscriptionManagerDelegate

@MainActor
protocol SubscriptionManagerDelegate: AnyObject {
    func contentWasLoaded(with products: [Product])
    func purchasedSuccessfully(with productId: String, transactionId: UInt64)
    func restoredSuccessfully(with productId: String)
    func errorOccurred(error: Error)
}

extension SubscriptionManagerDelegate {
    func contentWasLoaded(with products: [Product]) {}
    func purchasedSuccessfully(with productId: String, transactionId: UInt64) {}
    func restoredSuccessfully(with productId: String) {}
    func errorOccurred(error: Error) {}
}

// MARK: - SubscriptionManager

@MainActor
final class SubscriptionManager: ObservableObject {
    // MARK: - Constants
    private enum Constant {
        static let productIds: [String] = BrandConfig.allProductIds
        static let processedTransactionKey = "processedTransactionId"
        static let subscriptionProductIdKey = "subscriptionProductId"
        static let lastTransactionIdKey = "lastOriginalTransactionId"
    }
    
    // MARK: - Singleton
    static let shared = SubscriptionManager()
    
    // MARK: - Properties
    weak var delegate: SubscriptionManagerDelegate?
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasActiveSubscription = false
    
    private var transactionUpdatesTask: Task<Void, Never>?
    private var lastProcessedTransactionId: UInt64?
    
    /// Last known original transaction ID for backend validation (stored in UserDefaults)
    private(set) var lastTransactionId: String? {
        get {
            UserDefaults.standard.string(forKey: Constant.lastTransactionIdKey)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id, forKey: Constant.lastTransactionIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constant.lastTransactionIdKey)
            }
        }
    }
    
    /// Current subscription product ID (stored in UserDefaults)
    var currentProductId: String? {
        get {
            UserDefaults.standard.string(forKey: Constant.subscriptionProductIdKey)
        }
        set {
            if let productId = newValue {
                UserDefaults.standard.set(productId, forKey: Constant.subscriptionProductIdKey)
                hasActiveSubscription = true
            } else {
                UserDefaults.standard.removeObject(forKey: Constant.subscriptionProductIdKey)
                hasActiveSubscription = false
            }
            NotificationCenter.default.post(
                name: .subscriptionStatusChanged,
                object: nil,
                userInfo: ["isPremium": newValue != nil]
            )
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        lastProcessedTransactionId = Self.loadLastProcessedTransactionId()
        hasActiveSubscription = UserDefaults.standard.string(forKey: Constant.subscriptionProductIdKey) != nil
    }
    
    // MARK: - Public Methods
    
    /// Load products from App Store Connect
    func loadContent() async {
        isLoading = true

        do {
            print("🔄 SubscriptionManager: Loading products for IDs: \(Constant.productIds)")
            let storeProducts = try await Product.products(for: Constant.productIds)
                .sorted(by: { $0.price > $1.price })
            self.products = storeProducts
            delegate?.contentWasLoaded(with: storeProducts)

            if storeProducts.isEmpty {
                print("⚠️ SubscriptionManager: Product.products() returned EMPTY array for IDs: \(Constant.productIds)")
            } else {
                for product in storeProducts {
                    print("✅ SubscriptionManager: Loaded \(product.id) — \(product.displayPrice) (\(product.displayName))")
                }
            }
        } catch {
            delegate?.errorOccurred(error: error)
            print("❌ SubscriptionManager: Failed to load products - \(error.localizedDescription)")
            print("❌ SubscriptionManager: Error details - \(error)")
        }

        isLoading = false
    }
    
    /// Purchase a product
    func purchaseProduct(product: Product) async {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let productId = transaction.productID
                    let transactionId = transaction.id
                    let originalTransactionId = transaction.originalID
                    let signedTransactionInfo = verification.jwsRepresentation
                    
                    currentProductId = productId
                    lastTransactionId = String(originalTransactionId)
                    
                    await transaction.finish()
                    
                    await validateWithBackend(
                        originalTransactionId: String(originalTransactionId),
                        signedTransactionInfo: signedTransactionInfo
                    )
                    
                    guard registerProcessedTransaction(transactionId) else { return }
                    delegate?.purchasedSuccessfully(with: productId, transactionId: transactionId)
                    
                    // Track analytics
                    let plan: AnalyticsEvent.SubscriptionPlan = productId.contains("weekly") ? .weekly : .monthly
                    Analytics.track(.purchaseCompleted(plan: plan, transactionId: String(transactionId)))
                    
                    print("✅ SubscriptionManager: Purchase successful - \(productId)")
                    
                case .unverified(_, let error):
                    delegate?.errorOccurred(error: error)
                    Analytics.track(.purchaseFailed(plan: .weekly, error: error.localizedDescription))
                }
                
            case .userCancelled:
                delegate?.errorOccurred(error: IAPError.cancelledByUser)
                
            case .pending:
                delegate?.errorOccurred(error: IAPError.paymentRequestIsNotFinished)
                
            @unknown default:
                delegate?.errorOccurred(error: IAPError.purchaseFail)
            }
        } catch {
            delegate?.errorOccurred(error: error)
            Analytics.track(.purchaseFailed(plan: .weekly, error: error.localizedDescription))
        }
    }
    
    /// Restore purchases
    func restorePurchases() async {
        Analytics.track(.restoreStarted)
        var restored = false
        
        for await verification in Transaction.currentEntitlements {
            switch verification {
            case .verified(let transaction):
                let productId = transaction.productID
                let originalTransactionId = transaction.originalID
                let signedTransactionInfo = verification.jwsRepresentation
                
                currentProductId = productId
                lastTransactionId = String(originalTransactionId)
                
                delegate?.restoredSuccessfully(with: productId)
                await transaction.finish()
                await validateWithBackend(
                    originalTransactionId: String(originalTransactionId),
                    signedTransactionInfo: signedTransactionInfo
                )
                restored = true
                
                print("✅ SubscriptionManager: Restored subscription - \(productId)")
                
            case .unverified(_, let error):
                delegate?.errorOccurred(error: error)
            }
        }
        
        if restored {
            Analytics.track(.restoreCompleted)
        } else {
            delegate?.errorOccurred(error: IAPError.restoringFail)
            Analytics.track(.restoreFailed(error: "No purchases to restore"))
        }
    }
    
    /// Refresh subscription status from StoreKit, syncing with backend on every launch.
    /// This ensures the backend always has the latest expiration date.
    func refreshSubscriptionStatus() async {
        // 1. Try StoreKit entitlements first — this is the source of truth
        for await verification in Transaction.currentEntitlements {
            switch verification {
            case .verified(let transaction):
                currentProductId = transaction.productID
                lastTransactionId = String(transaction.originalID)
                await validateWithBackend(
                    originalTransactionId: String(transaction.originalID),
                    signedTransactionInfo: verification.jwsRepresentation
                )
                return
            case .unverified:
                continue
            }
        }
        
        // 2. No StoreKit entitlements — check with backend using stored transaction
        //    (backend will verify if the subscription record is still valid)
        if let txId = lastTransactionId {
            await validateWithBackend(
                originalTransactionId: txId,
                clearStateOnInvalidResponse: true
            )
            return
        }
        
        // 3. Nothing stored — not subscribed
        currentProductId = nil
    }
    
    /// Start listening for transaction updates (call at app launch)
    func startTransactionUpdatesListener() {
        transactionUpdatesTask?.cancel()
        
        transactionUpdatesTask = Task.detached { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { continue }
                
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    
                    // Capture transaction data before crossing to MainActor
                    let productId = transaction.productID
                    let transactionId = transaction.id
                    let originalTransactionId = transaction.originalID
                    let signedTransactionInfo = verification.jwsRepresentation
                    
                    await MainActor.run {
                        self.currentProductId = productId
                        self.lastTransactionId = String(originalTransactionId)
                        
                        guard self.registerProcessedTransaction(transactionId) else { return }
                        self.delegate?.purchasedSuccessfully(with: productId, transactionId: transactionId)
                        
                        Task {
                            await self.validateWithBackend(
                                originalTransactionId: String(originalTransactionId),
                                signedTransactionInfo: signedTransactionInfo
                            )
                        }
                    }
                }
            }
        }
    }
    
    /// Update products from external source (e.g., PaywallViewModel direct load)
    func updateProducts(_ newProducts: [Product]) {
        self.products = newProducts
    }

    /// Get product by plan type
    func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == plan.productId }
    }
    
    // MARK: - Private Methods
    
    /// Detect if we're in sandbox (TestFlight, Xcode debug, or sandbox tester).
    /// Backend must use Apple's sandbox API to verify these transactions.
    private var useSandboxForValidation: Bool {
        #if DEBUG
        return true
        #else
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        let path = url.path.lowercased()
        return path.contains("sandboxreceipt")
        #endif
    }
    
    private func validateWithBackend(
        originalTransactionId: String,
        signedTransactionInfo: String? = nil,
        clearStateOnInvalidResponse: Bool = false
    ) async {
        do {
            let result = try await SubscriptionValidationService.shared.validateSubscription(
                originalTransactionId: originalTransactionId,
                signedTransactionInfo: signedTransactionInfo,
                useSandbox: useSandboxForValidation
            )
            
            if result.isValid {
                // Backend confirms subscription is active — sync local state
                if let productId = result.productId {
                    currentProductId = productId
                }
                AppState.shared.setPremiumStatus(
                    true,
                    generationsRemaining: result.generationsRemaining,
                    generationsUsed: result.generationsUsed,
                    generationLimit: result.generationLimit,
                    expiresAt: result.expiresAt
                )
            } else {
                // Backend says subscription expired — clear local state
                currentProductId = nil
                lastTransactionId = nil
                AppState.shared.setPremiumStatus(false)
            }
        } catch {
            print("⚠️ SubscriptionManager: Backend validation failed - \(error)")
            if clearStateOnInvalidResponse,
               let validationError = error as? ValidationError,
               validationError == .invalidResponse {
                currentProductId = nil
                lastTransactionId = nil
                AppState.shared.setPremiumStatus(false)
            }
        }
    }
    
    private func registerProcessedTransaction(_ id: UInt64) -> Bool {
        guard lastProcessedTransactionId != id else { return false }
        lastProcessedTransactionId = id
        persistLastProcessedTransactionId()
        return true
    }
    
    private func persistLastProcessedTransactionId() {
        guard let id = lastProcessedTransactionId else {
            _ = KeychainManager.shared.delete(key: Constant.processedTransactionKey)
            return
        }
        _ = KeychainManager.shared.store(key: Constant.processedTransactionKey, value: "\(id)")
    }
    
    private static func loadLastProcessedTransactionId() -> UInt64? {
        guard let string = KeychainManager.shared.retrieve(key: Constant.processedTransactionKey),
              let id = UInt64(string) else { return nil }
        return id
    }
}
