-- =============================================================================
-- 00012_subscription_security_hardening.sql
-- =============================================================================
-- Closes public write access to subscription-critical tables and introduces
-- an atomic generation-slot reservation function to prevent quota races.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tighten RLS on sensitive business tables
-- ---------------------------------------------------------------------------

-- devices
DROP POLICY IF EXISTS "Anyone can insert devices" ON public.devices;
DROP POLICY IF EXISTS "Anyone can read devices" ON public.devices;
DROP POLICY IF EXISTS "Anyone can update their device" ON public.devices;
DROP POLICY IF EXISTS "Public can register devices" ON public.devices;
DROP POLICY IF EXISTS "Public can read device lookup" ON public.devices;
DROP POLICY IF EXISTS "Service role manages devices" ON public.devices;

CREATE POLICY "Public can register devices"
  ON public.devices FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Public can read device lookup"
  ON public.devices FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages devices"
  ON public.devices FOR ALL TO service_role USING (true) WITH CHECK (true);

-- system_config
DROP POLICY IF EXISTS "Anyone can read config" ON public.system_config;
DROP POLICY IF EXISTS "Service role manages config" ON public.system_config;

CREATE POLICY "Service role manages config"
  ON public.system_config FOR ALL TO service_role USING (true) WITH CHECK (true);

-- device_subscriptions
DROP POLICY IF EXISTS "Anyone can insert subscriptions" ON public.device_subscriptions;
DROP POLICY IF EXISTS "Anyone can read subscriptions" ON public.device_subscriptions;
DROP POLICY IF EXISTS "Service role manages subscriptions" ON public.device_subscriptions;

CREATE POLICY "Service role manages subscriptions"
  ON public.device_subscriptions FOR ALL TO service_role USING (true) WITH CHECK (true);

-- apple_receipts
DROP POLICY IF EXISTS "Service role can manage apple_receipts" ON public.apple_receipts;
DROP POLICY IF EXISTS "Service role manages apple_receipts" ON public.apple_receipts;

CREATE POLICY "Service role manages apple_receipts"
  ON public.apple_receipts FOR ALL TO service_role USING (true) WITH CHECK (true);

-- apple_product_mappings
DROP POLICY IF EXISTS "Anyone can read product mappings" ON public.apple_product_mappings;
DROP POLICY IF EXISTS "Service role manages product mappings" ON public.apple_product_mappings;

CREATE POLICY "Service role manages product mappings"
  ON public.apple_product_mappings FOR ALL TO service_role USING (true) WITH CHECK (true);

-- generations
DROP POLICY IF EXISTS "Anyone can insert generations" ON public.generations;
DROP POLICY IF EXISTS "Anyone can read generations" ON public.generations;
DROP POLICY IF EXISTS "Anyone can update generations" ON public.generations;
DROP POLICY IF EXISTS "Service role manages generations" ON public.generations;

CREATE POLICY "Service role manages generations"
  ON public.generations FOR ALL TO service_role USING (true) WITH CHECK (true);

-- pipeline_executions
DROP POLICY IF EXISTS "Anyone can read pipeline_executions" ON public.pipeline_executions;
DROP POLICY IF EXISTS "Service role manages pipeline_executions" ON public.pipeline_executions;

CREATE POLICY "Service role manages pipeline_executions"
  ON public.pipeline_executions FOR ALL TO service_role USING (true) WITH CHECK (true);

-- failed_generations
DROP POLICY IF EXISTS "Anyone can read failed generations" ON public.failed_generations;
DROP POLICY IF EXISTS "Service role manages failed_generations" ON public.failed_generations;

CREATE POLICY "Service role manages failed_generations"
  ON public.failed_generations FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- 2. Quota reservation helper
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_generations_device_id_created_at
  ON public.generations (device_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.reserve_generation_slot(
  p_device_id uuid,
  p_effect_id uuid,
  p_input_image_url text,
  p_secondary_image_url text,
  p_reference_video_url text,
  p_prompt text,
  p_provider text,
  p_request_id text,
  p_input_payload jsonb,
  p_character_orientation text,
  p_copy_audio boolean,
  p_error_log jsonb,
  p_enforce_limit boolean,
  p_generation_limit integer,
  p_period_days integer
)
RETURNS TABLE (
  reserved boolean,
  generation_id uuid,
  status text,
  pipeline_execution_id uuid,
  generations_used integer,
  generations_remaining integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_used integer := 0;
  v_generation public.generations%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_device_id::text, 0));

  IF p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_days IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_used
      FROM public.generations
     WHERE device_id = p_device_id
       AND created_at >= (now() - make_interval(days => p_period_days));

    IF v_used >= p_generation_limit THEN
      RETURN QUERY
      SELECT
        false,
        NULL::uuid,
        NULL::text,
        NULL::uuid,
        v_used,
        GREATEST(p_generation_limit - v_used, 0);
      RETURN;
    END IF;
  END IF;

  INSERT INTO public.generations (
    device_id,
    effect_id,
    input_image_url,
    secondary_image_url,
    reference_video_url,
    prompt,
    status,
    provider,
    request_id,
    input_payload,
    character_orientation,
    copy_audio,
    error_log
  )
  VALUES (
    p_device_id,
    p_effect_id,
    p_input_image_url,
    p_secondary_image_url,
    p_reference_video_url,
    p_prompt,
    'pending',
    p_provider,
    p_request_id,
    COALESCE(p_input_payload, '{}'::jsonb),
    COALESCE(p_character_orientation, 'image'),
    COALESCE(p_copy_audio, false),
    COALESCE(p_error_log, '[]'::jsonb)
  )
  RETURNING *
    INTO v_generation;

  RETURN QUERY
  SELECT
    true,
    v_generation.id,
    v_generation.status,
    v_generation.pipeline_execution_id,
    CASE
      WHEN p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_days IS NOT NULL THEN v_used
      ELSE NULL
    END,
    CASE
      WHEN p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_days IS NOT NULL
        THEN GREATEST(p_generation_limit - v_used - 1, 0)
      ELSE -1
    END;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, integer) FROM anon;
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, integer) TO service_role;
