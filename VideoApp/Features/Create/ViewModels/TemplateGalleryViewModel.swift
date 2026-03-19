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
        Analytics.track(.templateGalleryViewed)
    }
    
    /// Refresh templates
    func refresh() async {
        await templateService.refresh()
    }
    
    /// Handle template selection
    func selectTemplate(_ template: VideoTemplate) {
        Analytics.track(.templateSelected(
            templateId: template.id.uuidString,
            templateName: template.name
        ))
    }
    
    /// Handle custom video selection
    func selectCustomVideo(url: URL) {
        selectedCustomVideoUrl = url
        Analytics.track(.customVideoSelected)
    }
    
    /// Clear custom video selection
    func clearCustomVideo() {
        selectedCustomVideoUrl = nil
    }
}
