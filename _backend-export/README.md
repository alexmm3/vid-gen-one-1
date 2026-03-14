# Backend Export — Video Effects App

Self-contained export of the Supabase backend for deployment to a new project.

## Contents

- `schema.sql` — Complete database schema (all tables, indexes, RLS, storage buckets, realtime)
- `edge-functions/` — All edge functions (Grok-only, no hardcoded credentials)

## Deployment

1. Run `schema.sql` against a fresh Supabase project database
2. Run `../supabase/seed.sql` for system configuration
3. Deploy edge functions from `../supabase/functions/`
4. Set environment secrets (see `../supabase/.env.example`)

## Provider

This deployment uses **Grok (xAI)** exclusively for both image and video generation.
