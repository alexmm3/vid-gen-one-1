# High-Level Implementation Plan (V1)

> AI Video Effects App — simple version. Each effect = system prompt + one or two photos from user.

---

## Golden Rule

**Account UI is untouched.** Onboarding, Paywall, Profile, My Videos / History — zero changes. Only the Create flow and backend generation logic change.

---

## Phase 1 — Database

- Create `effects` table (name, preview video, thumbnail, category, `requires_secondary_photo` bool, `system_prompt_template`, provider, generation params).
- Create `effect_categories` table (or repurpose `video_categories`).
- Evolve `generations` table: add `effect_id`, `secondary_image_url`, `input_payload`; relax old dance-specific constraints.

## Phase 2 — Backend

- New `execute-effect` edge function: load effect → validate subscription → build prompt (template + user text) → call provider API → create/update generation row.
- Provider adapter layer (Kling + Grok to start). Thin wrappers, same interface.
- Adapt `generation-webhook` and `poll-pending-generations` to work with provider info from the generation record.

## Phase 3 — iOS

- `CreateView`: fetch `effects` instead of `reference_videos`, same grid/category UI.
- New `EffectGenerationView`: photo picker, optional second photo picker (driven by `requires_secondary_photo`), text prompt field, generate button.
- Wire `GeneratingView` and `ResultView` to the updated generation record shape.
- New `Effect` model, new `EffectService`.

## Phase 4 — Branding & Ship

- New bundle ID, app name, icons.
- Point to new Supabase project.
- App Store listing.

---

## What Does NOT Change

- Tab bar (Create / My Videos / Profile)
- Onboarding, Paywall, Profile, History screens
- Device-based auth
- Realtime status updates
- Apple IAP validation
- Storage buckets (portraits, generated-videos)

---

## Docs

- Architecture details: `02-effect-pipeline-architecture.md`
- Admin panel brief: `03-admin-panel-brief.md`
- Grok Imagine API (image + video) reference for provider implementation: `04-grok-imagine-api-reference.md`
- Grok edge function, provider selection, and provider config table: `05-grok-edge-function-and-provider-config-plan.md`
