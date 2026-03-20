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
            title: "Bring Photos\nTo Life",
            subtitle: "",
            videoName: "onboarding_1",
            icon: ""
        ),
        OnboardingPage(
            id: 1,
            title: "Choose Your\nEffect",
            subtitle: "",
            videoName: "onboarding_2",
            icon: ""
        ),
        OnboardingPage(
            id: 2,
            title: "Share\nEverywhere",
            subtitle: "",
            videoName: "onboarding_3",
            icon: ""
        )
    ]
}
