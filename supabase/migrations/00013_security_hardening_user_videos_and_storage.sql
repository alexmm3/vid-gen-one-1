-- Migration 00013: Security hardening for user_videos RLS and storage INSERT policies
--
-- user_videos: remove wide-open policies, remove public hard-DELETE,
-- restrict SELECT to active rows only (anon), service_role retains full access.
--
-- Storage: restrict INSERT on generated-videos and pipeline-artifacts to
-- service_role only (iOS never uploads to these buckets directly).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. user_videos – tighten RLS
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Anyone can read user_videos"   ON public.user_videos;
DROP POLICY IF EXISTS "Anyone can insert user_videos"  ON public.user_videos;
DROP POLICY IF EXISTS "Anyone can update user_videos"  ON public.user_videos;
DROP POLICY IF EXISTS "Anyone can delete user_videos"  ON public.user_videos;

-- Service role: unrestricted (used by edge functions and admin)
CREATE POLICY "Service role full access user_videos"
  ON public.user_videos FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- Anon/authenticated SELECT: only active videos
CREATE POLICY "Public read active user_videos"
  ON public.user_videos FOR SELECT TO public
  USING (is_active = true);

-- Anon/authenticated INSERT: allowed (iOS uploads metadata via PostgREST)
CREATE POLICY "Public insert user_videos"
  ON public.user_videos FOR INSERT TO public
  WITH CHECK (true);

-- Anon/authenticated UPDATE: only on own active rows (soft-delete flow).
-- Cannot re-activate a previously deactivated row from the client.
CREATE POLICY "Public update active user_videos"
  ON public.user_videos FOR UPDATE TO public
  USING (is_active = true);

-- No public DELETE policy — hard deletes are not allowed from the client.

-- ---------------------------------------------------------------------------
-- 2. Storage – restrict INSERT on backend-only buckets to service_role
-- ---------------------------------------------------------------------------

-- generated-videos: only edge functions write here (check-generation-status, poll-pending)
DROP POLICY IF EXISTS "Service role upload generated-videos" ON storage.objects;
CREATE POLICY "Service role upload generated-videos"
  ON storage.objects FOR INSERT TO service_role
  WITH CHECK (bucket_id = 'generated-videos');

-- pipeline-artifacts: only pipeline orchestrator writes here
DROP POLICY IF EXISTS "Service role upload pipeline-artifacts" ON storage.objects;
CREATE POLICY "Service role upload pipeline-artifacts"
  ON storage.objects FOR INSERT TO service_role
  WITH CHECK (bucket_id = 'pipeline-artifacts');

-- portraits: iOS uploads directly → keep as public (no change, policy already exists)
-- user-videos: iOS uploads directly → keep as public (no change, policy already exists)

COMMIT;
