# Pipeline Architecture V2 — Advanced Pre-Processing

> Building on V1's simple effect model, V2 adds configurable multi-step pipelines
> that can transform images and enrich prompts before video generation.

---

## 1. Core Concept

Each effect can optionally be linked to a **pipeline template** — an ordered list of
processing steps that run before the final video generation call. Effects without
a pipeline work exactly as V1 (image + prompt → Grok → video).

```
┌─────────────┐     ┌──────────────────┐     ┌────────────────┐
│   Effect     │────▶│  Pipeline        │────▶│  Steps (1..N)  │
│   Config     │     │  Template        │     │  in order      │
└─────────────┘     └──────────────────┘     └────────────────┘
                                                     │
                                               ┌─────┴─────┐
                                               │ Each step: │
                                               │ • provider │
                                               │ • config   │
                                               │ • I/O map  │
                                               └───────────┘
```

---

## 2. Step Types

| step_type | Description | Example providers |
|-----------|-------------|-------------------|
| `image_enhance` | Improve image quality/lighting | Gemini, Nanobanana |
| `image_edit` | Apply specific edits (style, background, etc.) | Nanobanana, Gemini |
| `image_generate` | Generate a new image from prompt | Grok Imagine Image |
| `prompt_enrich` | Use LLM to enhance/rewrite the prompt | Gemini, GPT |
| `video_generate` | Final video generation step | Grok Imagine Video |
| `conditional` | Branch logic based on input properties | Internal |

---

## 3. Data Flow Between Steps

Each step receives a **context object** and produces outputs that are merged back:

```json
{
  "original_image_url": "https://...",
  "secondary_image_url": "https://...",
  "user_prompt": "on a beach",
  "system_prompt": "Two people share a romantic kiss...",
  "step_1_output": {
    "enhanced_image_url": "https://...",
    "metadata": { ... }
  },
  "step_2_output": {
    "edited_image_url": "https://...",
    "metadata": { ... }
  }
}
```

The `input_mapping` field on each step defines which context keys it reads.
The `output_mapping` field defines where its results are stored in context.

---

## 4. Example Pipeline: "Premium Kiss Effect"

```
Step 1: image_enhance (Gemini)
  ├─ Input: original_image_url
  ├─ Config: { "enhancement": "portrait_lighting", "quality": "high" }
  └─ Output: enhanced_primary_url

Step 2: image_enhance (Gemini)
  ├─ Input: secondary_image_url
  ├─ Config: { "enhancement": "portrait_lighting", "quality": "high" }
  └─ Output: enhanced_secondary_url

Step 3: prompt_enrich (Gemini)
  ├─ Input: system_prompt, user_prompt
  ├─ Config: { "style": "cinematic", "max_tokens": 200 }
  └─ Output: enriched_prompt

Step 4: video_generate (Grok)
  ├─ Input: enhanced_primary_url, enhanced_secondary_url, enriched_prompt
  ├─ Config: { "duration": 5, "aspect_ratio": "9:16" }
  └─ Output: video_url
```

---

## 5. Tables

- `pipeline_templates` — Named, versioned pipeline definitions
- `pipeline_steps` — Ordered steps with provider, config, I/O mappings
- `effect_pipelines` — Links an effect to a pipeline (with config overrides)
- `pipeline_executions` — Runtime tracking (status, current step, step results)

---

## 6. Admin Panel Integration

The admin panel will provide:
- Pipeline builder UI (drag-and-drop step ordering)
- Per-step configuration forms
- Effect ↔ pipeline linking
- Pipeline execution monitoring
- Step result inspection for debugging

---

## 7. Backward Compatibility

Effects without a pipeline continue to work via the existing `generate-video`
edge function path. The pipeline executor is a separate code path that wraps
the existing generation logic.
