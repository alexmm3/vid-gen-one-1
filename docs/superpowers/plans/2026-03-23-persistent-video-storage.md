# Persistent Local Video Storage — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a generated video is downloaded for the first time, persist it permanently on the device so subsequent views never hit the backend.

**Architecture:** Add a `VideoPersistenceManager` that copies downloaded videos from the volatile `Caches/` disk cache to permanent `Documents/GeneratedVideos/`. Extend `LocalGeneration` with an optional `localVideoPath` field. All video consumers (player, save-to-photos, share) resolve through `effectiveVideoUrl` which returns the local file URL when available, falling back to the remote URL.

**Tech Stack:** Swift, FileManager, AVFoundation, Codable (UserDefaults persistence)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `VideoApp/Services/Cache/VideoPersistenceManager.swift` | **Create** | Copy video from cache/network → `Documents/GeneratedVideos/`, provide local URL lookup |
| `VideoApp/Models/Generation.swift` | **Modify** | Add `localVideoPath: String?` to `LocalGeneration`, add `effectiveVideoUrl` computed property |
| `VideoApp/Services/Storage/GenerationHistoryService.swift` | **Modify** | Add `updateLocalVideoPath`, update `saveGeneration`/`mergeRemoteGenerations` init calls, add cleanup on delete |
| `VideoApp/Services/Storage/ActiveGenerationManager.swift` | **Modify** | Trigger persist after generation completes |
| `VideoApp/Features/History/HistoryItemActionHandler.swift` | **Modify** | Use local file for save/share when available |
| `VideoApp/Features/History/Views/HistoryDetailView.swift` | **Modify** | Use `effectiveVideoUrl` for playback + lazy migration |
| `VideoApp/Features/History/Views/HistoryItemCard.swift` | **Modify** | Use `effectiveVideoUrl` for grid card playback |
| `VideoApp/Features/History/Views/HistoryListView.swift` | **Modify** | Use `effectiveVideoUrl` in context menu guards |

---

## Chunk 1: Core persistence layer

### Task 1: Create VideoPersistenceManager

**Files:**
- Create: `VideoApp/Services/Cache/VideoPersistenceManager.swift`

- [ ] **Step 1: Create VideoPersistenceManager**

```swift
//
//  VideoPersistenceManager.swift
//  AIVideo
//
//  Permanently stores generated videos in Documents/ so they survive
//  cache eviction and never need to be re-downloaded from the backend.
//

import Foundation

final class VideoPersistenceManager {
    static let shared = VideoPersistenceManager()

    private let fileManager = FileManager.default
    private let directory: URL
    /// Guards against duplicate concurrent persist calls for the same generation
    private var activePersists = Set<String>()
    private let lock = NSLock()

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("GeneratedVideos", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Local file URL for a generation (may or may not exist yet)
    func localURL(for generationId: String) -> URL {
        directory.appendingPathComponent("\(generationId).mp4")
    }

    /// Check if a video is already persisted locally
    func isPersisted(generationId: String) -> Bool {
        fileManager.fileExists(atPath: localURL(for: generationId).path)
    }

    /// Persist video data to Documents/GeneratedVideos/{generationId}.mp4
    /// Returns the local file path on success, nil on failure.
    /// MUST be called on a background thread — performs synchronous file I/O.
    private func persist(videoData: Data, generationId: String) -> String? {
        let url = localURL(for: generationId)
        do {
            try videoData.write(to: url, options: .atomic)
            // Exclude from iCloud backup to avoid eating user's iCloud quota
            var resourceURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try resourceURL.setResourceValues(resourceValues)
            print("💾 VideoPersistenceManager: Persisted \(generationId) (\(videoData.count / 1024)KB)")
            return url.lastPathComponent
        } catch {
            print("❌ VideoPersistenceManager: Failed to persist \(generationId): \(error)")
            return nil
        }
    }

    /// Persist video from its remote URL — downloads if not in cache.
    /// All file I/O runs off the main thread. Calls completion on main thread.
    func persistFromRemote(
        remoteUrlString: String,
        generationId: String,
        completion: @escaping (String?) -> Void
    ) {
        // Already persisted?
        if isPersisted(generationId: generationId) {
            DispatchQueue.main.async {
                completion(self.localURL(for: generationId).lastPathComponent)
            }
            return
        }

        // Dedup: skip if already persisting this generation
        lock.lock()
        guard !activePersists.contains(generationId) else {
            lock.unlock()
            return
        }
        activePersists.insert(generationId)
        lock.unlock()

        guard let remoteUrl = URL(string: remoteUrlString) else {
            removePersistGuard(generationId)
            DispatchQueue.main.async { completion(nil) }
            return
        }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.removePersistGuard(generationId) }

            let data: Data

            // Try disk cache first (read off main thread)
            if let cachedURL = VideoCacheManager.shared.cachedURL(for: remoteUrl),
               let cachedData = try? Data(contentsOf: cachedURL) {
                data = cachedData
            } else {
                // Download from network
                do {
                    let (downloaded, response) = try await URLSession.shared.data(from: remoteUrl)
                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          downloaded.count > 1000 else {
                        await MainActor.run { completion(nil) }
                        return
                    }
                    data = downloaded
                } catch {
                    print("❌ VideoPersistenceManager: Download failed for \(generationId): \(error)")
                    await MainActor.run { completion(nil) }
                    return
                }
            }

            let path = self.persist(videoData: data, generationId: generationId)
            await MainActor.run { completion(path) }
        }
    }

    /// Delete a persisted video
    func delete(generationId: String) {
        let url = localURL(for: generationId)
        try? fileManager.removeItem(at: url)
    }

    private func removePersistGuard(_ id: String) {
        lock.lock()
        activePersists.remove(id)
        lock.unlock()
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Open `VideoApp.xcodeproj/project.pbxproj` and add `VideoPersistenceManager.swift` to the same group/target as `VideoCacheManager.swift`. Alternatively, open Xcode, right-click the `Services/Cache` group, and "Add Files to VideoApp".

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme VideoApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VideoApp/Services/Cache/VideoPersistenceManager.swift VideoApp.xcodeproj/project.pbxproj
git commit -m "feat: add VideoPersistenceManager for permanent local video storage"
```

---

### Task 2: Extend LocalGeneration with localVideoPath

**Files:**
- Modify: `VideoApp/Models/Generation.swift:49-73`

- [ ] **Step 1: Add localVideoPath field and effectiveVideoUrl computed property**

Add `localVideoPath: String?` to `LocalGeneration`. This field stores the filename (e.g. `"abc123.mp4"`) relative to `Documents/GeneratedVideos/`. Add a computed property `effectiveVideoUrl` that returns the local `file://` URL when the file exists, or falls back to the remote URL.

```swift
struct LocalGeneration: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let templateName: String
    let templateId: String?
    let inputImageUrl: String
    let outputVideoUrl: String?
    let createdAt: Date
    let isCustomTemplate: Bool
    var localVideoPath: String?  // filename in Documents/GeneratedVideos/

    // ... existing computed properties (displayName, hasResult, fullOutputUrl) ...

    /// URL to use for playback — prefers local file, falls back to remote
    var effectiveVideoUrl: URL? {
        if localVideoPath != nil {
            let localURL = VideoPersistenceManager.shared.localURL(for: id)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }
        return fullOutputUrl
    }
}
```

**Codable safety:** `localVideoPath` is `Optional` so existing UserDefaults JSON without this key decodes correctly — Swift's auto-synthesized `Codable` treats missing keys as `nil` for optionals.

- [ ] **Step 2: Update ALL LocalGeneration initializer call sites**

Since all other properties are `let` but `localVideoPath` is `var`, the auto-synthesized memberwise init requires it. Update these files to pass `localVideoPath: nil`:

**`GenerationHistoryService.swift` — `saveGeneration()` (~line 38-46):**
```swift
let generation = LocalGeneration(
    id: UUID().uuidString,
    templateName: templateName,
    templateId: templateId,
    inputImageUrl: inputImageUrl,
    outputVideoUrl: outputVideoUrl,
    createdAt: Date(),
    isCustomTemplate: isCustomTemplate,
    localVideoPath: nil  // NEW — will be set after persist
)
```

**`GenerationHistoryService.swift` — `mergeRemoteGenerations()` (~line 96-104):**
```swift
let local = LocalGeneration(
    id: UUID().uuidString,
    templateName: displayName,
    templateId: remote.effectId,
    inputImageUrl: remote.inputImageUrl ?? "",
    outputVideoUrl: outputUrl,
    createdAt: parseISO8601(remote.createdAt) ?? Date(),
    isCustomTemplate: remote.effectId == nil && remote.referenceVideoUrl == nil,
    localVideoPath: nil  // NEW
)
```

**`Generation.swift` — sample data (~line 78-116):**
Add `localVideoPath: nil` to all `LocalGeneration(...)` calls in `sample` and `samples`.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme VideoApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VideoApp/Models/Generation.swift VideoApp/Services/Storage/GenerationHistoryService.swift
git commit -m "feat: add localVideoPath to LocalGeneration for persistent storage"
```

---

### Task 3: Add updateLocalVideoPath to GenerationHistoryService

**Files:**
- Modify: `VideoApp/Services/Storage/GenerationHistoryService.swift`

- [ ] **Step 1: Add method to update localVideoPath for a specific generation**

Add after `deleteGeneration(_:)` (~line 67):

```swift
/// Update the local video file path for a generation
func updateLocalVideoPath(_ path: String, forGenerationId id: String) {
    guard let index = generations.firstIndex(where: { $0.id == id }) else { return }
    generations[index].localVideoPath = path
    persistHistory()
}
```

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Services/Storage/GenerationHistoryService.swift
git commit -m "feat: add updateLocalVideoPath to GenerationHistoryService"
```

---

## Chunk 2: Integration with generation flow and UI

### Task 4: Trigger persist when generation completes

**Files:**
- Modify: `VideoApp/Services/Storage/ActiveGenerationManager.swift:252-289`

- [ ] **Step 1: Add video persistence call in completeGeneration()**

In `ActiveGenerationManager.completeGeneration(outputUrl:)`, after `historyService.saveGeneration(...)` (~line 256-262), add:

```swift
// Persist video locally so it never needs to be re-downloaded
if let savedGeneration = historyService.generations.first {
    VideoPersistenceManager.shared.persistFromRemote(
        remoteUrlString: outputUrl,
        generationId: savedGeneration.id
    ) { [weak historyService] localPath in
        guard let localPath, let historyService else { return }
        historyService.updateLocalVideoPath(localPath, forGenerationId: savedGeneration.id)
        print("💾 Video persisted locally for generation \(savedGeneration.id)")
    }
}
```

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Services/Storage/ActiveGenerationManager.swift
git commit -m "feat: persist video locally when generation completes"
```

---

### Task 5: Use local files in HistoryItemActionHandler

**Files:**
- Modify: `VideoApp/Features/History/HistoryItemActionHandler.swift`

- [ ] **Step 1: Update saveToPhotos to prefer local file**

Replace the current `saveToPhotos` implementation:

```swift
static func saveToPhotos(generation: LocalGeneration) async throws {
    // Prefer local file
    if let localUrl = generation.effectiveVideoUrl, localUrl.isFileURL {
        let data = try Data(contentsOf: localUrl)
        try await saveVideoToPhotoLibrary(data: data)
        return
    }
    // Fall back to network download
    guard let urlString = generation.outputVideoUrl else {
        throw StorageServiceError.downloadFailed
    }
    let data = try await StorageService.shared.downloadVideo(from: urlString)
    try await saveVideoToPhotoLibrary(data: data)
}
```

- [ ] **Step 2: Update prepareShareFile to prefer local file**

```swift
static func prepareShareFile(for generation: LocalGeneration) async throws -> URL {
    let fileName = sanitizedFileName(from: generation.displayName)
    let tempUrl = FileManager.default.temporaryDirectory
        .appendingPathComponent(fileName)
        .appendingPathExtension("mp4")

    if FileManager.default.fileExists(atPath: tempUrl.path) {
        try? FileManager.default.removeItem(at: tempUrl)
    }

    // Prefer local file — just copy instead of downloading
    if let localUrl = generation.effectiveVideoUrl, localUrl.isFileURL {
        try FileManager.default.copyItem(at: localUrl, to: tempUrl)
        return tempUrl
    }

    // Fall back to network download
    guard let urlString = generation.outputVideoUrl else {
        throw StorageServiceError.downloadFailed
    }
    let data = try await StorageService.shared.downloadVideo(from: urlString)
    try data.write(to: tempUrl)
    return tempUrl
}
```

- [ ] **Step 3: Build to verify**

- [ ] **Step 4: Commit**

```bash
git add VideoApp/Features/History/HistoryItemActionHandler.swift
git commit -m "feat: prefer local video files for save/share actions"
```

---

### Task 6: Use effectiveVideoUrl in HistoryDetailView

**Files:**
- Modify: `VideoApp/Features/History/Views/HistoryDetailView.swift`

- [ ] **Step 1: Replace fullOutputUrl with effectiveVideoUrl**

Update these references:

**`hasPlayableVideo` (~line 78):**
```swift
private var hasPlayableVideo: Bool { generation.effectiveVideoUrl != nil }
```

**`videoPlayerContent` (~line 198):**
```swift
if let url = generation.effectiveVideoUrl {
```

**`saveToPhotos()` (~line 458):**
```swift
guard generation.effectiveVideoUrl != nil, !isSaving else { return }
```

**`shareVideo()` (~line 477):**
```swift
guard generation.effectiveVideoUrl != nil, !isSharing else { return }
```

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Features/History/Views/HistoryDetailView.swift
git commit -m "feat: use local video URL in detail view when available"
```

---

### Task 7: Use effectiveVideoUrl in HistoryItemCard

**Files:**
- Modify: `VideoApp/Features/History/Views/HistoryItemCard.swift:19`

- [ ] **Step 1: Replace fullOutputUrl with effectiveVideoUrl in card**

```swift
// Line 19: change from:
if let url = generation.fullOutputUrl {
// to:
if let url = generation.effectiveVideoUrl {
```

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Features/History/Views/HistoryItemCard.swift
git commit -m "feat: use local video URL in history card when available"
```

---

### Task 8: Use effectiveVideoUrl in HistoryListView context menu

**Files:**
- Modify: `VideoApp/Features/History/Views/HistoryListView.swift`

- [ ] **Step 1: Replace fullOutputUrl with effectiveVideoUrl in context menu guards**

**Line 204:**
```swift
.disabled(generation.effectiveVideoUrl == nil || isSavingGenerationID != nil)
```

**Line 211:**
```swift
.disabled(generation.effectiveVideoUrl == nil || isSharingGenerationID != nil)
```

**Line 221:**
```swift
guard generation.effectiveVideoUrl != nil, isSavingGenerationID == nil else { return }
```

**Line 245:**
```swift
guard generation.effectiveVideoUrl != nil, isSharingGenerationID == nil else { return }
```

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Features/History/Views/HistoryListView.swift
git commit -m "feat: use local video URL in history list context menu"
```

---

## Chunk 3: Lazy migration & cleanup

### Task 9: Lazy persist on first view of existing (pre-migration) videos

**Files:**
- Modify: `VideoApp/Features/History/Views/HistoryDetailView.swift`

- [ ] **Step 1: Add onAppear persistence trigger for videos without local path**

In `HistoryDetailView.onAppear` (~line 181), add lazy migration logic:

```swift
.onAppear {
    viewModel.trackItemViewed(generation)
    // Lazy-persist: if video has no local copy yet, persist it now
    if generation.localVideoPath == nil, let remoteUrl = generation.outputVideoUrl {
        VideoPersistenceManager.shared.persistFromRemote(
            remoteUrlString: remoteUrl,
            generationId: generation.id
        ) { localPath in
            guard let localPath else { return }
            GenerationHistoryService.shared.updateLocalVideoPath(
                localPath, forGenerationId: generation.id
            )
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        controlsReady = true
        showControls = true
        scheduleAutoHide()
    }
}
```

This means: existing users who upgrade will get their videos persisted one-by-one as they view them. No bulk migration needed.

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Features/History/Views/HistoryDetailView.swift
git commit -m "feat: lazy-persist videos on first view for migration"
```

---

### Task 10: Clean up local file when generation is deleted

**Files:**
- Modify: `VideoApp/Services/Storage/GenerationHistoryService.swift`

- [ ] **Step 1: Delete local video file when generation is removed from history**

Update `deleteGeneration(_:)`:

```swift
func deleteGeneration(_ id: String) {
    // Delete local video file if it exists
    VideoPersistenceManager.shared.delete(generationId: id)

    generations.removeAll { $0.id == id }
    persistHistory()
    print("✅ GenerationHistoryService: Deleted generation \(id)")
}
```

Update `clearHistory()`:

```swift
func clearHistory() {
    // Delete all local video files
    for generation in generations {
        VideoPersistenceManager.shared.delete(generationId: generation.id)
    }
    generations.removeAll()
    persistHistory()
    print("✅ GenerationHistoryService: Cleared all history")
}
```

- [ ] **Step 2: Build to verify**

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Services/Storage/GenerationHistoryService.swift
git commit -m "feat: delete local video files when generation is removed"
```

---

### Task 11: Final build verification

- [ ] **Step 1: Full clean build**

```bash
xcodebuild -scheme VideoApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' clean build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify no warnings related to changed files**

Scan build output for warnings in our modified files.

- [ ] **Step 3: Final commit if any fixups needed**
