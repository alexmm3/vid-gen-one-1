-- =============================================================================
-- Set default video duration to 6 seconds
-- Run this once in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/oquhbidxsntfrqsloocc/editor
-- =============================================================================

-- 1. Update global cap in system_config
UPDATE public.system_config
SET value = jsonb_set(value, '{video_max_duration}', '6')
WHERE key = 'generation_globals';

-- 2. Update all pipeline video_generate steps (duration inside config jsonb)
UPDATE public.pipeline_steps
SET config = jsonb_set(config, '{duration}', '6')
WHERE step_type = 'video_generate'
  AND (config->>'duration')::int = 5;

-- 3. Update direct effects (generation_params with duration = 5)
UPDATE public.effects
SET generation_params = jsonb_set(generation_params, '{duration}', '6')
WHERE (generation_params->>'duration')::int = 5;

-- Verify
SELECT 'system_config' AS source, value->>'video_max_duration' AS duration
FROM public.system_config WHERE key = 'generation_globals'
UNION ALL
SELECT 'pipeline_step: ' || ps.name, ps.config->>'duration'
FROM public.pipeline_steps ps
WHERE ps.step_type = 'video_generate'
UNION ALL
SELECT 'effect: ' || e.name, e.generation_params->>'duration'
FROM public.effects e
WHERE e.generation_params ? 'duration';
