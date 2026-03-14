-- =============================================================================
-- Fix ALL model references to current API-available models (March 2026)
-- =============================================================================
-- Models retired:
--   gemini-2.0-flash-exp          -> gemini-3.1-flash-image-preview
--   gemini-3.1-flash-lite-preview -> gemini-3.1-flash-image-preview
--   gemini-imagen-3.0             -> gemini-3.1-flash-image-preview
--   grok-2-vision-1212            -> grok-4-1-fast-non-reasoning
-- =============================================================================

-- 1. Fix all pipeline_steps with stale Gemini models
UPDATE public.pipeline_steps
SET config = jsonb_set(config, '{model}', '"gemini-3.1-flash-image-preview"')
WHERE step_type = 'image_enhance'
  AND provider = 'gemini'
  AND config->>'model' IN (
    'gemini-2.0-flash-exp',
    'gemini-3.1-flash-lite-preview',
    'gemini-imagen-3.0',
    'gemini-2.5-flash-image'
  );

-- 2. Fix all pipeline_steps with stale Grok vision models
UPDATE public.pipeline_steps
SET config = jsonb_set(config, '{model}', '"grok-4-1-fast-non-reasoning"')
WHERE step_type = 'image_analyze'
  AND provider = 'grok'
  AND config->>'model' IN (
    'grok-2-vision-1212',
    'grok-2-vision',
    'grok-2-vision-latest',
    'grok-vision-beta'
  );

-- 3. Update ai_models registry
UPDATE public.ai_models
SET name = 'Gemini 3.1 Flash Image (Image Edit)', id = 'gemini-3.1-flash-image-preview'
WHERE id = 'gemini-2.0-flash-exp';

INSERT INTO public.ai_models (id, name, provider, model_type, is_active, config)
VALUES ('gemini-3.1-flash-image-preview', 'Gemini 3.1 Flash Image (Image Edit)', 'gemini', 'image', true, '{}')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, is_active = true;

INSERT INTO public.ai_models (id, name, provider, model_type, is_active, config)
VALUES ('grok-4-1-fast-non-reasoning', 'Grok 4.1 Fast (Vision / Text)', 'grok', 'vision', true, '{}')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, is_active = true;

-- Mark retired models as inactive
UPDATE public.ai_models SET is_active = false
WHERE id IN ('grok-vision', 'grok-text', 'gemini-imagen-3.0');

-- 4. Update provider_config with current defaults
UPDATE public.provider_config
SET config = jsonb_set(
  jsonb_set(config, '{default_model}', '"gemini-3.1-flash-image-preview"'),
  '{image_edit_model}', '"gemini-3.1-flash-image-preview"'
)
WHERE provider = 'gemini';
