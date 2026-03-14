# Grok Imagine API — Official Reference for LLMs

This document is the single source of truth for implementing the **xAI Grok Imagine API** (image and video) in this product. It is intended for LLMs and developers building the Grok-backed edge function that will be an alternative to the current Kling/ModelsLab video generation flow. **Do not change the iOS contract:** same request shape and effect parameters; only the backend execution (provider call + polling) differs.

**Official xAI docs (source of truth):**
- Image: https://docs.x.ai/developers/model-capabilities/images/generation  
- Video: https://docs.x.ai/developers/model-capabilities/video/generation  
- REST API: https://docs.x.ai/developers/rest-api-reference  

**Authentication:** Use a Bearer token. In this project the key is stored in Edge Function secrets as **`GROK_API_KEY`** (xAI’s docs use `XAI_API_KEY`; both refer to the same key from https://console.x.ai/ ).

**Base URL:** `https://api.x.ai/v1`

---

## 1. Video generation (Grok Imagine Video)

### 1.1 Overview

- **Model:** `grok-imagine-video`
- **Modes:** Text-to-video, **image-to-video** (animate a still image), video editing (edit existing video with a prompt).
- **Async:** Video generation is **asynchronous**. You get a `request_id` from the start endpoint, then poll until `status` is `done` or `expired`. There is **no webhook**; polling must be implemented (e.g. in the edge function or a separate poller that updates `generations`).

### 1.2 Endpoints

| Method | Path | Purpose |
|--------|------|--------|
| POST   | `/v1/videos/generations` | Start a video generation (text-to-video or image-to-video). Returns `request_id`. |
| POST   | `/v1/videos/edits`      | Start a video **edit** (provide existing video + prompt). Returns `request_id`. |
| GET    | `/v1/videos/{request_id}`| Poll status and get result (video URL when `status === "done"`). |

### 1.3 Start generation — POST /v1/videos/generations

**Headers:**
- `Content-Type: application/json`
- `Authorization: Bearer <GROK_API_KEY>`

**Request body (text-to-video):**

```json
{
  "model": "grok-imagine-video",
  "prompt": "A glowing crystal-powered rocket launching from the red dunes of Mars",
  "duration": 10,
  "aspect_ratio": "16:9",
  "resolution": "720p"
}
```

**Request body (image-to-video)** — add **one** of:

- `image_url`: string — public URL or data URI, e.g. `"https://example.com/photo.jpg"` or `"data:image/jpeg;base64,..."`

So for our product, the primary input image (`input_image_url`) maps to `image_url` (use the public URL as-is if it’s accessible by xAI; no need for base64 unless required).

**Parameters:**

| Parameter      | Type   | Required | Description |
|----------------|--------|----------|-------------|
| `model`        | string | Yes      | `"grok-imagine-video"` |
| `prompt`       | string | Yes      | Text description of the video (or motion for image-to-video). |
| `duration`     | number | No       | Length in seconds. **Range: 1–15.** Omit for default. |
| `aspect_ratio` | string | No       | e.g. `"16:9"`, `"9:16"`, `"1:1"`, `"4:3"`, `"3:4"`, `"3:2"`, `"2:3"`. Default `"16:9"`. For image-to-video, default follows input image; can override here. |
| `resolution`   | string | No       | `"720p"` (HD) or `"480p"` (faster). Default `"480p"`. |
| `image_url`    | string | No*      | *Required for image-to-video.* Public URL or `data:image/...;base64,...` of the source image. |

**Response (HTTP 200):**

```json
{ "request_id": "d97415a1-5796-b7ec-379f-4e6819e08fdf" }
```

Use this `request_id` for polling.

### 1.4 Poll status — GET /v1/videos/{request_id}

**Headers:** `Authorization: Bearer <GROK_API_KEY>`

**Response (pending):**

```json
{ "status": "pending" }
```

**Response (done):**

```json
{
  "status": "done",
  "video": {
    "url": "https://vidgen.x.ai/.../video.mp4",
    "duration": 8,
    "respect_moderation": true
  },
  "model": "grok-imagine-video"
}
```

**Response (expired):**

```json
{ "status": "expired" }
```

- **Video URL is temporary;** download or re-host (e.g. to R2) promptly.
- **Status values:** `pending` | `done` | `expired`.

### 1.5 Video editing — POST /v1/videos/edits

Same auth and base URL. Body includes:

- `model`: `"grok-imagine-video"`
- `prompt`: natural language edit instructions
- `video_url`: public URL of the source video

**Constraints for edits:** Duration, aspect ratio, and resolution are taken from the input video (duration capped at 8.7s; resolution capped at 720p). Do not send `duration`/`aspect_ratio`/`resolution` for edits.

### 1.6 Video generation timing and limits

- Processing usually takes **several minutes** (longer for 720p, longer duration, and video editing).
- **Limits:** 480p or 720p; max **15 seconds** for generation; edited video input max **8.7 seconds**.
- Content moderation applies; `respect_moderation` in the response indicates whether the output passed.

### 1.7 Example: Image-to-video with fetch (Edge Function style)

```typescript
const GROK_API_KEY = Deno.env.get("GROK_API_KEY")!;
const BASE = "https://api.x.ai/v1";

// 1) Start image-to-video
const startRes = await fetch(`${BASE}/videos/generations`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${GROK_API_KEY}`,
  },
  body: JSON.stringify({
    model: "grok-imagine-video",
    prompt: finalPrompt,           // from effect.system_prompt_template + user_prompt
    image_url: input_image_url,    // public URL from request
    duration: 10,
    aspect_ratio: "16:9",
    resolution: "720p",
  }),
});
if (!startRes.ok) throw new Error(`Grok start failed: ${await startRes.text()}`);
const { request_id } = await startRes.json();

// 2) Poll until done (or expired / timeout)
let data: { status: string; video?: { url: string; duration?: number } };
do {
  await new Promise((r) => setTimeout(r, 5000));
  const pollRes = await fetch(`${BASE}/videos/${request_id}`, {
    headers: { "Authorization": `Bearer ${GROK_API_KEY}` },
  });
  if (!pollRes.ok) throw new Error(`Grok poll failed: ${await pollRes.text()}`);
  data = await pollRes.json();
} while (data.status === "pending");

if (data.status === "done" && data.video?.url) {
  const outputVideoUrl = data.video.url;
  // Store outputVideoUrl (e.g. download and re-upload to R2, then save URL to generations.output_video_url)
} else {
  // status === "expired" or missing video
}
```

---

## 2. Image generation (Grok Imagine Image)

Included for future use; not required for the first video-only Grok edge function.

### 2.1 Overview

- **Model:** `grok-imagine-image`
- **Modes:** Text-to-image, image editing (single or multiple images), style transfer.
- **Sync:** Image API is **synchronous**; the response contains the image URL or base64 directly.

### 2.2 Endpoints

| Method | Path | Purpose |
|--------|------|--------|
| POST   | `/v1/images/generations` | Generate image(s) from text. |
| POST   | `/v1/images/edits`       | Edit image(s) with a prompt (single `image` or multiple `images`). |

### 2.3 POST /v1/images/generations

**Headers:** `Content-Type: application/json`, `Authorization: Bearer <GROK_API_KEY>`

**Request body:**

```json
{
  "model": "grok-imagine-image",
  "prompt": "A collage of London landmarks in a stenciled street-art style",
  "n": 1,
  "aspect_ratio": "16:9",
  "resolution": "2k",
  "response_format": "url"
}
```

**Parameters:**

| Parameter        | Type   | Required | Description |
|------------------|--------|----------|-------------|
| `model`          | string | Yes      | `"grok-imagine-image"` |
| `prompt`         | string | Yes      | Text description of the image. |
| `n`              | number | No       | Number of images (same prompt). Max 10. Default 1. |
| `aspect_ratio`   | string | No       | `"1:1"`, `"16:9"`, `"9:16"`, `"4:3"`, `"3:4"`, `"3:2"`, `"2:3"`, `"2:1"`, `"1:2"`, `"19.5:9"`, `"9:19.5"`, `"20:9"`, `"9:20"`, or `"auto"`. |
| `resolution`     | string | No       | `"2k"` or `"1k"`. |
| `response_format`| string | No       | `"url"` (default) or `"b64_json"`. |

**Response (success):** Array of objects with `url` or `b64_json` (and optional metadata). URLs are temporary.

### 2.4 POST /v1/images/edits

**Single image:** body includes `image` (object with `url` and `type: "image_url"`) or equivalent base64.  
**Multiple images (e.g. “add the cat from first to second”):** use `images` array. Up to 3 images. Optional `aspect_ratio` overrides output aspect ratio.

**Example (single image, public URL):**

```bash
curl -X POST https://api.x.ai/v1/images/edits \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GROK_API_KEY" \
  -d '{
    "model": "grok-imagine-image",
    "prompt": "Render this as a pencil sketch with detailed shading",
    "image": { "url": "https://example.com/photo.png", "type": "image_url" }
  }'
```

### 2.5 Image limits and pricing

- Content moderation applies; max **10 images per request** for generations.
- Pricing is per image (not token-based). Editing charges for input + output.
- Official pricing: https://docs.x.ai/developers/models/grok-imagine-image

---

## 3. Mapping to this product (video flow)

Use this when implementing the **Grok video** edge function so behavior and contract match the existing `generate-video` flow.

### 3.1 Incoming request (unchanged)

The edge function should accept the **same** body as the current `generate-video`:

- `device_id`: string  
- `effect_id`: string  
- `input_image_url`: string (public HTTP(S) URL)  
- `secondary_image_url`: optional (required if effect has `requires_secondary_photo`)  
- `user_prompt`: optional (replaces `{{user_prompt}}` in the effect template)

**Validation:** Same as current: require `device_id`, `effect_id`, `input_image_url`; validate URLs; load effect; enforce `requires_secondary_photo`; subscription check; then call Grok.

### 3.2 Effect record (unchanged)

From `effects` table:

- `system_prompt_template`: used as the Grok `prompt` (after substituting `{{user_prompt}}`).
- `generation_params`: use for Grok-specific overrides when present, e.g. `duration`, `aspect_ratio`, `resolution` (and in the future, any Grok-specific flags). Defaults: e.g. `duration: 10`, `aspect_ratio: "16:9"`, `resolution: "720p"`.
- `provider`: for routing (e.g. `"grok"` vs `"kling"`); do not change iOS — routing is backend-only.
- `requires_secondary_photo`: if true and no `secondary_image_url`, return 400. Grok image-to-video currently supports a single source image; if the product later supports two-image effects with Grok, that may require a different mode (e.g. image edit then image-to-video) and should be documented separately.

### 3.3 Generation record and status flow

- **Create** a row in `generations` with `status: "pending"` (and same fields as today: `device_id`, `input_image_url`, `prompt`, etc.).
- **Start** Grok with `POST /v1/videos/generations` (image-to-video: `prompt` + `image_url: input_image_url`).
- Store **`request_id`** (e.g. in `generations` or a provider-specific column) so a poller or the same function can resume polling.
- **Poll** `GET /v1/videos/{request_id}` until `status === "done"` or `status === "expired"` (or timeout).
- On **done:** set `generations.status = "completed"`, `generations.output_video_url = <final URL>`. Prefer downloading the video and uploading to your own storage (e.g. R2) and storing that URL, since xAI URLs are temporary.
- On **expired** or failure: set `generations.status = "failed"` and record error.

No webhook: the existing `generation-webhook` is for ModelsLab; for Grok, use polling (either in the same edge function with a long timeout, or a separate poll job that updates `generations` and triggers Realtime).

### 3.4 Response to client

Return the **same** shape as current `generate-video`:

- `success`, `generation_id`, `status` (`"pending"` | `"processing"` | `"completed"` | `"failed"`), optional `api_response`, `request_id` (log correlation).  
If you return immediately after starting Grok and delegate polling to another process, return `status: "pending"` or `"processing"` and let the client rely on Realtime for final completion.

---

## 4. Quick reference

### 4.1 Video (image-to-video)

- **Start:** `POST https://api.x.ai/v1/videos/generations`  
  Body: `{ model: "grok-imagine-video", prompt, image_url, duration?, aspect_ratio?, resolution? }`  
  Response: `{ request_id }`
- **Poll:** `GET https://api.x.ai/v1/videos/{request_id}`  
  Response: `{ status: "pending"|"done"|"expired", video?: { url, duration, respect_moderation } }`
- **Auth:** `Authorization: Bearer <GROK_API_KEY>`

### 4.2 Image (for future)

- **Generate:** `POST https://api.x.ai/v1/images/generations`  
  Body: `{ model: "grok-imagine-image", prompt, n?, aspect_ratio?, resolution?, response_format? }`
- **Edit:** `POST https://api.x.ai/v1/images/edits`  
  Body: `{ model: "grok-imagine-image", prompt, image: { url, type: "image_url" } }` or `images: [...]`
- **Auth:** same as video.

---

## 5. References

- Image generation: https://docs.x.ai/developers/model-capabilities/images/generation  
- Video generation: https://docs.x.ai/developers/model-capabilities/video/generation  
- REST API reference: https://docs.x.ai/developers/rest-api-reference  
- Models & pricing: https://docs.x.ai/developers/models  

*Document prepared for LLMs implementing the Grok provider; source: official xAI documentation as of 2025.*
