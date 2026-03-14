# iOS Implementation Plan: Effects (Replace Motion Capture)

**Version:** 1.0  
**Scope:** iOS app only. Aligns with backend/effects from `01-high-level-plan.md` and `02-effect-pipeline-architecture.md`.  
**Principle:** Reuse maximum existing UI/UX; introduce new elements only where the effect flow genuinely requires them.

---

## 1. Summary: What Changes vs What Stays

| Area | Change |
|------|--------|
| **Create tab – catalog** | Data source: fetch **effects** (and effect_categories) instead of reference_videos. Same grid, same category sections, same card design. |
| **Create tab – detail/generation screen** | Replace **VideoGenerationView(template)** with **EffectGenerationView(effect)**. **No effect preview on this screen** — only the effect name at top (so user remembers which effect they’re on). Upper part: one or two photo pickers. Below photo view(s): small text field for prompt. Bottom: Generate button. |
| **Generation flow** | Call new **execute-effect** backend (effect_id + primary image + optional secondary image + user prompt). Keep **GeneratingView** and **ResultView** as-is; only wire them to the new generation record shape. |
| **History (My Videos)** | **No structural changes.** List, detail, pending card, sync, delete – unchanged. At most: when merging remote generations, use **effect name** (from API) instead of deriving from reference_video_url. Optional small copy/label tweaks (e.g. "Effect" instead of "Template" in one place) – cosmetic only. |
| **Rest of app** | **Unchanged:** Tab bar, Onboarding, Paywall, Profile, device auth, realtime, IAP, storage buckets. |

---

## 2. Data Layer: Effects Instead of Templates

### 2.1 New model: `Effect`

Mirror the Supabase `effects` table (see `03-admin-panel-brief.md`):

- `id: UUID`
- `name: String`
- `description: String?`
- `previewVideoUrl: String?` — looping preview (same role as template’s preview)
- `thumbnailUrl: String?`
- `categoryId: UUID?`
- `isActive: Bool`, `isPremium: Bool`, `sortOrder: Int`
- **`requiresSecondaryPhoto: Bool`** — drives second photo picker in UI
- `systemPromptTemplate: String` — backend-only; not needed for UI
- `provider: String`, `generationParams: [String: Any]` — backend-only; optional on client for display/debug

CodingKeys: snake_case to match API (`preview_video_url`, `thumbnail_url`, `requires_secondary_photo`, etc.).

### 2.2 New model: `EffectCategory`

Mirror `effect_categories`:

- `id`, `name`, `displayName`, `sortOrder`, `icon`, `isActive`

Can be the same shape as existing `VideoCategory` (same field names). Decision: either reuse `VideoCategory` for effect categories or add a dedicated `EffectCategory` and keep the two domains separate; recommend **reuse** if the schema is identical to avoid duplicate UI code.

### 2.3 Effect service and catalog fetching

- **New `EffectService`** (or extend a single “catalog” service): fetch active effects from `effects` (and optionally categories from `effect_categories`). Same pattern as current `CategoryService` + `TemplateService`: REST to Supabase tables, decode into `[Effect]` and optionally `[EffectCategory]`.
- **Category → effects grouping:** Either:
  - **Option A:** Backend exposes effects with `category_id`; client groups by category (like current `reference_video_categories` join).  
  - **Option B:** Single table `effects` with `category_id`; client fetches effects and groups by `category_id` using a separate `effect_categories` fetch.  
  Use the same structure as your Supabase schema (effects table has `category_id`; categories in `effect_categories`). So: fetch `effect_categories`, fetch `effects?is_active=eq.true&order=sort_order.asc`, then group effects by `category_id` for display.

### 2.4 Create screen data source

- **CreateViewModel** (and any observer it uses): instead of `CategoryService` providing `templatesByCategory` / `VideoTemplate`, switch to an **effect-aware** source:
  - Either **CategoryService** is refactored to fetch effects + effect_categories and expose `effectsByCategory: [UUID: [Effect]]` and `categories: [EffectCategory]` (or reuse `VideoCategory`),
  - Or a dedicated **EffectService** exposes `effectsByCategory` and categories, and CreateViewModel uses that.
- **CreateView** continues to drive the UI from “categories” and “items per category”; only the type of item changes from `VideoTemplate` to `Effect`.

---

## 3. Create Tab UI: Catalog (Same Patterns)

### 3.1 Main Create screen

- Keep: **CategorySection**-style horizontal sections, “Show All”, same spacing and styling.
- **Reuse:** Same card size, same layout: thumbnail/preview + title overlay. For effects, use **effect’s** `thumbnail_url` and/or `preview_video_url` (reuse existing `VideoThumbnailView` + `LoopingRemoteVideoPlayer` and `templateCard`-style layout).
- **Change:** Data binding: sections show **effects** per category; on select, pass **Effect** and navigate to **EffectGenerationView(effect)** instead of VideoGenerationView(template).
- **CategorySection** can be made generic over “catalog item” (Effect) so the same component renders effect cards (preview URL, name). Alternatively, introduce **EffectCardView** that mirrors **templateCard** but takes an `Effect`; visually identical.
- **“Your Videos” section:** For a strict effect-only V1, this section can be **hidden** (no more “upload your own motion video” as template). If you later support a “custom” effect that takes a user video, you can re-enable a similar block. **Recommendation:** hide for effect-only; document as optional in this plan.

### 3.2 “Show All” / grid screen

- Same as current **TemplateGridScreen** but for effects: list of effects in a 2-column grid, same card style. Tapping an effect opens **EffectGenerationView(effect)**. Title can stay e.g. category name or “All Effects”.

### 3.3 No new UI in catalog

- No new screens, no new navigation patterns. Only the type of entity (Effect) and the destination screen (EffectGenerationView) change.

---

## 4. Effect Generation Screen (Detail + Inputs)

This is the only place where the flow meaningfully differs from “template + one photo”.

### 4.1 Screen layout: no effect preview

- **Do not show effect preview video on this screen.** It saves space and keeps focus on inputs. The user already saw the effect card on the main Create screen; here they only need a reminder of which effect they chose.
- **New view: `EffectGenerationView(effect: Effect)`** replaces **VideoGenerationView(template)** in the navigation from Create.

**Layout (top to bottom):**

1. **Effect name only** — A single line (e.g. “Portrait Animation”, “Romantic Kiss”) so the user remembers which effect they’re on. No video, no preview.
2. **Photo picker(s)** — Upper part of the screen. First photo: same “Your Photo” / “Add Your Photo” card and same **PhotoSourceSheet** / **CameraImagePicker**. If `effect.requiresSecondaryPhoto == true`, a second identical block below (“Second Photo”).
3. **Prompt text field** — **Below** the photo view(s). One small **TextField** (or TextEditor): “Additional prompt (optional)” or “Describe any extra details…”. Same horizontal padding, 1–3 lines, same body font.
4. **Bottom bar** — Same **VideoButton** “Generate Video”. Same sheets (photo tips, AI consent, paywall, generation-in-progress alert). Same navigation: fullScreenCover for **GeneratingView**, navigationDestination for **ResultView**.

### 4.2 Reuse and minimal new UI

- **Reuse:** Photo card component, PhotoSourceSheet, CameraImagePicker, VideoButton, all sheets and navigation. **Do not** reuse or add a preview video block on this screen.
- **New/conditional:** (1) Second photo section when `requiresSecondaryPhoto` is true; (2) one text field for the prompt below the photo(s). Generate enabled when primary (and if required, secondary) photo is selected.

### 4.3 View model and generation API

- **EffectGenerationViewModel** (or extend GenerationViewModel):
  - State: primary image, optional second image, optional text prompt.
  - Action: “Generate”:
    - Same guards: AI consent, subscription, “one active generation” (ActiveGenerationManager).
    - Upload primary image (reuse **StorageService.uploadPortrait**); if `requiresSecondaryPhoto`, upload second image (reuse same or a similar upload method; backend may expect a second URL in the execute-effect payload).
    - Call **new** API: **execute-effect** with `effect_id`, primary image URL, optional second image URL, optional `user_prompt` string.
- **GenerationService:** add method e.g. `executeEffect(effectId: String, primaryImageUrl: String, secondaryImageUrl: String?, userPrompt: String?) async throws -> GenerationJob`. Request body matches backend contract (effect_id, init_image_url, optional secondary_image_url, user_prompt).
- **ActiveGenerationManager** and **GenerationViewModel** (or equivalent): when starting a generation from an effect, pass **effect id and effect name** instead of template id and template name, so pending state and history can show the effect name. Backend will return a generation row with `effect_id`; polling/completion stay the same (generation_id, status, output_video_url).

### 4.4 GeneratingView and ResultView

- **GeneratingView:** No changes. It already shows progress and “can dismiss” once submitted; it doesn’t care whether the job was template-based or effect-based.
- **ResultView:** No changes. It takes `videoUrl` and a display name (e.g. effect name); same Save/Share behavior. Call site: pass `effect.name` (or equivalent) as the “template name” argument so the result screen title makes sense.

---

## 5. History (My Videos): No Structural Changes

- **HistoryListView**, **HistoryItemCard**, **HistoryDetailView**: keep as-is. They already use **LocalGeneration** with `templateName`, `templateId`, `isCustomTemplate`, and `displayName`.
- **LocalGeneration**: keep the same structure. Semantically, “template” becomes “effect” for new rows: `templateName` stores the **effect name**, `templateId` the **effect id** (when present). No need to rename fields for V1 if you want minimal code churn; only the source of the name changes.
- **Merge from server:** When backend adds `effect_id` and `effect_name` (or similar) to the get-device-generations response, **GenerationHistoryService.mergeRemoteGenerations** should:
  - Prefer **effect_name** (or name resolved from effect_id) for `templateName` when present.
  - Fall back to current logic (e.g. deriving from `reference_video_url`) for old records or backward compatibility.
- **Pending generation card:** **ActiveGenerationManager** already stores `templateName` and `templateId`. When starting an effect generation, pass effect name and effect id; no UI change needed.
- **Cosmetic:** You can leave all labels as they are (“My Videos”, “Custom”, card titles). Optionally, one-time tweaks like changing a single “Template” label to “Effect” in history detail – only if you want consistency with the new wording; **0 changes required** for correctness.

---

## 6. Backend Contract Assumptions (for alignment)

So that iOS can be implemented against a single contract:

- **Catalog:**  
  - `effects` table: `id`, `name`, `description`, `preview_video_url`, `thumbnail_url`, `category_id`, `is_active`, `is_premium`, `sort_order`, `requires_secondary_photo` (and backend-only fields).  
  - `effect_categories` (or equivalent) for section headers and ordering.
- **Generation:**  
  - **execute-effect** accepts: `device_id`, `effect_id`, `init_image_url` (primary), optional `secondary_image_url`, optional `user_prompt`.  
  - Returns: generation id and polling metadata (same as current flow).
- **History:**  
  - **get-device-generations** (or equivalent) returns for each row: at least `id`, `status`, `output_video_url`, `input_image_url`, `created_at`, and for effect-based rows **effect_id** and **effect_name** (or a way to resolve the effect name). iOS will use effect_name for display in history when present.

---

## 7. File / Component Checklist (iOS)

| Item | Action |
|------|--------|
| **Models** | Add **Effect** (and **EffectCategory** if not reusing VideoCategory). Keep **VideoTemplate** / **Generation** / **LocalGeneration**; use Effect only in Create and generation start. |
| **Services** | Add **EffectService** (or extend CategoryService) to fetch effects + effect_categories and expose effectsByCategory. Add **GenerationService.executeEffect(...)**. |
| **CreateViewModel** | Switch to effect-based catalog (effectsByCategory + categories); remove or hide “Your Videos” for effect-only. |
| **CreateView** | Bind to effects; on select push **EffectGenerationView(effect)**. Optionally hide UserVideosSection. |
| **CategorySection** | Generalize to show effect cards (or add EffectCardView) and call onSelect(Effect). |
| **TemplateGridScreen** | Use for “Show All” effects with same layout; onSelect(Effect) → EffectGenerationView. |
| **EffectGenerationView** | New view: effect name only (no preview), 1–2 photo pickers, prompt text field below photos, Generate; same sheets and navigation to GeneratingView / ResultView. |
| **EffectGenerationViewModel** | New (or extend GenerationViewModel): hold primary + optional secondary photo + prompt; call executeEffect; register with ActiveGenerationManager with effect id/name. |
| **GenerationViewModel** | Optionally add `generateEffect(...)` or keep generation logic in EffectGenerationViewModel and reuse existing progress/result wiring. |
| **ActiveGenerationManager** | Accept effect id/name when starting a generation (same fields as template id/name). |
| **GenerationHistoryService** | In mergeRemoteGenerations, prefer effect_name from API when present. |
| **RemoteGeneration** | Add optional `effectId`, `effectName` (or similar) from get-device-generations. |
| **GeneratingView** | No change. |
| **ResultView** | No change (caller passes effect name). |
| **HistoryListView / HistoryItemCard / HistoryDetailView** | No change (optional cosmetic label only). |
| **VideoGenerationView** | Can remain for a transition period or be removed once EffectGenerationView is the only path from Create. |
| **TemplateDetailView / PhotoUploadView** | Used only from TemplateGalleryView; if you remove template gallery or repurpose it for effects, adjust or remove. Not required for the main Create → Effect flow. |

---

## 8. Order of Implementation (suggested)

1. **Data:** Add **Effect** and **EffectCategory** models; implement **EffectService** (or CategoryService effect API) and fetch effects + categories.
2. **Catalog UI:** CreateViewModel + CreateView + CategorySection (or EffectCardView) to show effects; “Show All” grid for effects; navigation to EffectGenerationView(effect).
3. **Effect generation screen:** EffectGenerationView + EffectGenerationViewModel; primary photo + conditional second photo + optional text field; **GenerationService.executeEffect**; wire to GeneratingView and ResultView; register with ActiveGenerationManager with effect id/name.
4. **History:** Extend **RemoteGeneration** and **mergeRemoteGenerations** to use effect name when present.
5. **Cleanup:** Hide or remove “Your Videos” on Create for effect-only; optionally remove or repurpose VideoGenerationView and template-based flows when backend is fully on execute-effect.

---

## 9. What Stays Exactly the Same

- Tab bar (Create / My Videos / Profile).  
- Onboarding, Paywall, Profile.  
- My Videos list and detail (layout, actions, sync, delete).  
- Device auth, realtime, IAP, storage (portraits, generated-videos).  
- All existing design tokens (colors, spacing, typography), **VideoButton**, **VideoMuteButton**, **PhotoSourceSheet**, **PhotoTipsSheet**, **AIDataConsentView**, **GeneratingView**, **ResultView**, **FullScreenVideoView**.  
- Reuse of the same UI/UX patterns: category sections, cards, bottom CTA, full-screen cover for generating, navigationDestination for result.

This plan is the starting point for aligning the backend and effects model with the iOS app while keeping the rest of the application and the history experience as they are today, with at most minimal cosmetic changes.
