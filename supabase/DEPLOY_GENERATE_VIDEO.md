# Deploy `generate-video` Edge Function

Production must run the **bundled** handler from this repo (not a placeholder). The admin panel calls `POST /functions/v1/generate-video` from the browser; that requires **CORS** on `OPTIONS` and `POST` responses.

## 1. Build deploy payloads

From the **repo root**:

```bash
chmod +x supabase/scripts/build-generate-video-deploy-payload.sh
./supabase/scripts/build-generate-video-deploy-payload.sh
```

This writes:

- `supabase/.deploy-generate-video.payload.json` — single `index.ts` MCP payload (~33KB JSON).
- `supabase/.b64-deploy-generate-video.payload.json` — multi-file base64 shim (~43KB JSON), useful if your MCP client chokes on one huge string.

## 2. Deploy via Supabase CLI (recommended)

```bash
export SUPABASE_ACCESS_TOKEN=…   # https://supabase.com/dashboard/account/tokens
npx supabase login --token "$SUPABASE_ACCESS_TOKEN"
npx supabase functions deploy generate-video \
  --project-ref oquhbidxsntfrqsloocc \
  --no-verify-jwt
```

(`verify_jwt` is off because the function uses service role + app logic.)

## 3. Deploy via Cursor Supabase MCP

In Cursor, call **`deploy_edge_function`** on the **`supabase-video-gen-app-1`** (or your linked) project MCP with **`arguments`** exactly equal to `JSON.parse` of:

- `supabase/.deploy-generate-video.payload.json`, **or**
- `supabase/.b64-deploy-generate-video.payload.json`

Ensure `files[*].content` is **not truncated**.

## 4. Playground / subscription

The admin Playground uses `device_id: "admin-playground"`. For that to pass `checkDeviceSubscription`, set either:

- Supabase secret **`ADMIN_DEVICE_ID=admin-playground`**, or  
- **`DEBUG_PREMIUM_DEVICE_PREFIX`** so `admin-playground` matches your debug rule.

## 5. `verify-admin` 401

A **401** from `verify-admin` usually means the **session token** no longer matches **`ADMIN_PASSWORD`** (password rotated) or the token expired—log out and log in again. After changing `ADMIN_PASSWORD`, redeploy `verify-admin`.

## 6. Admin panel CORS helper patch

If browsers still complain on preflight for admin functions, apply `docs/patches/0001-admin-cors-allow-methods.patch` to **vidgen-effects-admin-panel** and redeploy `verify-admin`.
