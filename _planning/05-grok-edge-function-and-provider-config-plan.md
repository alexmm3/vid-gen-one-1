# Plan: Grok Edge Function, Provider Selection, and Provider Config Table

This plan covers: (1) adding a Grok-backed video generation path with the same contract as the current Kling flow, (2) per-effect provider selection (Model Lab vs Grok), and (3) a Supabase configuration table for essential provider parameters so you can tune defaults without code changes.

---

## 1. Goals (recap)

- **Same iOS contract:** Request body and response shape unchanged. No app changes.
- **Grok as alternative provider:** New execution path that uses xAI Grok Imagine API (image-to-video) instead of ModelsLab/Kling.
- **Per-effect provider choice:** Each effect can specify which provider to use (e.g. `kling` or `grok`).
- **Central provider config:** One config table in Supabase to set default duration, quality, and other key parameters for both providers, editable without redeploying code.

**Assumptions:** `GROK_API_KEY` is already in Edge Function secrets. Existing flow (generate-video → webhook or polling) stays for Kling.

---

## 2. High-level flow (unchanged from client perspective)

```
iOS → POST /functions/v1/generate-video
      Body: { device_id, effect_id, input_image_url, secondary_image_url?, user_prompt? }
           ↓
Backend: load effect → validate → subscription check → create generation row
           ↓
         read effect.provider:
           - "kling" (or "modelslab") → call ModelsLab API, webhook or poll by fetch id
           - "grok"                  → call Grok API, store request_id, poll by request_id
           ↓
         Return { success, generation_id, status, ... }  (same shape)
           ↓
Realtime + polling: status moves to "completed" or "failed"
           ↓
iOS: same UI (GeneratingView → ResultView)
```

So the **single entry point** remains `generate-video`. Inside that function we branch on `effect.provider` and call the appropriate provider logic (Kling vs Grok). No second URL for the client.

---

## 3. Per-effect provider selection

The `effects` table already has a `provider` column (e.g. `'kling'`). Use it as the source of truth.

- **Allowed values:** `kling` (or `modelslab`) and `grok`. Any other value can be treated as `kling` for safety.
- **Admin panel:** When editing an effect, show a **Provider** dropdown: “Model Lab (Kling)” | “Grok”. Persist as `provider: 'kling'` or `provider: 'grok'`.
- **Backend:** In `generate-video`, after loading the effect, branch:
  - if `effect.provider === 'grok'` → run Grok path (new code).
  - else → run existing Kling path (current code).

No schema change required for effects; only ensure the admin UI exposes `provider` and that the edge function respects it.

---

## 4. Provider configuration table (Supabase)

Introduce a **single table** that holds global default parameters per provider. Edge functions read it once per request (or cache briefly) and merge with effect-level `generation_params` (effect params override config defaults).

### 4.1 Table schema

```sql
-- Optional: constrain provider to known values
CREATE TABLE public.provider_config (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  provider     text        NOT NULL UNIQUE,   -- 'kling' | 'grok'
  config       jsonb       NOT NULL DEFAULT '{}',
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_config_pkey PRIMARY KEY (id)
);

-- One row per provider. config is a JSON object; keys documented below.
-- Example rows:
-- provider = 'kling', config = '{"default_model_id": "kling-v2-master-i2v", "default_aspect_ratio": "16:9"}'
-- provider = 'grok', config = '{"default_duration": 10, "default_resolution": "720p", "default_aspect_ratio": "16:9", "poll_interval_seconds": 5, "poll_timeout_minutes": 10}'

ALTER TABLE public.provider_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read provider_config" ON public.provider_config FOR SELECT TO public USING (true);
CREATE POLICY "Service role full access" ON public.provider_config FOR ALL TO service_role USING (true) WITH CHECK (true);
```

You can manage `provider_config` from the Supabase SQL editor or from the admin panel (simple form: select provider, edit JSON or key-value fields).

### 4.2 Config keys by provider

**Grok** (`provider = 'grok'`):

| Key | Type | Description | Default (if missing) |
|-----|------|-------------|---------------------|
| `default_duration` | number | Video length in seconds (1–15). | `10` |
| `default_resolution` | string | `"720p"` or `"480p"`. | `"720p"` |
| `default_aspect_ratio` | string | e.g. `"16:9"`, `"9:16"`, `"1:1"`, `"4:3"`, `"3:4"`. | `"16:9"` |
| `poll_interval_seconds` | number | Seconds between status polls. | `5` |
| `poll_timeout_minutes` | number | Max wait before marking generation as failed. | `10` |

**Kling / Model Lab** (`provider = 'kling'`):

| Key | Type | Description | Default (if missing) |
|-----|------|-------------|---------------------|
| `default_model_id` | string | ModelsLab model id, e.g. `kling-v2-master-i2v`. | `"kling-v2-master-i2v"` |
| `default_aspect_ratio` | string | e.g. `"16:9"`, `"9:16"`, `"1:1"` (if supported by model). | `"16:9"` |
| `default_duration` or `num_frames` | number | If the API exposes duration or frame count. | (leave to effect or API default) |

Current code uses `effect.generation_params?.model_id` with fallback `"kling-v2-master-i2v"`. So the **global** fallback can come from `provider_config.config.default_model_id` for `kling`, and effect-level `generation_params.model_id` (or duration/aspect_ratio) can still override.

**Resolution:** Effect row’s `generation_params` (e.g. `duration`, `aspect_ratio`, `resolution`, `model_id`) override the provider_config defaults. Order: **provider_config first, then effect.generation_params override.**

---

## 5. Generations table: support for Grok polling

Grok returns a `request_id` (UUID-like string); Kling uses a numeric `id` in `api_response`. The poller must know both the generation row and the provider-specific id to poll.

**Option A (recommended):** Add a nullable column to `generations`:

- `provider_request_id` (text, nullable): For Grok, store xAI’s `request_id`. For Kling, leave null (continue using `api_response.id`).

Then:

- **Kling:** Keep current behavior: `api_response` stores `{ id, status, ... }`; poll-pending-generations uses `api_response.id` to call ModelsLab fetch.
- **Grok:** When starting Grok, save `provider_request_id = response.request_id` and `status = 'processing'`, and store minimal `api_response` if needed (e.g. `{ provider: 'grok', request_id: '...' }`). Poller uses `provider_request_id` to call `GET https://api.x.ai/v1/videos/{request_id}`.

**Option B:** Store Grok’s `request_id` only inside `api_response` (e.g. `api_response.request_id`) and have the poller branch on a **provider** field. That requires the poller to know which provider each row uses—e.g. add `provider` to `generations` (denormalized from effect at creation time) or re-join to `effects`. Option A avoids joining and keeps a single, explicit column for “external job id”.

**Recommendation:** Add both:

- `generations.provider` (text, nullable): Set at creation from `effect.provider`. Values: `kling`, `grok`. Enables poller to choose polling logic without joining to effects.
- `generations.provider_request_id` (text, nullable): For Grok, xAI’s `request_id`; for Kling, null (use `api_response.id` as today).

Migration:

```sql
ALTER TABLE public.generations
  ADD COLUMN IF NOT EXISTS provider text,
  ADD COLUMN IF NOT EXISTS provider_request_id text;
```

When creating a generation row, set `provider = effect.provider`. When calling Grok, set `provider_request_id = response.request_id` in the same update that sets `status = 'processing'` and `api_response`.

---

## 6. Grok edge function implementation (unified in generate-video)

Implement the Grok path **inside** the existing `generate-video` function (or a shared module it calls) so there is still one endpoint.

### 6.1 Steps (Grok branch)

1. **Read provider config:** Load `provider_config` row where `provider = 'grok'`. Merge `config` with `effect.generation_params` (effect overrides).
2. **Build Grok params:** `prompt` = final prompt (template + user_prompt), `image_url` = `input_image_url`, `duration` = config/default 10, `aspect_ratio` = config/default 16:9, `resolution` = config/default 720p.
3. **Create generation row** (same as today) plus set `provider = 'grok'`.
4. **Call xAI:** `POST https://api.x.ai/v1/videos/generations` with `Authorization: Bearer GROK_API_KEY`. On success, get `request_id`.
5. **Update generation:** Set `status = 'processing'`, `provider_request_id = request_id`, `api_response = { provider: 'grok', request_id }`.
6. **Return to client:** Same JSON as today: `{ success: true, generation_id, status: 'processing', ... }`.

Secondary image: Grok image-to-video currently supports one image. If the effect has `requires_secondary_photo` and we still want to use Grok, you have two options: (a) ignore second image for Grok and document the limitation, or (b) only allow Grok for effects that do not require a second photo. This plan assumes (b) or single-image-only for Grok for now; you can relax later (e.g. composite image or two-step flow).

### 6.2 Polling for Grok (extend poll-pending-generations)

Today `poll-pending-generations` only knows how to poll Kling (using `api_response.id` and ModelsLab fetch URL). Extend it:

1. When selecting rows with `status = 'processing'`, also select `provider` and `provider_request_id`.
2. For each row:
   - If `provider === 'grok'` and `provider_request_id` is set: call `GET https://api.x.ai/v1/videos/{provider_request_id}` with `Authorization: Bearer GROK_API_KEY`. Parse status: `pending` → keep processing; `done` → set `output_video_url` from `video.url`, status `completed`; `expired` → mark failed.
   - Else: existing Kling logic (use `api_response.id`, ModelsLab fetch).

Use **provider_config** for Grok `poll_timeout_minutes` (and optionally `poll_interval_seconds`) so you can mark stale Grok jobs as failed without code changes.

Optional: Download the Grok video URL and re-upload to your storage (e.g. R2) and save that URL as `output_video_url`, so you don’t rely on xAI’s temporary URL.

---

## 7. Webhook (no change for Grok)

`generation-webhook` is called by ModelsLab when a Kling job finishes. Grok does **not** call a webhook. So:

- **Kling:** Keep webhook; optionally keep polling as backup.
- **Grok:** No webhook; rely only on `poll-pending-generations` (or a dedicated Grok poller cron). Ensure the cron runs often enough (e.g. every 1–2 minutes) so that Grok completions show up in a reasonable time.

---

## 8. Summary: what to build

| Item | Action |
|------|--------|
| **DB: provider_config** | New table: `provider`, `config` (jsonb), `updated_at`. One row per provider with keys above. |
| **DB: generations** | Add `provider`, `provider_request_id` (nullable). Set when creating/updating generation. |
| **Effect provider** | Use existing `effects.provider`. Admin: dropdown to choose Kling vs Grok. |
| **generate-video** | After loading effect, branch on `effect.provider`. Grok branch: load provider_config for grok, call xAI, store request_id, return same response shape. Keep Kling path unchanged. |
| **poll-pending-generations** | For `status = 'processing'`, branch on `provider`. If grok, poll xAI with `provider_request_id`; else poll Kling. Apply timeout from provider_config for Grok. |
| **Secrets** | `GROK_API_KEY` already set. No change. |
| **iOS** | No change. Same endpoint, same body, same response. |

---

## 9. Parameters you can control from Supabase (summary)

- **Grok (provider_config for `grok`):** Default video length (`default_duration`), quality (`default_resolution`: 720p/480p), aspect ratio (`default_aspect_ratio`), and polling behavior (`poll_interval_seconds`, `poll_timeout_minutes`).
- **Kling (provider_config for `kling`):** Default model (`default_model_id`), default aspect ratio (`default_aspect_ratio`). Optionally duration/frame-related keys if the ModelsLab API exposes them and you add support.
- **Per-effect overrides:** Existing `effects.generation_params` (e.g. `duration`, `aspect_ratio`, `resolution`, `model_id`) continue to override these global defaults for that effect.

This gives you a single place (Supabase config table + effect-level params) to tune both providers without touching the iOS app or redeploying edge function code for simple value changes.
