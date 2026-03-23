//
//  OnboardingPage.swift
//  AIVideo
//
//  Model for onboarding page content
//

import Foundation

struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let videoName: String?
    let icon: String
    
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Effects No One\nHas Seen",
            subtitle: "",
            videoName: "onboarding_1",
            icon: ""
        ),
        OnboardingPage(
            id: 1,
            title: "One Tap.\nMind-Blown.",
            subtitle: "",
            videoName: "onboarding_2",
            icon: ""
        ),
        OnboardingPage(
            id: 2,
            title: "Make Them\nAsk How",
            subtitle: "",
            videoName: "onboarding_3",
            icon: ""
        )
    ]
}
