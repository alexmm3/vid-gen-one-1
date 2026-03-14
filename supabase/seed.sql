-- =============================================================================
-- Seed Data — System Configuration & AI Model Registry
-- =============================================================================
-- This file contains ONLY structural configuration data needed for the
-- application to function. No effects, no videos, no user content.
-- =============================================================================

-- System config: subscription checking disabled by default for development
INSERT INTO public.system_config (key, value, description)
VALUES
  ('subscription_check_enabled', 'false', 'Enable/disable subscription validation on generation requests'),
  ('maintenance_mode', 'false', 'When true, all generation requests are rejected with a maintenance message')
ON CONFLICT (key) DO NOTHING;

-- AI Models: register the Grok model(s)
INSERT INTO public.ai_models (id, name, provider, model_type, is_active, config)
VALUES
  ('grok-imagine-video', 'Grok Imagine Video', 'grok', 'video', true, '{"default_duration": 10, "default_resolution": "720p", "default_aspect_ratio": "9:16"}'),
  ('grok-imagine-image', 'Grok Imagine Image', 'grok', 'image', true, '{"default_aspect_ratio": "9:16"}')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  provider = EXCLUDED.provider,
  model_type = EXCLUDED.model_type;

-- Provider config: Grok defaults
INSERT INTO public.provider_config (provider, config, is_active)
VALUES
  ('grok', '{
    "default_model_id": "grok-imagine-video",
    "default_duration": 10,
    "default_resolution": "720p",
    "default_aspect_ratio": "9:16",
    "poll_timeout_minutes": 10,
    "poll_interval_seconds": 15
  }', true)
ON CONFLICT (provider) DO UPDATE SET
  config = EXCLUDED.config;

-- =============================================================================
-- DONE. Base configuration seeded.
-- =============================================================================
