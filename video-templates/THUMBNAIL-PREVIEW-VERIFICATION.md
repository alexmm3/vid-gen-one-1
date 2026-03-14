# Template Thumbnail & Preview System — Verification & Setup

## How It Works (Verified)

### Two lightweight assets per template

| Asset | Storage | Purpose | Used by |
|-------|---------|---------|---------|
| **Thumbnail** (JPEG) | Supabase Storage `reference-videos` (e.g. `thumbnails/`) | Instant static image under the video player | `VideoThumbnailView`, `ImageCacheManager.prefetch()` |
| **Preview** (low-res MP4) | Supabase Storage `reference-videos` (e.g. `previews/`) | Looping video in template cards | `LoopingRemoteVideoPlayer` in CategorySection & TemplateGridScreen |

### Flow

1. **Template cards** (horizontal scroll + grid) use a `ZStack`:
   - **Bottom**: `VideoThumbnailView(thumbnailUrl: fullThumbnailUrl, videoUrl: fullPreviewUrl)` — loads JPEG from Supabase or extracts first frame from video if `thumbnail_url` is null
   - **Top**: `LoopingRemoteVideoPlayer(url: fullPreviewUrl)` — plays low-res preview (or falls back to full video if `preview_url` is null)

2. **Fallbacks** (in template model):
   - `fullThumbnailUrl` nil → `VideoThumbnailView` extracts first frame from `fullPreviewUrl` (slower)
   - `fullPreviewUrl` nil → falls back to `fullVideoUrl` (full-res, heavier bandwidth)

3. **Prefetch**: At app launch, `ImageCacheManager.prefetch(urls: thumbnailURLs)` preloads all template thumbnails.

---

## Bundled vs Template Videos

| Video | Type | Needs thumbnail/preview? |
|-------|------|--------------------------|
| `onboarding_1.mp4`, `onboarding_2.mp4`, `onboarding_3.mp4` | **Bundled** (app assets) | **No** — loaded from bundle |
| `paywall_bg.mp4` | **Bundled** | **No** |
| Templates in `reference_videos` | **Remote** (Supabase Storage) | **Yes** — for template gallery cards |

The onboarding and paywall videos are bundled. They do not use the thumbnail/preview system.

---

## Supabase Storage layout

Use the `reference-videos` bucket:

- **Thumbnails**: e.g. `thumbnails/{template-uuid}.jpg` or `thumbnails/{name}.jpg`
- **Previews**: e.g. `previews/preview_{name}.mp4`
- **Full videos**: e.g. `templates/{timestamp}_{name}.mp4`

Public URL form: `https://<project-ref>.supabase.co/storage/v1/object/public/reference-videos/<path>`.

### Update the database

Update the template row in `reference_videos` with the public URLs from Supabase Storage:

```sql
UPDATE reference_videos
SET
  thumbnail_url = 'https://<project-ref>.supabase.co/storage/v1/object/public/reference-videos/thumbnails/{filename}.jpg',
  preview_url = 'https://<project-ref>.supabase.co/storage/v1/object/public/reference-videos/previews/preview_{filename}.mp4'
WHERE name ILIKE '%your-template%';
```

Or via Supabase REST/Admin:

```json
{
  "thumbnail_url": "https://<project-ref>.supabase.co/storage/v1/object/public/reference-videos/thumbnails/{filename}.jpg",
  "preview_url": "https://<project-ref>.supabase.co/storage/v1/object/public/reference-videos/previews/preview_{filename}.mp4"
}
```

---

## Files in `video-templates/`

- Thumbnail and preview assets can be prepared locally, then uploaded to Supabase Storage (`reference-videos` bucket) and the URLs set on the template record.
