# Supabase Deployment Guide

## Overview

This directory contains everything needed to set up the Supabase backend for the Video Effects App:

- **`migrations/00001_full_schema.sql`** — Complete database schema (tables, indexes, RLS, storage buckets, realtime)
- **`seed.sql`** — System configuration and AI model registry (no content data)
- **`functions/`** — Edge functions (Grok-only, clean of hardcoded credentials)
- **`config.toml`** — Local development configuration

## Project MCP Mapping

For this project, the Cursor MCP server to use is:

- **`supabase-video-gen-app-1`**
- Supabase project ref: **`oquhbidxsntfrqsloocc`**

This is the project-level MCP to use for deployment and Supabase inspection tasks in this repo.

## Tables

### Core
| Table | Purpose |
|-------|---------|
| `devices` | Anonymous device identity |
| `subscription_plans` | Plan tiers and generation limits |
| `device_subscriptions` | Active subscriptions per device |
| `apple_receipts` | Apple IAP transaction records |
| `apple_product_mappings` | Maps Apple product IDs to plans |
| `system_config` | Feature flags and runtime settings |

### Effects & Content
| Table | Purpose |
|-------|---------|
| `effect_categories` | Grouping/tagging for effects |
| `effects` | Effect definitions (prompt templates, params) |
| `video_categories` | Grouping for reference videos |
| `reference_videos` | Video templates for motion control |
| `reference_video_categories` | Many-to-many join table |
| `ai_models` | Registry of available AI models |
| `provider_config` | Per-provider defaults and settings |

### Pipeline Architecture
| Table | Purpose |
|-------|---------|
| `pipeline_templates` | Reusable pipeline definitions |
| `pipeline_steps` | Ordered steps within a pipeline |
| `effect_pipelines` | Links effects to their pipelines |
| `pipeline_executions` | Runtime state of pipeline runs |

### Generation & History
| Table | Purpose |
|-------|---------|
| `generations` | Main work table — tracks every generation |
| `failed_generations` | Dead letter queue for failed jobs |
| `user_videos` | User-uploaded videos |

### Storage Buckets
| Bucket | Purpose |
|--------|---------|
| `portraits` | User-uploaded input images |
| `generated-videos` | Output videos from Grok |
| `reference-videos` | Motion reference videos |
| `user-videos` | User-saved videos |
| `pipeline-artifacts` | Intermediate pipeline step outputs |

## Edge Functions

| Function | Purpose | Auth |
|----------|---------|------|
| `generate-video` | Effect-based video generation (Grok) | JWT |
| `generate-grok-image` | Image generation (Grok Imagine) | JWT |
| `poll-pending-generations` | Cron: poll Grok for completion | Service |
| `check-generation-status` | Check generation status from DB | JWT |
| `generation-webhook` | Provider callback for completion | None |
| `validate-apple-subscription` | Apple IAP validation | JWT |
| `get-device-generations` | Fetch device generation history | JWT |
| `admin-auth` | Admin login and token management | None |
| `admin-templates` | Admin CRUD for templates + R2 upload | Admin |

## Required Environment Variables

Set these as Supabase Edge Function secrets:

```
GROK_API_KEY=          # xAI Grok API key
ADMIN=                 # Admin password for admin-auth
ADMIN_DEVICE_ID=       # Device ID that bypasses subscription checks (optional)
DEBUG_PREMIUM_DEVICE_PREFIX=debug-premium:   # Optional: DEBUG-build premium simulation bypass

# R2 Storage (for admin-templates upload):
R2_ACCOUNT_ID=
R2_BUCKET_NAME=
R2_PUBLIC_DOMAIN=
R2_AUTH_EMAIL=
CLOUDFLARE_API_KEY=
```

## Deployment Steps

1. Connect to your Supabase project via MCP or CLI
2. Run `migrations/00001_full_schema.sql` against the database
3. Run `seed.sql` to populate system configuration
4. Deploy edge functions: `supabase functions deploy --project-ref <ref>`
5. Set secrets: `supabase secrets set GROK_API_KEY=... ADMIN=...`
6. Enable Realtime on the `generations` table (done in migration)
7. Verify storage buckets are created (done in migration)

## Notes

- `admin-auth` and `admin-templates` use `SUPABASE_SERVICE_ROLE_KEY`, so the tightened RLS does not block the admin panel.
- `devices` keeps anon `INSERT`/`SELECT` intentionally because the current iOS `UserVideoService` still registers and looks up device rows directly via PostgREST before saving `user_videos`.
- `DEBUG_PREMIUM_DEVICE_PREFIX` should only be set in development or internal test environments. Release builds do not send this prefix, but if you enable it on a public production backend, any client that can forge that prefix could bypass subscription checks.

## Pipeline Architecture

The pipeline system enables multi-step pre-processing before video generation:

```
Effect selected by user
    ↓
Load effect + linked pipeline (effect_pipelines → pipeline_templates)
    ↓
Execute pipeline_steps in order:
    Step 1: image_enhance (Gemini) — enhance input photo
    Step 2: image_edit (Nanobanana) — apply style rules
    Step 3: prompt_enrich (Gemini) — enhance the prompt
    Step 4: video_generate (Grok) — generate final video
    ↓
Each step stored in pipeline_executions.step_results
    ↓
Final output → generations.output_video_url
```

Effects without a linked pipeline work exactly as before:
input image + prompt template → Grok → video output.
