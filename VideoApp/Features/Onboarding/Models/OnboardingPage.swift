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
            title: "Bring Photos\nTo Life With AI",
            subtitle: "Upload a single photo and generate stunning videos",
            videoName: "onboarding_1", // Bundle video name
            icon: "person.fill.viewfinder"
        ),
        OnboardingPage(
            id: 1,
            title: "Choose Your\nEffect",
            subtitle: "Pick an AI effect and customize it with your prompt",
            videoName: "onboarding_2",
            icon: "wand.and.stars"
        ),
        OnboardingPage(
            id: 2,
            title: "Share\nEverywhere",
            subtitle: "Generate videos in minutes. Perfect for TikTok, Reels, and more",
            videoName: "onboarding_3",
            icon: "square.and.arrow.up"
        )
    ]
}
