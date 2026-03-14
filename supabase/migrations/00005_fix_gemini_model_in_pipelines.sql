-- =============================================================================
-- Fix Gemini model in pipeline steps
-- gemini-3.1-flash-lite-preview / gemini-imagen-3.0 may not be available;
-- use gemini-2.0-flash-exp which supports image editing via generateContent
-- =============================================================================

UPDATE public.pipeline_steps
SET config = jsonb_set(
  config,
  '{model}',
  '"gemini-2.0-flash-exp"'
)
WHERE step_type = 'image_enhance'
  AND provider = 'gemini'
  AND (
    config->>'model' = 'gemini-3.1-flash-lite-preview'
    OR config->>'model' = 'gemini-imagen-3.0'
    OR config->>'model' IS NULL
  );
