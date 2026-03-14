-- =============================================================================
-- Generation Globals — centralized config for all generations
-- =============================================================================
-- Lives in system_config with key = 'generation_globals'.
-- All values are optional; null means "use pipeline/effect/provider defaults".
-- Non-null values override ALL pipelines and direct generation calls.
-- =============================================================================

INSERT INTO public.system_config (key, value, description)
VALUES (
  'generation_globals',
  '{
    "video_resolution": "480p",
    "video_max_duration": 5,
    "video_aspect_ratio": null,
    "image_enhance_enabled": true,
    "image_analyze_enabled": true,
    "prompt_enrich_enabled": true,
    "image_enhance_model": null,
    "image_analyze_model": null,
    "prompt_enrich_model": null,
    "video_generate_model": null,
    "pipelines_enabled": true
  }'::jsonb,
  'Global overrides for ALL generations. null = use pipeline/effect defaults. Set video_resolution to 480p for testing (cheaper/faster), 720p for production.'
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description;
