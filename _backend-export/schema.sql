-- =============================================================================
-- Video Effects App — Complete Database Schema
-- =============================================================================
-- Clean schema for a new Supabase project.
-- Includes: core tables, effects system, advanced pipeline architecture,
-- subscription/IAP, admin support, storage buckets, RLS, and realtime.
--
-- NO seed data, NO content, NO videos — pure structure only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto"  WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- 2. Helper Functions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Core Tables (ordered by foreign-key dependencies)
-- ---------------------------------------------------------------------------

-- 3.1 devices — anonymous device identity (no user accounts)
CREATE TABLE public.devices (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  device_id   text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT devices_pkey PRIMARY KEY (id),
  CONSTRAINT devices_device_id_key UNIQUE (device_id)
);

-- 3.2 subscription_plans — defines plan tiers and limits
CREATE TABLE public.subscription_plans (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  name             text        NOT NULL,
  generation_limit integer     NOT NULL DEFAULT 10,
  created_at       timestamptz NOT NULL DEFAULT now(),
  period_days      integer,
  description      text,
  is_active        boolean     NOT NULL DEFAULT true,
  price_cents      integer,
  apple_product_id text,
  CONSTRAINT subscription_plans_pkey PRIMARY KEY (id)
);

-- 3.3 system_config — runtime feature flags and settings
CREATE TABLE public.system_config (
  key         text        NOT NULL,
  value       jsonb       NOT NULL,
  description text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT system_config_pkey PRIMARY KEY (key)
);

-- 3.4 device_subscriptions
CREATE TABLE public.device_subscriptions (
  id                      uuid        NOT NULL DEFAULT gen_random_uuid(),
  device_id               uuid        NOT NULL,
  plan_id                 uuid        NOT NULL,
  started_at              timestamptz NOT NULL DEFAULT now(),
  expires_at              timestamptz,
  created_at              timestamptz NOT NULL DEFAULT now(),
  original_transaction_id text,
  CONSTRAINT device_subscriptions_pkey PRIMARY KEY (id),
  CONSTRAINT device_subscriptions_device_id_unique UNIQUE (device_id),
  CONSTRAINT device_subscriptions_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES public.devices(id),
  CONSTRAINT device_subscriptions_plan_id_fkey
    FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(id)
);

-- 3.5 apple_receipts — stores Apple IAP transaction data
CREATE TABLE public.apple_receipts (
  id                      uuid        NOT NULL DEFAULT gen_random_uuid(),
  device_id               uuid        NOT NULL,
  original_transaction_id text        NOT NULL,
  product_id              text        NOT NULL,
  expires_at              timestamptz NOT NULL,
  environment             text        NOT NULL DEFAULT 'Production'::text,
  last_verified_at        timestamptz NOT NULL DEFAULT now(),
  raw_transaction_info    jsonb,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT apple_receipts_pkey PRIMARY KEY (id),
  CONSTRAINT apple_receipts_device_id_original_transaction_id_key
    UNIQUE (device_id, original_transaction_id),
  CONSTRAINT apple_receipts_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES public.devices(id)
);

-- 3.6 apple_product_mappings — maps Apple product IDs to plans
CREATE TABLE public.apple_product_mappings (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  apple_product_id text        NOT NULL,
  plan_id          uuid        NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT apple_product_mappings_pkey PRIMARY KEY (id),
  CONSTRAINT apple_product_mappings_apple_product_id_key UNIQUE (apple_product_id),
  CONSTRAINT apple_product_mappings_plan_id_fkey
    FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(id)
);

-- ---------------------------------------------------------------------------
-- 4. Categories
-- ---------------------------------------------------------------------------

-- 4.1 effect_categories — grouping for effects
CREATE TABLE public.effect_categories (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  name         text        NOT NULL,
  display_name text        NOT NULL,
  sort_order   integer     NOT NULL DEFAULT 0,
  icon         text,
  is_active    boolean     NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT effect_categories_pkey PRIMARY KEY (id),
  CONSTRAINT effect_categories_name_key UNIQUE (name)
);

-- 4.2 video_categories — grouping for reference videos/templates
CREATE TABLE public.video_categories (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  name         text        NOT NULL,
  display_name text        NOT NULL,
  sort_order   integer              DEFAULT 0,
  icon         text,
  is_active    boolean              DEFAULT true,
  created_at   timestamptz          DEFAULT now(),
  CONSTRAINT video_categories_pkey PRIMARY KEY (id),
  CONSTRAINT video_categories_name_key UNIQUE (name)
);

-- ---------------------------------------------------------------------------
-- 5. AI Models & Provider Config
-- ---------------------------------------------------------------------------

-- 5.1 ai_models — registry of available AI models
CREATE TABLE public.ai_models (
  id         text        NOT NULL,
  name       text        NOT NULL,
  provider   text        NOT NULL,
  model_type text        NOT NULL DEFAULT 'video',
  is_active  boolean     NOT NULL DEFAULT true,
  config     jsonb       NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ai_models_pkey PRIMARY KEY (id)
);

-- 5.2 provider_config — per-provider defaults and settings
CREATE TABLE public.provider_config (
  id         uuid        NOT NULL DEFAULT gen_random_uuid(),
  provider   text        NOT NULL,
  config     jsonb       NOT NULL DEFAULT '{}',
  is_active  boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_config_pkey PRIMARY KEY (id),
  CONSTRAINT provider_config_provider_key UNIQUE (provider)
);

-- ---------------------------------------------------------------------------
-- 6. Effects System
-- ---------------------------------------------------------------------------

-- 6.1 effects — the core effect definitions
CREATE TABLE public.effects (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  name                     text        NOT NULL,
  description              text,
  preview_video_url        text,
  thumbnail_url            text,
  category_id              uuid,
  is_active                boolean     NOT NULL DEFAULT true,
  is_premium               boolean     NOT NULL DEFAULT false,
  sort_order               integer     NOT NULL DEFAULT 0,
  requires_secondary_photo boolean     NOT NULL DEFAULT false,
  system_prompt_template   text        NOT NULL,
  provider                 text        NOT NULL DEFAULT 'grok',
  ai_model_id              text,
  generation_params        jsonb       NOT NULL DEFAULT '{}',
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT effects_pkey PRIMARY KEY (id),
  CONSTRAINT effects_category_id_fkey
    FOREIGN KEY (category_id) REFERENCES public.effect_categories(id),
  CONSTRAINT effects_ai_model_id_fkey
    FOREIGN KEY (ai_model_id) REFERENCES public.ai_models(id)
);

-- ---------------------------------------------------------------------------
-- 7. Pipeline Architecture (advanced pre-processing)
-- ---------------------------------------------------------------------------

-- 7.1 pipeline_templates — reusable pipeline definitions
--     Each defines an ordered sequence of steps to run before/during generation.
CREATE TABLE public.pipeline_templates (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  name        text        NOT NULL,
  description text,
  version     integer     NOT NULL DEFAULT 1,
  is_active   boolean     NOT NULL DEFAULT true,
  created_by  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pipeline_templates_pkey PRIMARY KEY (id)
);

-- 7.2 pipeline_steps — individual steps within a pipeline template
--     step_type examples: 'image_enhance', 'image_edit', 'image_generate',
--                         'prompt_enrich', 'video_generate', 'conditional'
--     provider examples: 'grok', 'gemini', 'nanobanana', 'openai', ...
CREATE TABLE public.pipeline_steps (
  id              uuid        NOT NULL DEFAULT gen_random_uuid(),
  pipeline_id     uuid        NOT NULL,
  step_order      integer     NOT NULL DEFAULT 0,
  step_type       text        NOT NULL,
  name            text        NOT NULL,
  description     text,
  provider        text        NOT NULL,
  config          jsonb       NOT NULL DEFAULT '{}',
  input_mapping   jsonb       NOT NULL DEFAULT '{}',
  output_mapping  jsonb       NOT NULL DEFAULT '{}',
  is_required     boolean     NOT NULL DEFAULT true,
  timeout_seconds integer     NOT NULL DEFAULT 120,
  retry_config    jsonb       NOT NULL DEFAULT '{"max_retries": 2, "backoff_ms": 5000}',
  is_active       boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pipeline_steps_pkey PRIMARY KEY (id),
  CONSTRAINT pipeline_steps_pipeline_id_fkey
    FOREIGN KEY (pipeline_id) REFERENCES public.pipeline_templates(id) ON DELETE CASCADE,
  CONSTRAINT pipeline_steps_unique_order UNIQUE (pipeline_id, step_order)
);

-- 7.3 effect_pipelines — links effects to their pipeline templates
--     An effect can have one active pipeline at a time.
CREATE TABLE public.effect_pipelines (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  effect_id    uuid        NOT NULL,
  pipeline_id  uuid        NOT NULL,
  is_active    boolean     NOT NULL DEFAULT true,
  priority     integer     NOT NULL DEFAULT 0,
  config_overrides jsonb   NOT NULL DEFAULT '{}',
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT effect_pipelines_pkey PRIMARY KEY (id),
  CONSTRAINT effect_pipelines_effect_id_fkey
    FOREIGN KEY (effect_id) REFERENCES public.effects(id) ON DELETE CASCADE,
  CONSTRAINT effect_pipelines_pipeline_id_fkey
    FOREIGN KEY (pipeline_id) REFERENCES public.pipeline_templates(id)
);

-- 7.4 pipeline_executions — runtime state of a pipeline run
CREATE TABLE public.pipeline_executions (
  id              uuid        NOT NULL DEFAULT gen_random_uuid(),
  generation_id   uuid        NOT NULL,
  pipeline_id     uuid        NOT NULL,
  status          text        NOT NULL DEFAULT 'pending',
  current_step    integer     NOT NULL DEFAULT 0,
  total_steps     integer     NOT NULL DEFAULT 0,
  step_results    jsonb       NOT NULL DEFAULT '[]',
  context         jsonb       NOT NULL DEFAULT '{}',
  started_at      timestamptz,
  completed_at    timestamptz,
  error_message   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pipeline_executions_pkey PRIMARY KEY (id),
  CONSTRAINT pipeline_executions_pipeline_id_fkey
    FOREIGN KEY (pipeline_id) REFERENCES public.pipeline_templates(id),
  CONSTRAINT pipeline_executions_status_check
    CHECK (status = ANY (ARRAY['pending', 'running', 'step_completed', 'completed', 'failed', 'cancelled']))
);

-- ---------------------------------------------------------------------------
-- 8. Reference Videos & Templates (for motion-control / template-based gen)
-- ---------------------------------------------------------------------------

CREATE TABLE public.reference_videos (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  name             text        NOT NULL,
  description      text,
  video_url        text        NOT NULL,
  thumbnail_url    text,
  duration_seconds integer,
  is_active        boolean     NOT NULL DEFAULT true,
  sort_order       integer     NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  category_id      uuid,
  preview_url      text,
  CONSTRAINT reference_videos_pkey PRIMARY KEY (id),
  CONSTRAINT reference_videos_category_id_fkey
    FOREIGN KEY (category_id) REFERENCES public.video_categories(id)
);

CREATE TABLE public.reference_video_categories (
  id                 uuid        NOT NULL DEFAULT gen_random_uuid(),
  reference_video_id uuid        NOT NULL,
  category_id        uuid        NOT NULL,
  created_at         timestamptz          DEFAULT now(),
  sort_order         integer     NOT NULL DEFAULT 0,
  CONSTRAINT reference_video_categories_pkey PRIMARY KEY (id),
  CONSTRAINT reference_video_categories_reference_video_id_category_id_key
    UNIQUE (reference_video_id, category_id),
  CONSTRAINT reference_video_categories_reference_video_id_fkey
    FOREIGN KEY (reference_video_id) REFERENCES public.reference_videos(id),
  CONSTRAINT reference_video_categories_category_id_fkey
    FOREIGN KEY (category_id) REFERENCES public.video_categories(id)
);

-- ---------------------------------------------------------------------------
-- 9. Generations — the main work table
-- ---------------------------------------------------------------------------

CREATE TABLE public.generations (
  id                    uuid        NOT NULL DEFAULT gen_random_uuid(),
  device_id             uuid        NOT NULL,
  status                text        NOT NULL DEFAULT 'pending',
  input_image_url       text        NOT NULL,
  reference_video_url   text,
  secondary_image_url   text,
  output_video_url      text,
  prompt                text,
  effect_id             uuid,
  provider              text,
  provider_request_id   text,
  input_payload         jsonb,
  character_orientation text        NOT NULL DEFAULT 'image',
  copy_audio            boolean     NOT NULL DEFAULT false,
  api_response          jsonb,
  error_message         text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  retry_count           integer     NOT NULL DEFAULT 0,
  max_retries           integer     NOT NULL DEFAULT 3,
  last_error_at         timestamptz,
  error_log             jsonb       NOT NULL DEFAULT '[]',
  poll_count            integer     NOT NULL DEFAULT 0,
  last_polled_at        timestamptz,
  request_id            text,
  CONSTRAINT generations_pkey PRIMARY KEY (id),
  CONSTRAINT generations_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES public.devices(id),
  CONSTRAINT generations_effect_id_fkey
    FOREIGN KEY (effect_id) REFERENCES public.effects(id),
  CONSTRAINT generations_status_check
    CHECK (status = ANY (ARRAY['pending', 'processing', 'completed', 'failed'])),
  CONSTRAINT generations_character_orientation_check
    CHECK (character_orientation = ANY (ARRAY['image', 'video']))
);

-- Add pipeline_execution FK after both tables exist
ALTER TABLE public.pipeline_executions
  ADD CONSTRAINT pipeline_executions_generation_id_fkey
    FOREIGN KEY (generation_id) REFERENCES public.generations(id);

-- 9.1 failed_generations — dead letter queue
CREATE TABLE public.failed_generations (
  id                      uuid        NOT NULL DEFAULT gen_random_uuid(),
  original_generation_id  uuid        NOT NULL,
  device_id               uuid        NOT NULL,
  failure_reason          text        NOT NULL,
  final_error_message     text,
  error_log               jsonb       NOT NULL DEFAULT '[]',
  api_response            jsonb,
  retry_count             integer     NOT NULL DEFAULT 0,
  created_at              timestamptz NOT NULL DEFAULT now(),
  can_retry               boolean     NOT NULL DEFAULT true,
  retried_at              timestamptz,
  notes                   text,
  CONSTRAINT failed_generations_pkey PRIMARY KEY (id),
  CONSTRAINT failed_generations_original_generation_id_fkey
    FOREIGN KEY (original_generation_id) REFERENCES public.generations(id),
  CONSTRAINT failed_generations_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES public.devices(id)
);

-- ---------------------------------------------------------------------------
-- 10. User Videos
-- ---------------------------------------------------------------------------

CREATE TABLE public.user_videos (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  device_id        uuid        NOT NULL,
  name             text        NOT NULL,
  video_url        text        NOT NULL,
  thumbnail_url    text,
  duration_seconds integer,
  file_size_bytes  bigint,
  is_active        boolean              DEFAULT true,
  created_at       timestamptz          DEFAULT now(),
  updated_at       timestamptz          DEFAULT now(),
  CONSTRAINT user_videos_pkey PRIMARY KEY (id),
  CONSTRAINT user_videos_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES public.devices(id)
);

-- ---------------------------------------------------------------------------
-- 11. Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX idx_apple_receipts_device_id
  ON public.apple_receipts USING btree (device_id);
CREATE INDEX idx_apple_receipts_expires_at
  ON public.apple_receipts USING btree (expires_at);
CREATE INDEX idx_apple_receipts_original_transaction_id
  ON public.apple_receipts USING btree (original_transaction_id);

CREATE INDEX idx_generations_status_pending
  ON public.generations USING btree (status)
  WHERE (status = 'pending');
CREATE INDEX idx_generations_status_processing
  ON public.generations USING btree (status)
  WHERE (status = 'processing');
CREATE INDEX idx_generations_device_id
  ON public.generations USING btree (device_id);
CREATE INDEX idx_generations_effect_id
  ON public.generations USING btree (effect_id);

CREATE INDEX idx_effects_category_id
  ON public.effects USING btree (category_id);
CREATE INDEX idx_effects_is_active
  ON public.effects USING btree (is_active)
  WHERE (is_active = true);

CREATE INDEX idx_rvc_category_id
  ON public.reference_video_categories USING btree (category_id);
CREATE INDEX idx_rvc_reference_video_id
  ON public.reference_video_categories USING btree (reference_video_id);

CREATE INDEX idx_subscription_plans_apple_product_id
  ON public.subscription_plans USING btree (apple_product_id)
  WHERE (apple_product_id IS NOT NULL);

CREATE INDEX idx_pipeline_steps_pipeline_id
  ON public.pipeline_steps USING btree (pipeline_id);
CREATE INDEX idx_pipeline_executions_generation_id
  ON public.pipeline_executions USING btree (generation_id);
CREATE INDEX idx_pipeline_executions_status
  ON public.pipeline_executions USING btree (status)
  WHERE (status IN ('pending', 'running'));
CREATE INDEX idx_effect_pipelines_effect_id
  ON public.effect_pipelines USING btree (effect_id);

-- ---------------------------------------------------------------------------
-- 12. Triggers
-- ---------------------------------------------------------------------------

CREATE TRIGGER update_devices_updated_at
  BEFORE UPDATE ON public.devices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_generations_updated_at
  BEFORE UPDATE ON public.generations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_apple_receipts_updated_at
  BEFORE UPDATE ON public.apple_receipts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_effects_updated_at
  BEFORE UPDATE ON public.effects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_provider_config_updated_at
  BEFORE UPDATE ON public.provider_config
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_pipeline_templates_updated_at
  BEFORE UPDATE ON public.pipeline_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_pipeline_steps_updated_at
  BEFORE UPDATE ON public.pipeline_steps
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_pipeline_executions_updated_at
  BEFORE UPDATE ON public.pipeline_executions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_effect_pipelines_updated_at
  BEFORE UPDATE ON public.effect_pipelines
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_videos_updated_at
  BEFORE UPDATE ON public.user_videos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------------
-- 13. Row-Level Security (RLS)
-- ---------------------------------------------------------------------------

ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.apple_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.apple_product_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.effect_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.effects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pipeline_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pipeline_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.effect_pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pipeline_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reference_videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reference_video_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.failed_generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_videos ENABLE ROW LEVEL SECURITY;

-- devices
CREATE POLICY "Anyone can insert devices"
  ON public.devices FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Anyone can read devices"
  ON public.devices FOR SELECT TO public USING (true);
CREATE POLICY "Anyone can update their device"
  ON public.devices FOR UPDATE TO public USING (true);

-- subscription_plans
CREATE POLICY "Anyone can read plans"
  ON public.subscription_plans FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages plans"
  ON public.subscription_plans FOR ALL TO service_role USING (true) WITH CHECK (true);

-- system_config
CREATE POLICY "Anyone can read config"
  ON public.system_config FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages config"
  ON public.system_config FOR ALL TO service_role USING (true) WITH CHECK (true);

-- device_subscriptions
CREATE POLICY "Anyone can insert subscriptions"
  ON public.device_subscriptions FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Anyone can read subscriptions"
  ON public.device_subscriptions FOR SELECT TO public USING (true);

-- apple_receipts
CREATE POLICY "Service role can manage apple_receipts"
  ON public.apple_receipts FOR ALL TO public USING (true) WITH CHECK (true);

-- apple_product_mappings
CREATE POLICY "Anyone can read product mappings"
  ON public.apple_product_mappings FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages product mappings"
  ON public.apple_product_mappings FOR ALL TO service_role USING (true) WITH CHECK (true);

-- effect_categories
CREATE POLICY "Anyone can read effect categories"
  ON public.effect_categories FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages effect categories"
  ON public.effect_categories FOR ALL TO service_role USING (true) WITH CHECK (true);

-- video_categories
CREATE POLICY "Anyone can read categories"
  ON public.video_categories FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages video categories"
  ON public.video_categories FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ai_models
CREATE POLICY "Anyone can read ai_models"
  ON public.ai_models FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages ai_models"
  ON public.ai_models FOR ALL TO service_role USING (true) WITH CHECK (true);

-- provider_config
CREATE POLICY "Anyone can read provider_config"
  ON public.provider_config FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages provider_config"
  ON public.provider_config FOR ALL TO service_role USING (true) WITH CHECK (true);

-- effects
CREATE POLICY "Anyone can read effects"
  ON public.effects FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages effects"
  ON public.effects FOR ALL TO service_role USING (true) WITH CHECK (true);

-- pipeline_templates
CREATE POLICY "Anyone can read pipeline_templates"
  ON public.pipeline_templates FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages pipeline_templates"
  ON public.pipeline_templates FOR ALL TO service_role USING (true) WITH CHECK (true);

-- pipeline_steps
CREATE POLICY "Anyone can read pipeline_steps"
  ON public.pipeline_steps FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages pipeline_steps"
  ON public.pipeline_steps FOR ALL TO service_role USING (true) WITH CHECK (true);

-- effect_pipelines
CREATE POLICY "Anyone can read effect_pipelines"
  ON public.effect_pipelines FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages effect_pipelines"
  ON public.effect_pipelines FOR ALL TO service_role USING (true) WITH CHECK (true);

-- pipeline_executions
CREATE POLICY "Anyone can read pipeline_executions"
  ON public.pipeline_executions FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages pipeline_executions"
  ON public.pipeline_executions FOR ALL TO service_role USING (true) WITH CHECK (true);

-- reference_videos
CREATE POLICY "Anyone can read reference videos"
  ON public.reference_videos FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages reference videos"
  ON public.reference_videos FOR ALL TO service_role USING (true) WITH CHECK (true);

-- reference_video_categories
CREATE POLICY "Anyone can read video category mappings"
  ON public.reference_video_categories FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages video category mappings"
  ON public.reference_video_categories FOR ALL TO service_role USING (true) WITH CHECK (true);

-- generations
CREATE POLICY "Anyone can insert generations"
  ON public.generations FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Anyone can read generations"
  ON public.generations FOR SELECT TO public USING (true);
CREATE POLICY "Anyone can update generations"
  ON public.generations FOR UPDATE TO public USING (true);

-- failed_generations
CREATE POLICY "Anyone can read failed generations"
  ON public.failed_generations FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages failed_generations"
  ON public.failed_generations FOR ALL TO service_role USING (true) WITH CHECK (true);

-- user_videos
CREATE POLICY "Anyone can read user_videos"
  ON public.user_videos FOR SELECT TO public USING (true);
CREATE POLICY "Anyone can insert user_videos"
  ON public.user_videos FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Anyone can update user_videos"
  ON public.user_videos FOR UPDATE TO public USING (true);
CREATE POLICY "Anyone can delete user_videos"
  ON public.user_videos FOR DELETE TO public USING (true);

-- ---------------------------------------------------------------------------
-- 14. Storage Buckets
-- ---------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('portraits',         'portraits',         true, NULL, NULL),
  ('generated-videos',  'generated-videos',  true, NULL, NULL),
  ('reference-videos',  'reference-videos',  true, NULL, NULL),
  ('user-videos',       'user-videos',       true, 52428800, ARRAY['video/mp4', 'video/quicktime', 'image/jpeg', 'image/png']),
  ('pipeline-artifacts','pipeline-artifacts', true, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies
CREATE POLICY "Public read portraits"
  ON storage.objects FOR SELECT TO public USING (bucket_id = 'portraits');
CREATE POLICY "Service role upload portraits"
  ON storage.objects FOR INSERT TO public WITH CHECK (bucket_id = 'portraits');

CREATE POLICY "Public read generated-videos"
  ON storage.objects FOR SELECT TO public USING (bucket_id = 'generated-videos');
CREATE POLICY "Service role upload generated-videos"
  ON storage.objects FOR INSERT TO public WITH CHECK (bucket_id = 'generated-videos');

CREATE POLICY "Public read reference-videos"
  ON storage.objects FOR SELECT TO public USING (bucket_id = 'reference-videos');

CREATE POLICY "Public read user-videos"
  ON storage.objects FOR SELECT TO public USING (bucket_id = 'user-videos');
CREATE POLICY "Anyone upload user-videos"
  ON storage.objects FOR INSERT TO public WITH CHECK (bucket_id = 'user-videos');
CREATE POLICY "Anyone update user-videos"
  ON storage.objects FOR UPDATE TO public USING (bucket_id = 'user-videos');
CREATE POLICY "Anyone delete user-videos"
  ON storage.objects FOR DELETE TO public USING (bucket_id = 'user-videos');

CREATE POLICY "Public read pipeline-artifacts"
  ON storage.objects FOR SELECT TO public USING (bucket_id = 'pipeline-artifacts');
CREATE POLICY "Service role upload pipeline-artifacts"
  ON storage.objects FOR INSERT TO public WITH CHECK (bucket_id = 'pipeline-artifacts');

-- ---------------------------------------------------------------------------
-- 15. Realtime
-- ---------------------------------------------------------------------------

ALTER PUBLICATION supabase_realtime ADD TABLE public.generations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.pipeline_executions;

-- =============================================================================
-- DONE. Schema is ready for deployment.
-- =============================================================================
