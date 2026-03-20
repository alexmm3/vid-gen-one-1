-- =============================================================================
-- 00014_subscription_weekly_monthly_overhaul.sql
-- =============================================================================
-- Overhauls subscription plans: deactivates Yearly, upserts Weekly & Monthly,
-- drops price_cents (prices live in App Store Connect), and adds a new
-- reserve_generation_slot overload with subscription-anchored counting.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add UNIQUE constraint on subscription_plans.name (needed for upserts)
-- ---------------------------------------------------------------------------

ALTER TABLE public.subscription_plans
  ADD CONSTRAINT subscription_plans_name_key UNIQUE (name);

-- ---------------------------------------------------------------------------
-- 2. Deactivate the Yearly plan (preserve FK integrity — no DELETE)
-- ---------------------------------------------------------------------------

UPDATE public.subscription_plans
   SET is_active = false
 WHERE LOWER(name) = 'yearly';

-- ---------------------------------------------------------------------------
-- 3. Upsert Weekly plan
-- ---------------------------------------------------------------------------

INSERT INTO public.subscription_plans (name, generation_limit, period_days, is_active)
VALUES ('Weekly', 10, 7, true)
ON CONFLICT (name) DO UPDATE
  SET generation_limit = EXCLUDED.generation_limit,
      period_days      = EXCLUDED.period_days,
      is_active        = EXCLUDED.is_active;

-- ---------------------------------------------------------------------------
-- 4. Upsert Monthly plan
-- ---------------------------------------------------------------------------

INSERT INTO public.subscription_plans (name, generation_limit, period_days, is_active)
VALUES ('Monthly', 50, 30, true)
ON CONFLICT (name) DO UPDATE
  SET generation_limit = EXCLUDED.generation_limit,
      period_days      = EXCLUDED.period_days,
      is_active        = EXCLUDED.is_active;

-- ---------------------------------------------------------------------------
-- 5. Drop price_cents column (prices live in App Store Connect only)
-- ---------------------------------------------------------------------------

ALTER TABLE public.subscription_plans
  DROP COLUMN IF EXISTS price_cents;

-- ---------------------------------------------------------------------------
-- 6. New reserve_generation_slot overload with subscription-anchored counting
--    Last param: p_period_start timestamptz  (instead of p_period_days integer)
--    Old overload is kept alive for backward compatibility during transition.
-- ---------------------------------------------------------------------------

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
  p_period_start timestamptz
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

  IF p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_start IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_used
      FROM public.generations
     WHERE device_id = p_device_id
       AND created_at >= p_period_start;

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
      WHEN p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_start IS NOT NULL THEN v_used
      ELSE NULL
    END,
    CASE
      WHEN p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_start IS NOT NULL
        THEN GREATEST(p_generation_limit - v_used - 1, 0)
      ELSE -1
    END;
END;
$$;

-- Revoke/grant for the NEW overload (timestamptz signature)
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) TO service_role;
