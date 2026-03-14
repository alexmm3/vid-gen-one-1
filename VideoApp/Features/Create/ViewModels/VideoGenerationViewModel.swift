//
//  VideoGenerationViewModel.swift
//  AIVideo
//
//  ViewModel for the video generation preparation screen
//

import Foundation
import SwiftUI

@MainActor
final class VideoGenerationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedPhoto: UIImage?
    @Published private(set) var hasSavedPhoto = false
    
    // MARK: - Private
    private static let savedPhotoKey = "lastUsedCharacterPhoto"
    private static let photoDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private static let savedPhotoPath = photoDirectory.appendingPathComponent("last_character_photo.jpg")
    
    // MARK: - Public Methods
    
    /// Load previously saved photo
    func loadSavedPhoto() {
        if let savedPhoto = loadSavedPhotoFromDisk() {
            selectedPhoto = savedPhoto
            hasSavedPhoto = true
        }
    }
    
    /// Set photo and save it
    func setPhoto(_ photo: UIImage?) {
        selectedPhoto = photo
        
        if let photo = photo {
            savePhoto(photo)
            hasSavedPhoto = true
            Analytics.track(.photoSelected(source: .gallery))
        }
    }
    
    /// Clear selected photo (but keep saved)
    func clearPhoto() {
        selectedPhoto = nil
    }
    
    /// Delete saved photo permanently
    func deleteSavedPhoto() {
        selectedPhoto = nil
        hasSavedPhoto = false
        
        try? FileManager.default.removeItem(at: Self.savedPhotoPath)
        UserDefaults.standard.removeObject(forKey: Self.savedPhotoKey)
    }
    
    // MARK: - Private Methods
    
    private func savePhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        do {
            try data.write(to: Self.savedPhotoPath)
            UserDefaults.standard.set(true, forKey: Self.savedPhotoKey)
            print("✅ VideoGenerationViewModel: Photo saved")
        } catch {
            print("❌ VideoGenerationViewModel: Failed to save photo - \(error)")
        }
    }
    
    private func loadSavedPhotoFromDisk() -> UIImage? {
        guard UserDefaults.standard.bool(forKey: Self.savedPhotoKey) else { return nil }
        
        do {
            let data = try Data(contentsOf: Self.savedPhotoPath)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
