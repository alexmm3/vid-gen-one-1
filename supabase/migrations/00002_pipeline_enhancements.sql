-- =============================================================================
-- Pipeline Enhancements Migration
-- =============================================================================
-- Adds: pipeline_step_executions table, pipeline_execution_id on generations,
--        Gemini/Vision AI models, Gemini provider config
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add pipeline_execution_id to generations for traceability
-- ---------------------------------------------------------------------------

ALTER TABLE public.generations
  ADD COLUMN IF NOT EXISTS pipeline_execution_id uuid
    REFERENCES public.pipeline_executions(id);

CREATE INDEX IF NOT EXISTS idx_generations_pipeline_execution_id
  ON public.generations (pipeline_execution_id)
  WHERE pipeline_execution_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. New table: pipeline_step_executions
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.pipeline_step_executions (
  id                    uuid        NOT NULL DEFAULT gen_random_uuid(),
  pipeline_execution_id uuid        NOT NULL REFERENCES public.pipeline_executions(id) ON DELETE CASCADE,
  step_id               uuid        NOT NULL REFERENCES public.pipeline_steps(id),
  step_order            integer     NOT NULL,
  status                text        NOT NULL DEFAULT 'pending',
  input_data            jsonb       NOT NULL DEFAULT '{}',
  output_data           jsonb       NOT NULL DEFAULT '{}',
  provider_request_id   text,
  error_message         text,
  started_at            timestamptz,
  completed_at          timestamptz,
  duration_ms           integer,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pipeline_step_executions_pkey PRIMARY KEY (id),
  CONSTRAINT pipeline_step_executions_status_check
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped'))
);

CREATE INDEX IF NOT EXISTS idx_pipeline_step_executions_pipeline
  ON public.pipeline_step_executions (pipeline_execution_id);

ALTER TABLE public.pipeline_step_executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read step executions"
  ON public.pipeline_step_executions FOR SELECT TO public USING (true);
CREATE POLICY "Service role manages step executions"
  ON public.pipeline_step_executions FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TRIGGER update_pipeline_step_executions_updated_at
  BEFORE UPDATE ON public.pipeline_step_executions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------------
-- 3. Seed AI models for Gemini and Grok Vision/Text
-- ---------------------------------------------------------------------------

INSERT INTO public.ai_models (id, name, provider, model_type, is_active, config)
VALUES
  ('gemini-2.0-flash-exp', 'Gemini 2.0 Flash (Image Edit)', 'gemini', 'image', true, '{}'),
  ('gemini-imagen-3.0', 'Imagen 3.0 (NanaBanana Pro)', 'gemini', 'image', true, '{}'),
  ('grok-vision', 'Grok Vision (Image Analysis)', 'grok', 'vision', true, '{}'),
  ('grok-text', 'Grok Text (Prompt Enrichment)', 'grok', 'text', true, '{}')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  provider = EXCLUDED.provider,
  model_type = EXCLUDED.model_type;

-- ---------------------------------------------------------------------------
-- 4. Seed Gemini provider config
-- ---------------------------------------------------------------------------

INSERT INTO public.provider_config (provider, config, is_active)
VALUES (
  'gemini',
  '{
    "api_key_secret": "GEMINI_API_KEY",
    "base_url": "https://generativelanguage.googleapis.com/v1beta",
    "default_model": "gemini-2.0-flash-exp",
    "image_edit_model": "imagen-3.0-generate-002",
    "timeout_seconds": 60
  }'::jsonb,
  true
) ON CONFLICT (provider) DO UPDATE SET config = EXCLUDED.config;

-- =============================================================================
-- DONE
-- =============================================================================
