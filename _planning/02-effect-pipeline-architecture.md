# Effect Architecture (V1 — Simple)

> Every effect is a single row in the `effects` table. One or two photos in, a system prompt under the hood, video out. No pre-processing, no LLM enrichment, no image transformations.

---

## 1. Effects Table Schema

```sql
CREATE TABLE public.effects (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  name                     text        NOT NULL,
  description              text,
  preview_video_url        text,               -- looping preview in catalog
  thumbnail_url            text,               -- card thumbnail
  category_id              uuid,               -- FK to effect_categories
  is_active                boolean     NOT NULL DEFAULT true,
  is_premium               boolean     NOT NULL DEFAULT false,
  sort_order               integer     NOT NULL DEFAULT 0,

  -- Input shape
  requires_secondary_photo boolean     NOT NULL DEFAULT false,

  -- Prompt
  system_prompt_template   text        NOT NULL,  -- supports {{user_prompt}} placeholder

  -- Video generation
  provider                 text        NOT NULL DEFAULT 'kling',   -- kling | grok | ...
  generation_params        jsonb       NOT NULL DEFAULT '{}',      -- duration, aspect_ratio, etc.

  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT effects_pkey PRIMARY KEY (id)
);
```

That's the whole model. One boolean (`requires_secondary_photo`) controls whether the UI shows a second photo picker. Everything else is just metadata + a prompt + provider config.

---

## 2. How It Works

```
User picks effect
      ↓
UI shows:
  • Photo picker (always)
  • Second photo picker (if requires_secondary_photo = true)
  • Text prompt field (always, optional)
      ↓
User taps Generate
      ↓
Backend (execute-effect):
  1. Load effect row from DB
  2. Validate subscription
  3. Build final prompt:
       - Start with system_prompt_template
       - Replace {{user_prompt}} with user's text (or remove placeholder if empty)
  4. Create generations row (status: "pending")
  5. Call provider API with:
       - image: primary photo URL
       - secondary_image: second photo URL (if provided)
       - prompt: final prompt
       - params: generation_params (duration, aspect_ratio, etc.)
  6. Update status to "processing"
      ↓
Webhook / polling → completed → video appears in My Videos
```

No intermediate steps, no LLM calls, no image transformations. Straight to video generation.

---

## 3. Prompt Template Example

For an effect called "Romantic Kiss":

```
system_prompt_template:
"Two people from the provided photos share a romantic kiss.
Cinematic slow motion, soft golden lighting, shallow depth of field.
{{user_prompt}}"
```

If the user types "on a beach at sunset", the final prompt becomes:

```
"Two people from the provided photos share a romantic kiss.
Cinematic slow motion, soft golden lighting, shallow depth of field.
on a beach at sunset"
```

If the user leaves the text field empty, `{{user_prompt}}` is stripped and the system prompt stands alone.

---

## 4. Concrete Examples

### Effect: "Portrait Animation" (single photo)

| Field | Value |
|-------|-------|
| `requires_secondary_photo` | `false` |
| `system_prompt_template` | `"Animate this portrait with gentle breathing, subtle hair movement, cinematic lighting. {{user_prompt}}"` |
| `provider` | `"kling"` |
| `generation_params` | `{"duration": 5, "aspect_ratio": "9:16"}` |

### Effect: "Romantic Kiss" (two photos)

| Field | Value |
|-------|-------|
| `requires_secondary_photo` | `true` |
| `system_prompt_template` | `"Two people from the photos share a romantic kiss. Soft lighting, cinematic. {{user_prompt}}"` |
| `provider` | `"kling"` |
| `generation_params` | `{"duration": 5, "aspect_ratio": "9:16"}` |

### Effect: "Cyberpunk Transform" (single photo, different provider)

| Field | Value |
|-------|-------|
| `requires_secondary_photo` | `false` |
| `system_prompt_template` | `"Transform this person into a cyberpunk world. Neon lights, rain, futuristic city. {{user_prompt}}"` |
| `provider` | `"grok"` |
| `generation_params` | `{"duration": 5, "aspect_ratio": "9:16"}` |

---

## 5. Evolved Generations Table

Minimal changes to `generations`:

```sql
-- Add:
effect_id         uuid REFERENCES effects(id),  -- which effect was used
input_payload     jsonb,                          -- raw user inputs for audit
secondary_image_url text,                         -- second photo if applicable

-- Keep as-is:
input_image_url, output_video_url, prompt, status,
device_id, api_response, error_message, retry_count, ...

-- Can drop or ignore (no longer relevant):
reference_video_url   -- was for motion-copy templates
character_orientation -- was dance-specific
copy_audio            -- was dance-specific
```

---

## 6. iOS Changes (Minimal)

| Screen | Change |
|--------|--------|
| `CreateView` | Fetch from `effects` instead of `reference_videos`. Same grid layout. |
| `EffectGenerationView` (new, replaces `VideoGenerationView`) | Photo picker (always shown), second photo picker (if `requires_secondary_photo`), text field for prompt. Generate button. |
| `GeneratingView` | No change — already shows progress. |
| `ResultView` | No change — already shows result. |
| Everything else | **No changes.** Tabs, navigation, onboarding, paywall, profile, history — untouched. |

---

## 7. Future Expansion

This V1 schema is intentionally minimal. When/if you need more complexity later:

- **Custom controls** → add a `custom_controls` JSONB column
- **Pre-processing steps** → add a `pipeline_config` JSONB column
- **Video-to-video** → add a `requires_video_input` boolean

The `execute-effect` edge function can be extended to check for these columns. Effects that don't use them just work as they do now. Backward compatible by design.
