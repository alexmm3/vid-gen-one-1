//
//  AnalyticsEvent.swift
//  AIVideo
//
//  Strongly-typed analytics events for the app
//

import Foundation

/// Strongly-typed analytics events for AI Video
enum AnalyticsEvent {
    // MARK: - App Lifecycle
    case appOpened
    case appBackgrounded

    // MARK: - Onboarding
    case onboardingStarted
    case onboardingPageViewed(page: Int)
    case onboardingCompleted
    case onboardingSkipped(page: Int)

    // MARK: - Paywall
    case paywallShown(source: PaywallSource)
    case paywallDismissed(source: PaywallSource)
    case paywallPlanSelected(plan: SubscriptionPlan, source: PaywallSource)
    case purchaseStarted(plan: SubscriptionPlan)
    case purchaseCompleted(plan: SubscriptionPlan, transactionId: String, productId: String)
    case purchaseFailed(plan: SubscriptionPlan, error: String)
    case purchaseCancelled(plan: SubscriptionPlan)
    case restoreStarted
    case restoreCompleted
    case restoreFailed(error: String)

    // MARK: - Effect Browsing
    case effectCatalogViewed
    case effectScrolled(effectId: String, effectName: String, position: Int)
    case effectDetailOpened(effectId: String, effectName: String)

    // MARK: - Generation
    case photoSelected(source: PhotoSource)
    case generationStarted(effectId: String?, effectName: String?, isCustom: Bool)
    case generationPollingStarted(generationId: String)
    case generationPollingResumed(generationId: String, pollCount: Int)
    case generationCompleted(generationId: String, durationSeconds: Int, effectName: String?)
    case generationFailed(effectId: String?, effectName: String?, error: String, errorCategory: ErrorCategory)
    case generationBackgrounded(generationId: String)
    case generationExpired(generationId: String)

    // MARK: - Result
    case resultViewed(effectName: String?)
    case videoSaved(effectName: String?)
    case videoSaveFailed(error: String)
    case videoShared(effectName: String?)
    case createAnotherTapped

    // MARK: - History
    case historyViewed
    case historyItemViewed(generationId: String)
    case historyItemDeleted(generationId: String)
    case createSimilarTapped(templateId: String?)

    // MARK: - Profile
    case profileViewed
    case settingsTapped(setting: String)
    case rateAppTapped
    case contactSupportTapped

    // MARK: - Navigation
    case tabSwitched(tab: String)

    // MARK: - Consent
    case aiConsentShown
    case aiConsentAccepted

    // MARK: - UI Interactions
    case photoTipsShown(effectName: String)
    case generationBlockedByActiveJob

    // MARK: - Subscription Lifecycle
    case subscriptionValidated(isValid: Bool, plan: String?)
    case subscriptionExpired

    // MARK: - Enums

    enum PaywallSource: String {
        case onboarding
        case generateBlocked = "generate_blocked"
        case profile
    }

    enum SubscriptionPlan: String {
        case weekly
        case monthly
    }

    enum PhotoSource: String {
        case camera
        case gallery
    }

    enum ErrorCategory: String {
        case network
        case timeout
        case subscription
        case server
        case unknown
    }
}

// MARK: - Firebase Event Mapping

extension AnalyticsEvent {
    /// Firebase event name (snake_case)
    var name: String {
        switch self {
        case .appOpened: return "app_opened"
        case .appBackgrounded: return "app_backgrounded"
        case .onboardingStarted: return "onboarding_started"
        case .onboardingPageViewed: return "onboarding_page_viewed"
        case .onboardingCompleted: return "onboarding_completed"
        case .onboardingSkipped: return "onboarding_skipped"
        case .paywallShown: return "paywall_shown"
        case .paywallDismissed: return "paywall_dismissed"
        case .paywallPlanSelected: return "paywall_plan_selected"
        case .purchaseStarted: return "purchase_started"
        case .purchaseCompleted: return "purchase_completed"
        case .purchaseFailed: return "purchase_failed"
        case .purchaseCancelled: return "purchase_cancelled"
        case .restoreStarted: return "restore_started"
        case .restoreCompleted: return "restore_completed"
        case .restoreFailed: return "restore_failed"
        case .effectCatalogViewed: return "effect_catalog_viewed"
        case .effectScrolled: return "effect_scrolled"
        case .effectDetailOpened: return "effect_detail_opened"
        case .photoSelected: return "photo_selected"
        case .generationStarted: return "generation_started"
        case .generationPollingStarted: return "generation_polling_started"
        case .generationPollingResumed: return "generation_polling_resumed"
        case .generationCompleted: return "generation_completed"
        case .generationFailed: return "generation_failed"
        case .generationBackgrounded: return "generation_backgrounded"
        case .generationExpired: return "generation_expired"
        case .resultViewed: return "result_viewed"
        case .videoSaved: return "video_saved"
        case .videoSaveFailed: return "video_save_failed"
        case .videoShared: return "video_shared"
        case .createAnotherTapped: return "create_another_tapped"
        case .historyViewed: return "history_viewed"
        case .historyItemViewed: return "history_item_viewed"
        case .historyItemDeleted: return "history_item_deleted"
        case .createSimilarTapped: return "create_similar_tapped"
        case .profileViewed: return "profile_viewed"
        case .settingsTapped: return "settings_tapped"
        case .rateAppTapped: return "rate_app_tapped"
        case .contactSupportTapped: return "contact_support_tapped"
        case .tabSwitched: return "tab_switched"
        case .aiConsentShown: return "ai_consent_shown"
        case .aiConsentAccepted: return "ai_consent_accepted"
        case .photoTipsShown: return "photo_tips_shown"
        case .generationBlockedByActiveJob: return "generation_blocked_active_job"
        case .subscriptionValidated: return "subscription_validated"
        case .subscriptionExpired: return "subscription_expired"
        }
    }

    /// Firebase event parameters
    var parameters: [String: Any]? {
        switch self {
        case .appOpened, .appBackgrounded:
            return nil

        case .onboardingStarted, .onboardingCompleted:
            return nil

        case .onboardingPageViewed(let page):
            return ["page": page]

        case .onboardingSkipped(let page):
            return ["page": page]

        case .paywallShown(let source), .paywallDismissed(let source):
            return ["source": source.rawValue]

        case .paywallPlanSelected(let plan, let source):
            return ["plan": plan.rawValue, "source": source.rawValue]

        case .purchaseStarted(let plan):
            return ["plan": plan.rawValue]

        case .purchaseCompleted(let plan, let transactionId, let productId):
            return ["plan": plan.rawValue, "transaction_id": transactionId, "product_id": productId]

        case .purchaseFailed(let plan, let error):
            return ["plan": plan.rawValue, "error": error]

        case .purchaseCancelled(let plan):
            return ["plan": plan.rawValue]

        case .restoreStarted, .restoreCompleted:
            return nil

        case .restoreFailed(let error):
            return ["error": error]

        case .effectCatalogViewed:
            return nil

        case .effectScrolled(let effectId, let effectName, let position):
            return ["effect_id": effectId, "effect_name": effectName, "position": position]

        case .effectDetailOpened(let effectId, let effectName):
            return ["effect_id": effectId, "effect_name": effectName]

        case .photoSelected(let source):
            return ["source": source.rawValue]

        case .generationStarted(let effectId, let effectName, let isCustom):
            var params: [String: Any] = ["is_custom": isCustom]
            if let id = effectId { params["effect_id"] = id }
            if let name = effectName { params["effect_name"] = name }
            return params

        case .generationPollingStarted(let generationId):
            return ["generation_id": generationId]

        case .generationPollingResumed(let generationId, let pollCount):
            return ["generation_id": generationId, "poll_count": pollCount]

        case .generationCompleted(let generationId, let durationSeconds, let effectName):
            var params: [String: Any] = ["generation_id": generationId, "duration_seconds": durationSeconds]
            if let name = effectName { params["effect_name"] = name }
            return params

        case .generationFailed(let effectId, let effectName, let error, let errorCategory):
            var params: [String: Any] = ["error": error, "error_category": errorCategory.rawValue]
            if let id = effectId { params["effect_id"] = id }
            if let name = effectName { params["effect_name"] = name }
            return params

        case .generationBackgrounded(let generationId):
            return ["generation_id": generationId]

        case .generationExpired(let generationId):
            return ["generation_id": generationId]

        case .resultViewed(let effectName):
            if let name = effectName { return ["effect_name": name] }
            return nil

        case .videoSaved(let effectName):
            if let name = effectName { return ["effect_name": name] }
            return nil

        case .videoSaveFailed(let error):
            return ["error": error]

        case .videoShared(let effectName):
            if let name = effectName { return ["effect_name": name] }
            return nil

        case .createAnotherTapped:
            return nil

        case .historyViewed:
            return nil

        case .historyItemViewed(let generationId), .historyItemDeleted(let generationId):
            return ["generation_id": generationId]

        case .createSimilarTapped(let templateId):
            if let id = templateId { return ["template_id": id] }
            return nil

        case .profileViewed:
            return nil

        case .settingsTapped(let setting):
            return ["setting": setting]

        case .rateAppTapped, .contactSupportTapped:
            return nil

        case .tabSwitched(let tab):
            return ["tab": tab]

        case .aiConsentShown, .aiConsentAccepted:
            return nil

        case .photoTipsShown(let effectName):
            return ["effect_name": effectName]

        case .generationBlockedByActiveJob:
            return nil

        case .subscriptionValidated(let isValid, let plan):
            var params: [String: Any] = ["is_valid": isValid]
            if let plan = plan { params["plan"] = plan }
            return params

        case .subscriptionExpired:
            return nil
        }
    }
}
