# Multi-Step Effect Pipeline — Implementation Plan

> Comprehensive plan for enabling administrators to build complex, multi-step video generation workflows using Gemini image editing, Grok Vision analysis, Grok prompt enrichment, and Grok video generation.

---

## The Current State (What We Have)

The system today is a **single-step** flow: user image + prompt template → Grok video generation. The `generate-video` Edge Function loads an effect, substitutes `{{user_prompt}}`, and fires a single Grok image-to-video API call. No pre-processing, no LLM enrichment, no image transformation.

However, the database schema is already **forward-looking** — `pipeline_templates`, `pipeline_steps`, `effect_pipelines`, and `pipeline_executions` tables exist, plus a `pipeline-artifacts` storage bucket. None of this infrastructure is wired up in any Edge Function or admin panel page yet. This is the foundation we build on.

---

## What We Want (Two Key Scenarios)

### Scenario A — Image Enhancement Before Video Generation

User photo → Gemini 3.1 Flash Lite enhances image (e.g., cinematic filter) → enhanced image becomes first frame for Grok video generation → output video.

### Scenario B — Vision-Driven Prompt Enrichment

User photo → Grok Vision analyzes image and produces a description → description + effect prompt template → Grok compiles a personalized video generation prompt → personalized prompt + original image → Grok video generation → output video.

Both scenarios require **multi-step orchestration** where the output of one step feeds into the next.

---

## Phase 1: Database Schema Enhancements

### 1.1 Standardized `pipeline_steps.step_type` vocabulary

The `pipeline_steps` table already supports `step_type` as free text. Canonical step types:

| `step_type` | Provider | Purpose |
|---|---|---|
| `image_enhance` | `gemini` | Send image + prompt to Gemini image editing to get an enhanced version |
| `image_analyze` | `grok` | Send image to Grok Vision to get a text description |
| `prompt_enrich` | `grok` | Send context + template to Grok text completion to build a better prompt |
| `video_generate` | `grok` | The final video generation step (what we have today) |

No DDL changes needed for step_type — it's already `text`.

### 1.2 Add Gemini and Vision models to `ai_models`

```sql
INSERT INTO public.ai_models (id, name, provider, model_type, is_active, config)
VALUES
  ('gemini-3.1-flash-lite-preview', 'Gemini 3.1 Flash Lite (Image Edit/Generate)', 'gemini', 'image', true, '{}'),
  ('grok-vision', 'Grok Vision (Image Analysis)', 'grok', 'vision', true, '{}'),
  ('grok-text', 'Grok Text (Prompt Enrichment)', 'grok', 'text', true, '{}')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, provider = EXCLUDED.provider;
```

### 1.3 Add Gemini to `provider_config`

```sql
INSERT INTO public.provider_config (provider, config, is_active)
VALUES (
  'gemini',
  '{
    "api_key_secret": "GEMINI_API_KEY",
    "base_url": "https://generativelanguage.googleapis.com/v1beta",
    "default_model": "gemini-3.1-flash-lite-preview",
    "timeout_seconds": 60
  }'::jsonb,
  true
) ON CONFLICT (provider) DO UPDATE SET config = EXCLUDED.config;
```

### 1.4 `pipeline_steps.config` schema conventions per step type

The `config` JSONB column on `pipeline_steps` already exists. Conventions for each step type:

**For `image_enhance` steps:**

```json
{
  "model": "gemini-3.1-flash-lite-preview",
  "prompt_template": "Apply a cinematic color grade to this image. Enhance contrast, add warm tones, shallow depth of field look. Keep the subject identical. {{context}}",
  "output_format": "image_url",
  "quality": "high"
}
```

**For `image_analyze` steps:**

```json
{
  "model": "grok-vision",
  "prompt_template": "Describe in detail what you see in this image. Focus on: the subject(s), their appearance, expression, pose, clothing, and the background/setting. Be specific and concise.",
  "output_key": "image_description",
  "max_tokens": 500
}
```

**For `prompt_enrich` steps:**

```json
{
  "model": "grok-text",
  "prompt_template": "You are a creative video director. Based on this image description: '{{image_description}}', and this effect concept: '{{effect_concept}}', write a detailed video generation prompt that incorporates specific details from the image. The video should {{effect_goal}}. Keep it under 200 words. {{user_prompt}}",
  "output_key": "enriched_prompt"
}
```

**For `video_generate` steps:**

```json
{
  "model": "grok-imagine-video",
  "prompt_source": "enriched_prompt",
  "image_source": "enhanced_image",
  "duration": 10,
  "aspect_ratio": "9:16",
  "resolution": "720p"
}
```

### 1.5 `input_mapping` and `output_mapping` conventions

These JSONB columns on `pipeline_steps` already exist. They serve as the **data flow wiring** between steps.

**`input_mapping`** — tells the step where to get its inputs from the pipeline context:

```json
{
  "image": "pipeline.user_image",
  "prompt_context": "steps.image_analyze.output.image_description"
}
```

**`output_mapping`** — tells the orchestrator where to store step results in context:

```json
{
  "enhanced_image": "result.image_url",
  "enhanced_image_storage_path": "result.storage_path"
}
```

### 1.6 Add `pipeline_execution_id` to `generations`

```sql
ALTER TABLE public.generations
  ADD COLUMN IF NOT EXISTS pipeline_execution_id uuid
    REFERENCES public.pipeline_executions(id);
```

Links a generation to its pipeline execution for traceability.

### 1.7 New table: `pipeline_step_executions`

The existing `pipeline_executions.step_results` JSONB array is useful as a summary, but a dedicated table gives indexing, easier querying, independent status tracking per step, and future individual-step retries.

```sql
CREATE TABLE public.pipeline_step_executions (
  id                    uuid        NOT NULL DEFAULT gen_random_uuid(),
  pipeline_execution_id uuid        NOT NULL REFERENCES public.pipeline_executions(id) ON DELETE CASCADE,
  step_id               uuid        NOT NULL REFERENCES public.pipeline_steps(id),
  step_order            integer     NOT NULL,
  status                text        NOT NULL DEFAULT 'pending',
  input_data            jsonb       NOT NULL DEFAULT '{}',
  output_data           jsonb       NOT NULL DEFAULT '{}',
  provider_request_id   text,
  error_message         text,
  started_at            timestamptz,
  completed_at          timestamptz,
  duration_ms           integer,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pipeline_step_executions_pkey PRIMARY KEY (id),
  CONSTRAINT pipeline_step_executions_status_check
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped'))
);

CREATE INDEX idx_pipeline_step_executions_pipeline
  ON public.pipeline_step_executions (pipeline_execution_id);

ALTER TABLE public.pipeline_step_executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read step executions"
  ON public.pipeline_step_executions FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages step executions"
  ON public.pipeline_step_executions FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TRIGGER update_pipeline_step_executions_updated_at
  BEFORE UPDATE ON public.pipeline_step_executions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

---

## Phase 2: New Edge Functions & Backend Logic

### 2.1 Pipeline Orchestrator (shared module)

New file: `_shared/pipeline-orchestrator.ts`

The orchestrator is the brain of the multi-step system. Called from within `generate-video` when an effect has a linked pipeline.

**Flow:**

1. Load ordered `pipeline_steps` for the pipeline
2. Create `pipeline_executions` row (status: `running`)
3. Initialize pipeline context: `{ user_image: input_image_url, user_prompt, effect_id, effect_name, effect_concept: system_prompt_template }`
4. Execute steps sequentially:
   - For each step, resolve `input_mapping` from context
   - Call the appropriate provider handler
   - Store results via `output_mapping` back into context
   - Create `pipeline_step_executions` row for tracking
   - Upload artifacts (enhanced images) to `pipeline-artifacts` bucket
5. The final `video_generate` step kicks off the async Grok call
6. Return the context with `provider_request_id` for polling

### 2.2 Provider Handler Modules

Create `supabase/functions/_shared/providers/`:

**`gemini-image.ts`** — Gemini image editing:

- Calls Gemini API for image enhancement/editing
- Accepts: image URL + prompt
- Returns: enhanced image URL (uploaded to `pipeline-artifacts`)
- Uses `GEMINI_API_KEY` from Edge Function secrets

**`grok-vision.ts`** — Grok Vision for image analysis:

- Calls Grok chat completions with image input
- Accepts: image URL + analysis prompt
- Returns: text description
- Uses existing `GROK_API_KEY`

**`grok-text.ts`** — Grok text completion for prompt enrichment:

- Calls Grok chat completions (text only)
- Accepts: prompt with context variables substituted
- Returns: compiled/enriched prompt text
- Uses existing `GROK_API_KEY`

**`grok-video.ts`** — Extracted from current `generate-video`:

- Same Grok video generation logic as today
- Accepts: image URL + prompt + params
- Returns: `request_id` for polling

### 2.3 Modify `generate-video` for pipeline routing

Rather than creating a new endpoint, modify `generate-video` to check for pipelines:

```
load effect
  → check effect_pipelines for active pipeline
  → if pipeline exists:
      → run pipeline orchestration (pre-processing steps inline, video step async)
  → else:
      → run current direct-to-Grok logic (unchanged)
```

This maintains the **same iOS contract** — the app always calls `generate-video`, and the backend decides internally whether to run a simple or complex flow.

### 2.4 Extend `poll-pending-generations`

When a generation with a `pipeline_execution_id` completes (video done), also update `pipeline_executions` to `status: 'completed'`. This enables the admin panel to show pipeline status.

### 2.5 New Edge Function secrets

```
GEMINI_API_KEY    — Google AI / Gemini API key
```

`GROK_API_KEY` already exists and covers Grok Vision, Grok text, and Grok video.

---

## Phase 3: Admin Panel — Pipeline Builder

### 3.1 New route: Pipeline Management

Add `/pipelines` to the admin panel router:

- **Pipeline list page** — shows all `pipeline_templates`: name, step count, version, linked effects count, active status
- **Pipeline editor page** — the workflow builder

### 3.2 Pipeline Editor UI

A step-by-step workflow builder.

**Header:** Pipeline name, description, version, active toggle.

**Steps list** (ordered, drag-to-reorder): each step is an expandable card with:

1. **Step type** dropdown: `Image Enhancement`, `Image Analysis`, `Prompt Enrichment`, `Video Generation`
2. **Name** — human-readable label (e.g., "Apply Cinematic Filter")
3. **Provider** — auto-set based on step type, or selectable
4. **AI Model** — dropdown filtered by step type's compatible models
5. **Prompt Template** — large text area with variable hints (e.g., `{{user_image}}`, `{{image_description}}`, `{{user_prompt}}`)
6. **Input Mapping** — visual or JSON editor showing where inputs come from
7. **Output Mapping** — what this step produces and the key names
8. **Timeout** — seconds
9. **Required** toggle — whether failure aborts the pipeline
10. **Retry config** — max retries, backoff

**Add Step** button at the bottom.

**Constraint:** The last step must always be `video_generate`.

### 3.3 Effect Editor — Pipeline Linking

Modify the existing Effect Editor to add a **Pipeline** section:

- **Pipeline** dropdown: select from `pipeline_templates` or "None (direct generation)"
- When "None" is selected, the effect works exactly as today (simple prompt → video)
- When a pipeline is selected, show a read-only summary of the pipeline steps
- **Config overrides** — JSON editor for per-effect overrides of pipeline step configs

The `system_prompt_template` field on the effect becomes the **fallback** for simple effects; for pipeline effects, the prompt is built dynamically by the pipeline steps.

### 3.4 Pipeline Execution Monitor

Extend the existing Generations page:

- When clicking a generation that has a `pipeline_execution_id`, show an expandable **Pipeline Run** section
- Display each step with: status badge, duration, input summary, output summary, errors
- Show the flow visually: Step 1 ✓ → Step 2 ✓ → Step 3 ✓ → Step 4 (processing)

### 3.5 New page: AI Models & Providers

Add `/ai-models` page:

- CRUD for `ai_models` — manage which models are available
- CRUD for `provider_config` — manage provider defaults and API configurations

---

## Phase 4: Concrete Pipeline Examples

### Scenario A: Cinematic Enhancement Pipeline

**Pipeline name:** "Cinematic Pre-Enhancement"

| Step | Type | Config |
|---|---|---|
| 1 | `image_enhance` | Model: Gemini. Prompt: "Transform this casual photo into a cinematic still. Add dramatic lighting, rich color grading, slight vignette. Keep the subject identical." Input: `user_image`. Output: `enhanced_image` |
| 2 | `video_generate` | Model: grok-imagine-video. Prompt: effect's `system_prompt_template`. Image: `enhanced_image` (from step 1, not original). Duration/aspect_ratio from effect params |

**Admin creates this by:**

1. Going to Pipelines → Create New
2. Adding Step 1 (Image Enhancement) with the Gemini prompt
3. Adding Step 2 (Video Generation) with image source set to step 1's output
4. Saving the pipeline
5. Going to Effects → Edit "Cinematic Transform"
6. Setting Pipeline to "Cinematic Pre-Enhancement"

### Scenario B: Vision-Enriched Personalized Prompt

**Pipeline name:** "Vision-Enriched Generation"

| Step | Type | Config |
|---|---|---|
| 1 | `image_analyze` | Model: Grok Vision. Prompt: "Describe in detail what you see in this image: the subject, setting, mood, notable details." Input: `user_image`. Output: `image_description` |
| 2 | `prompt_enrich` | Model: Grok Text. Prompt: "You are a creative video director. Image description: '{{image_description}}'. Effect goal: '{{effect_concept}}'. User request: '{{user_prompt}}'. Write a detailed, personalized video generation prompt that weaves specific details from the image into the effect concept." Input: `image_description` + effect template. Output: `enriched_prompt` |
| 3 | `video_generate` | Model: grok-imagine-video. Prompt: `enriched_prompt` (from step 2). Image: `user_image` (original). Duration/aspect_ratio from effect params |

**The elephant example:** If the user uploads a photo of an elephant and the effect is "Fun Animal Adventure," step 1 detects "a large African elephant standing in a savanna," step 2 takes that + the effect template to create something like "The majestic elephant suddenly starts dancing to funky music, its trunk swaying rhythmically..." and step 3 generates that video.

---

## Phase 5: Implementation Order

### Sprint 1 — Database & Foundations (1–2 days)

1. Run schema migrations (new table, column additions)
2. Seed AI models and provider config for Gemini/Vision
3. Add `GEMINI_API_KEY` to Edge Function secrets
4. Create provider handler modules (`gemini-image.ts`, `grok-vision.ts`, `grok-text.ts`, `grok-video.ts`)

### Sprint 2 — Pipeline Orchestrator (2–3 days)

5. Build `pipeline-orchestrator.ts` shared module
6. Integrate into `generate-video` with pipeline routing
7. Update `poll-pending-generations` for pipeline-aware completion
8. Test with hardcoded pipeline data (SQL-inserted)

### Sprint 3 — Admin Panel: Pipeline Builder (3–4 days)

9. Add Pipeline list + editor pages to admin panel
10. Add pipeline linking to Effect Editor
11. Add AI Models management page
12. Add provider config management

### Sprint 4 — Admin Panel: Monitoring & Polish (1–2 days)

13. Extend Generations page with pipeline execution details
14. Add step-level execution monitoring
15. Add pipeline validation (last step must be `video_generate`, etc.)

### Sprint 5 — Testing & Iteration (2 days)

16. Create test pipelines for both scenarios
17. End-to-end testing: admin creates pipeline → links to effect → user generates video via iOS → multi-step flow executes → video delivered
18. Error handling: what happens when Gemini fails? When a step times out? Graceful fallback?

---

## Key Architectural Decisions

### Why modify `generate-video` instead of creating a new endpoint?

The iOS app calls `generate-video`. By routing internally, we get pipeline support with zero iOS changes. The iOS contract (`device_id`, `effect_id`, `input_image_url`, `user_prompt`) is sufficient for everything described.

### Why run pre-processing steps synchronously within the Edge Function?

Gemini image editing is synchronous (returns in 2–10 seconds). Grok Vision/text calls are also fast (1–5 seconds). Only video generation is async (minutes). Running pre-processing inline avoids the complexity of multi-stage polling. The Edge Function timeout (default 60s in Supabase) is more than enough for 2–3 pre-processing steps.

### Why a dedicated `pipeline_step_executions` table?

The existing `pipeline_executions.step_results` JSONB array could work, but a relational table gives: indexing, easier querying in the admin panel, independent status tracking per step, and the ability to retry individual steps in the future.

### Backward compatibility

Effects without a linked pipeline work exactly as today. The pipeline system is opt-in per effect. Zero risk to existing effects.

### Why not touch iOS?

The iOS app sends one image + one prompt. That's exactly what both scenarios need. The backend decides internally what to do with that image. The app polls for completion as usual. From the user's perspective, some effects might take slightly longer (due to pre-processing), but the UX is identical.

---

## Summary of All Changes Required

| Layer | What | Type |
|---|---|---|
| **Database** | Add `pipeline_step_executions` table | New table |
| **Database** | Add `pipeline_execution_id` to `generations` | New column |
| **Database** | Insert Gemini/Vision models into `ai_models` | Seed data |
| **Database** | Insert Gemini `provider_config` | Seed data |
| **Backend** | Create `_shared/providers/gemini-image.ts` | New module |
| **Backend** | Create `_shared/providers/grok-vision.ts` | New module |
| **Backend** | Create `_shared/providers/grok-text.ts` | New module |
| **Backend** | Extract `_shared/providers/grok-video.ts` from generate-video | Refactor |
| **Backend** | Create `_shared/pipeline-orchestrator.ts` | New module |
| **Backend** | Modify `generate-video` to check for & route to pipelines | Enhancement |
| **Backend** | Modify `poll-pending-generations` for pipeline-aware completion | Enhancement |
| **Backend** | Add `GEMINI_API_KEY` secret | Config |
| **Admin Panel** | New Pipeline list page | New page |
| **Admin Panel** | New Pipeline editor page (workflow builder) | New page |
| **Admin Panel** | Modify Effect Editor — add pipeline selector | Enhancement |
| **Admin Panel** | New AI Models management page | New page |
| **Admin Panel** | Extend Generations monitor with pipeline step details | Enhancement |
| **Admin Panel** | Update TypeScript types for new/modified tables | Enhancement |
| **iOS** | Nothing | No changes |
