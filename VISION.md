# Vision: Advanced Effect Pipelines

## What We're Building

We are evolving the video effects app from a **single-step** system (user photo + prompt → Grok → video) into a **multi-step pipeline** system where each effect can run a configurable chain of image transformations before the final video generation. The goal: dramatically better output quality by preparing the input image before it ever reaches the video model.

## The Problem with V1

In V1, the user uploads a photo and it goes straight to Grok Imagine Video with a prompt template. The video model has to do everything at once — interpret the person's appearance, apply the creative concept, and generate motion. This means:

- The person's face/body may not match the creative intent (wrong lighting, wrong angle, low quality selfie)
- Two-person effects suffer from inconsistent blending of the two faces
- The prompt does all the heavy lifting, and the video model sometimes ignores key details
- No opportunity to enhance, restyle, or composite the image before generation

## The Solution: Pre-Processing Pipelines

Each effect gets an optional **pipeline** — an ordered chain of steps that transform the user's input before the final video call. An admin configures these pipelines through the admin panel.

### Example: "Cinematic Kiss" Effect (Two Photos)

```
Step 1 → Gemini: Enhance both portraits (fix lighting, increase quality)
Step 2 → Gemini: Composite both faces into a single romantic scene image
Step 3 → Grok Imagine Video: Animate the composited image into a kiss scene
```

### Example: "Anime Transformation" Effect (Single Photo)

```
Step 1 → Nanobanana Pro: Restyle the portrait into anime art style
Step 2 → Grok Imagine Video: Animate the anime portrait with power-up effects
```

### Example: "Red Carpet" Effect (Single Photo, Simple)

```
No pipeline — straight to Grok like V1 (backward compatible)
```

## The APIs

### Grok Imagine (xAI) — Video & Image Generation
**What we already have.** Our primary executor for the final video output.

- `POST https://api.x.ai/v1/videos/generations` — image-to-video, text-to-video, up to 10s at 720p
- `POST https://api.x.ai/v1/images/generations` — text-to-image, image editing
- Models: `grok-imagine-video`, `grok-imagine-image`
- Auth: `Bearer $GROK_API_KEY`
- Async: returns `request_id`, poll `GET /v1/videos/{request_id}` for completion

### Gemini 2.5 Flash Image (Google) — Image Editing & Enhancement
**Our primary pre-processing engine.** Best for multi-image composition, style-aware edits, and quality enhancement.

- `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-image-generation:generateContent`
- Accepts inline image data (base64) plus text instructions
- Supports multi-turn editing (sequential refinements)
- Can blend/composite multiple images with natural language instructions
- Output: PNG/JPEG image data in the response
- Auth: `x-goog-api-key: $GEMINI_API_KEY`
- Aspect ratios: 1:1, 9:16, 16:9, and more

### Nanobanana Pro (Google) — Advanced Image Editing
**Specialized image editing.** Best for precise style transfers, background replacement, element manipulation.

- `POST https://api.nanobananaimages.com/v1/generate` or via Replicate
- Reference image support (up to 4 images)
- Style presets: photorealistic, anime, oil painting, abstract
- Local edits: lighting, color grading, element addition/removal, background swap
- ~20 second processing time
- Auth: `Bearer $NANOBANANA_API_KEY`
- High-res output up to 4K

## How Pipelines Work at Runtime

```
User taps "Generate" on an effect
          ↓
Edge function loads effect + linked pipeline
          ↓
For each step in the pipeline:
  1. Read input from context (original image, previous step output, etc.)
  2. Call the step's API (Gemini, Nanobanana, Grok Image)
  3. Store the output in Supabase Storage (pipeline-artifacts bucket)
  4. Write the result URL back into the pipeline context
  5. Update pipeline_executions with step progress
          ↓
Final step: Grok Imagine Video with the processed image + enriched prompt
          ↓
Poll for completion → video delivered to user
```

Each step's intermediate result is stored, so admins can inspect what happened at every stage — useful for debugging and tuning effect quality.

## What the Admin Panel Manages

- **Effects**: name, prompt template, category, premium flag, thumbnail
- **Pipelines**: create/edit step chains, assign to effects
- **Steps**: pick provider, write config (prompt, style, parameters), set input/output mappings
- **Monitoring**: view pipeline executions, inspect step results, see failure reasons
- **AI Models**: toggle models on/off, adjust default parameters

## Implementation Order

1. **Pipeline executor edge function** — the runtime that walks through steps and calls APIs
2. **Gemini image editing integration** — first pre-processing provider (API key already available)
3. **Nanobanana Pro integration** — second provider for style-heavy effects
4. **Admin panel pipeline builder** — UI for creating and linking pipelines
5. **iOS app updates** — pipeline progress indicator, step previews (optional)

## What Success Looks Like

An admin creates a new "Glamour Portrait" effect entirely from the admin panel:
1. Writes a pipeline: Gemini enhances lighting → Nanobanana applies magazine-cover style → Grok generates a video of the person on a runway
2. Sets a prompt template and thumbnail
3. Marks it active
4. Users see it in the app and generate videos — no code changes, no app update needed

Effects become a **creative product**, not an engineering task. The pipeline system is the constructor that makes this possible.
