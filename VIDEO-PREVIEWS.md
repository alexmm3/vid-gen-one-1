# Video Preview System

## Overview

The app uses **lightweight preview videos** for template thumbnail cards on the main screen
and grid views. This dramatically reduces bandwidth and improves scroll performance by
avoiding the need to stream full-resolution template videos just for small card previews.

The **original full-resolution videos** are always used for:
- AI generation (sent to the video generation API as reference)
- Full-screen playback in the template detail view

Preview videos are **never** used for AI generation.

## Architecture

### Database

The `reference_videos` table has two video URL columns:

| Column | Purpose | Used by |
|---|---|---|
| `video_url` | Full-resolution original video | AI generation, detail view, fullscreen playback |
| `preview_url` | Low-res preview for thumbnails | Main screen cards, grid view cards |

### Supabase Storage Layout

Use the **reference-videos** bucket:

```
reference-videos/
├── templates/            ← Full-resolution originals
│   ├── 1770667927122_apt2.mp4
│   ├── 1770668058086_apt.mp4
│   └── ...
├── previews/             ← Low-res previews
│   ├── preview_1770667927122_apt2.mp4
│   ├── preview_1770668058086_apt.mp4
│   └── ...
└── thumbnails/           ← Optional static thumbnails
    └── ...
```

### Naming Convention

For an original video at:
```
templates/{timestamp}_{name}.mp4
```

The preview can be at:
```
previews/preview_{timestamp}_{name}.mp4
```

Or simply `previews/preview_{name}.mp4`. Prefix `preview_` and place in the `previews/` folder.

### iOS Fallback

In the template model, the `fullPreviewUrl` computed property automatically falls back
to the full video URL if no preview is available:

```swift
var fullPreviewUrl: URL? {
    if let preview = previewUrl, let url = URL(string: preview) {
        return url
    }
    return fullVideoUrl  // fallback to original
}
```

This means new templates work immediately even without a preview — they'll just use the
full video until a preview is uploaded.

## Current Specs

| Property | Value |
|---|---|
| Resolution | 480px wide (height auto, maintains aspect ratio) |
| Video codec | H.264 (libx264) — hardware-decoded on iOS |
| Bitrate | 500kbps average, 700kbps max |
| Audio | Stripped (cards are always muted) |
| Container | MP4 with faststart (moov atom at beginning for instant streaming) |
| Avg file size | ~1 MB per preview |

## How to Create a Preview for a New Video

### 1. Resize with FFmpeg

```bash
ffmpeg -i original.mp4 \
  -vf "scale=480:-2" \
  -c:v libx264 \
  -preset medium \
  -b:v 500k \
  -maxrate 700k \
  -bufsize 1000k \
  -an \
  -movflags +faststart \
  preview_original.mp4
```

Flags explained:
- `-vf "scale=480:-2"` — Scale to 480px wide, auto height (divisible by 2)
- `-c:v libx264` — H.264 codec for universal iOS hardware decoding
- `-b:v 500k -maxrate 700k -bufsize 1000k` — Target 500kbps with burst headroom
- `-an` — Strip audio (cards are always muted)
- `-movflags +faststart` — Move moov atom to front for instant streaming

### 2. Upload to Supabase Storage

Upload the preview file to the `reference-videos` bucket under `previews/preview_{original_filename}.mp4`. You can do this through:
- Supabase Dashboard → Storage → reference-videos → upload to `previews/`
- The `admin-templates` edge function with `action=upload` and `folder=previews`

### 3. Update the Database

Set `preview_url` on the template record via the admin panel or the `admin-templates`
edge function (`action=update`). Use the public URL from Supabase Storage:

```
https://<project-ref>.supabase.co/storage/v1/object/public/reference-videos/previews/preview_{filename}.mp4
```

## iOS Code References

| File | What it does |
|------|----------------|
| Template model (e.g. `VideoTemplate.swift`) | `previewUrl` field and `fullPreviewUrl` fallback |
| `CategorySection.swift` | Main screen horizontal cards — uses `fullPreviewUrl` |
| `TemplateGridScreen.swift` | Grid view cards — uses `fullPreviewUrl` |
| Detail view | Uses `videoUrl` (full video, NOT preview) |
| Generation flow | Uses `videoUrl` (full video, NOT preview) |
