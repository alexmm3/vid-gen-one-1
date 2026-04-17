//
//  TemplateGalleryViewModel.swift
//  AIVideo
//
//  ViewModel for template gallery
//

import Foundation
import SwiftUI

@MainActor
final class TemplateGalleryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var templates: [VideoTemplate] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedCustomVideoUrl: URL?
    
    // MARK: - Private
    private let templateService = TemplateService.shared
    
    // MARK: - Initialization
    
    init() {
        // Observe template service updates
        templateService.$templates
            .assign(to: &$templates)
        
        templateService.$isLoading
            .assign(to: &$isLoading)
        
        templateService.$error
            .assign(to: &$error)
    }
    
    // MARK: - Public Methods
    
    /// Load templates from Supabase
    func loadTemplates() async {
        await templateService.fetchTemplates()
        Analytics.track(.effectCatalogViewed)
    }

    /// Refresh templates
    func refresh() async {
        await templateService.refresh()
    }

    /// Handle template selection
    func selectTemplate(_ template: VideoTemplate) {
        Analytics.track(.effectDetailOpened(
            effectId: template.id.uuidString,
            effectName: template.name
        ))
    }

    /// Handle custom video selection
    func selectCustomVideo(url: URL) {
        selectedCustomVideoUrl = url
    }
    
    /// Clear custom video selection
    func clearCustomVideo() {
        selectedCustomVideoUrl = nil
    }
}
