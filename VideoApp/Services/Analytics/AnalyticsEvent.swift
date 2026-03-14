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
    case purchaseStarted(plan: SubscriptionPlan)
    case purchaseCompleted(plan: SubscriptionPlan, transactionId: String)
    case purchaseFailed(plan: SubscriptionPlan, error: String)
    case restoreStarted
    case restoreCompleted
    case restoreFailed(error: String)
    
    // MARK: - Template Gallery
    case templateGalleryViewed
    case templateSelected(templateId: String, templateName: String)
    case customVideoSelected
    
    // MARK: - Generation
    case photoSelected(source: PhotoSource)
    case generationStarted(templateId: String?, isCustom: Bool)
    case generationPollingStarted(generationId: String)
    case generationPollingResumed(generationId: String, pollCount: Int)
    case generationCompleted(generationId: String, durationSeconds: Int)
    case generationFailed(error: String)
    case generationBackgrounded(generationId: String)
    case generationExpired(generationId: String)
    
    // MARK: - Result
    case resultViewed
    case videoSaved
    case videoShared
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
    
    // MARK: - Enums
    
    enum PaywallSource: String {
        case onboarding
        case generateBlocked = "generate_blocked"
        case profile
    }
    
    enum SubscriptionPlan: String {
        case weekly
        case yearly
    }
    
    enum PhotoSource: String {
        case camera
        case gallery
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
        case .purchaseStarted: return "purchase_started"
        case .purchaseCompleted: return "purchase_completed"
        case .purchaseFailed: return "purchase_failed"
        case .restoreStarted: return "restore_started"
        case .restoreCompleted: return "restore_completed"
        case .restoreFailed: return "restore_failed"
        case .templateGalleryViewed: return "template_gallery_viewed"
        case .templateSelected: return "template_selected"
        case .customVideoSelected: return "custom_video_selected"
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
            
        case .purchaseStarted(let plan):
            return ["plan": plan.rawValue]
            
        case .purchaseCompleted(let plan, let transactionId):
            return ["plan": plan.rawValue, "transaction_id": transactionId]
            
        case .purchaseFailed(let plan, let error):
            return ["plan": plan.rawValue, "error": error]
            
        case .restoreStarted, .restoreCompleted:
            return nil
            
        case .restoreFailed(let error):
            return ["error": error]
            
        case .templateGalleryViewed:
            return nil
            
        case .templateSelected(let templateId, let templateName):
            return ["template_id": templateId, "template_name": templateName]
            
        case .customVideoSelected:
            return nil
            
        case .photoSelected(let source):
            return ["source": source.rawValue]
            
        case .generationStarted(let templateId, let isCustom):
            var params: [String: Any] = ["is_custom": isCustom]
            if let id = templateId {
                params["template_id"] = id
            }
            return params
            
        case .generationPollingStarted(let generationId):
            return ["generation_id": generationId]
            
        case .generationPollingResumed(let generationId, let pollCount):
            return ["generation_id": generationId, "poll_count": pollCount]
            
        case .generationCompleted(let generationId, let durationSeconds):
            return ["generation_id": generationId, "duration_seconds": durationSeconds]
            
        case .generationFailed(let error):
            return ["error": error]
            
        case .generationBackgrounded(let generationId):
            return ["generation_id": generationId]
            
        case .generationExpired(let generationId):
            return ["generation_id": generationId]
            
        case .resultViewed, .videoSaved, .videoShared, .createAnotherTapped:
            return nil
            
        case .historyViewed:
            return nil
            
        case .historyItemViewed(let generationId), .historyItemDeleted(let generationId):
            return ["generation_id": generationId]
            
        case .createSimilarTapped(let templateId):
            if let id = templateId {
                return ["template_id": id]
            }
            return nil
            
        case .profileViewed:
            return nil
            
        case .settingsTapped(let setting):
            return ["setting": setting]
            
        case .rateAppTapped, .contactSupportTapped:
            return nil
        }
    }
}
