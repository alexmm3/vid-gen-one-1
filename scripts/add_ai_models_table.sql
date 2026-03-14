-- Create the ai_models table
CREATE TABLE IF NOT EXISTS public.ai_models (
  id text PRIMARY KEY,
  name text NOT NULL,
  provider text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ai_models ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Anyone can read ai_models" ON public.ai_models FOR SELECT TO public USING (true);
CREATE POLICY "Full access for service role" ON public.ai_models FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Insert known models
INSERT INTO public.ai_models (id, name, provider)
VALUES
  ('kling-v2-master-i2v', 'Kling V2 Master (Image to Video)', 'kling'),
  ('kling-v2.1-master-i2v', 'Kling V2.1 Master (Image to Video)', 'kling'),
  ('Kling-V2-5-Turbo-i2v', 'Kling V2.5 Turbo (Image to Video)', 'kling'),
  ('kling-motion-control', 'Kling Motion Control', 'kling'),
  ('grok-imagine-video', 'Grok Imagine Video', 'grok')
ON CONFLICT (id) DO UPDATE SET 
  name = EXCLUDED.name,
  provider = EXCLUDED.provider;

-- Add ai_model_id to effects table
ALTER TABLE public.effects 
ADD COLUMN IF NOT EXISTS ai_model_id text REFERENCES public.ai_models(id);

-- Optionally, backfill ai_model_id from generation_params if it exists
UPDATE public.effects
SET ai_model_id = generation_params->>'model_id'
WHERE generation_params->>'model_id' IS NOT NULL
  AND ai_model_id IS NULL
  AND EXISTS (SELECT 1 FROM public.ai_models WHERE id = effects.generation_params->>'model_id');

-- Update the default model in provider_config to use Kling V2.5 Turbo
UPDATE public.provider_config
SET config = jsonb_set(config, '{default_model_id}', '"Kling-V2-5-Turbo-i2v"')
WHERE provider = 'kling';
