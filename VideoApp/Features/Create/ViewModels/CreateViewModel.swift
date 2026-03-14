//
//  CreateViewModel.swift
//  AIVideo
//
//  ViewModel for the main Create screen — effects catalog (effect categories + effects)
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class CreateViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var allEffects: [Effect] = []
    @Published var categories: [VideoCategory] = []
    @Published var effectsByCategory: [UUID: [Effect]] = [:]
    @Published var isLoadingEffects = false

    @Published var error: Error?

    // MARK: - Computed Properties

    var nonEmptyCategories: [VideoCategory] {
        categories.filter { category in
            !(effectsByCategory[category.id]?.isEmpty ?? true)
        }
    }

    // MARK: - Private
    private let effectService = EffectService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        effectService.$allEffects
            .assign(to: &$allEffects)
        effectService.$categories
            .assign(to: &$categories)
        effectService.$effectsByCategory
            .assign(to: &$effectsByCategory)
        effectService.$isLoading
            .assign(to: &$isLoadingEffects)
    }

    // MARK: - Loading Methods

    /// Load effect catalog (categories + effects)
    func loadAll() async {
        await effectService.fetchAll()
        Analytics.track(.templateGalleryViewed)
    }

    /// Force refresh effect catalog
    func refresh() async {
        await effectService.forceRefresh()
    }

    /// Effects for a given category
    func effects(for category: VideoCategory) -> [Effect] {
        effectService.effects(for: category)
    }
}
