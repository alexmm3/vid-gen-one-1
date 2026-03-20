-- =============================================================================
-- Migration 00011: Enable scheduled generation polling and state reconciliation
--
-- Purpose:
-- 1. Enable pg_net and pg_cron for background Edge Function invocation
-- 2. Schedule poll-pending-generations every minute
-- 3. Reconcile stale pending generations and pipeline/generation status drift
--
-- NOTE:
-- The scheduled poller assumes `poll-pending-generations` is deployed with
-- verify_jwt = false because it is a service/cron worker, not a user endpoint.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE SCHEMA IF NOT EXISTS util;

CREATE OR REPLACE FUNCTION util.invoke_poll_pending_generations()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  request_id bigint;
BEGIN
  SELECT net.http_post(
    url := 'https://oquhbidxsntfrqsloocc.supabase.co/functions/v1/poll-pending-generations',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{}'::jsonb,
    timeout_milliseconds := 300000
  )
  INTO request_id;

  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_generation_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  stale_pending_failed_count integer := 0;
  pipeline_completed_fixed_count integer := 0;
  pipeline_failed_fixed_count integer := 0;
BEGIN
  WITH stale_pending AS (
    UPDATE public.generations AS g
    SET
      status = 'failed',
      error_message = COALESCE(g.error_message, 'Generation never started processing'),
      last_error_at = COALESCE(g.last_error_at, now())
    WHERE g.status = 'pending'
      AND g.created_at < now() - interval '15 minutes'
      AND g.provider_request_id IS NULL
      AND g.pipeline_execution_id IS NULL
    RETURNING g.id, g.device_id, g.error_message, COALESCE(g.retry_count, 0) AS retry_count
  )
  INSERT INTO public.failed_generations (
    original_generation_id,
    device_id,
    failure_reason,
    final_error_message,
    error_log,
    retry_count
  )
  SELECT
    sp.id,
    sp.device_id,
    'stale_pending_generation',
    sp.error_message,
    '[]'::jsonb,
    sp.retry_count
  FROM stale_pending sp
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.failed_generations fg
    WHERE fg.original_generation_id = sp.id
  );

  GET DIAGNOSTICS stale_pending_failed_count = ROW_COUNT;

  UPDATE public.pipeline_executions pe
  SET
    status = 'completed',
    completed_at = COALESCE(pe.completed_at, now()),
    error_message = NULL
  FROM public.generations g
  WHERE pe.id = g.pipeline_execution_id
    AND g.status = 'completed'
    AND pe.status IN ('pending', 'running', 'step_completed');

  GET DIAGNOSTICS pipeline_completed_fixed_count = ROW_COUNT;

  UPDATE public.pipeline_executions pe
  SET
    status = 'failed',
    completed_at = COALESCE(pe.completed_at, now()),
    error_message = COALESCE(pe.error_message, g.error_message, 'Generation failed')
  FROM public.generations g
  WHERE pe.id = g.pipeline_execution_id
    AND g.status = 'failed'
    AND pe.status IN ('pending', 'running', 'step_completed');

  GET DIAGNOSTICS pipeline_failed_fixed_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'stale_pending_failed_count', stale_pending_failed_count,
    'pipeline_completed_fixed_count', pipeline_completed_fixed_count,
    'pipeline_failed_fixed_count', pipeline_failed_fixed_count
  );
END;
$$;

DO $$
DECLARE
  poll_job_id bigint;
  reconcile_job_id bigint;
BEGIN
  SELECT jobid INTO poll_job_id
  FROM cron.job
  WHERE jobname = 'poll-pending-generations-every-minute'
  LIMIT 1;

  IF poll_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(poll_job_id);
  END IF;

  SELECT jobid INTO reconcile_job_id
  FROM cron.job
  WHERE jobname = 'reconcile-generation-state-every-5-minutes'
  LIMIT 1;

  IF reconcile_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(reconcile_job_id);
  END IF;
END $$;

SELECT cron.schedule(
  'poll-pending-generations-every-minute',
  '* * * * *',
  $$SELECT util.invoke_poll_pending_generations();$$
);

SELECT cron.schedule(
  'reconcile-generation-state-every-5-minutes',
  '*/5 * * * *',
  $$SELECT public.reconcile_generation_state();$$
);

COMMIT;
