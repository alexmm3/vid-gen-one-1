-- =============================================================================
-- Full 4-Step Pipeline (Gemini + Vision + Text + Video)
-- Uses all system capabilities including vision of images.
-- Note: pipeline_step_executions and pipeline_execution_id are in 00002.
-- =============================================================================

-- 1. Ensure pipeline_tests category exists
INSERT INTO public.effect_categories (id, name, display_name, sort_order, is_active)
VALUES ('00000000-0000-0000-0000-000000000001', 'pipeline_tests', 'Pipeline Tests', 99, true)
ON CONFLICT (name) DO UPDATE SET display_name = EXCLUDED.display_name, is_active = true;

-- 4. Full 4-Step Pipeline: Gemini Enhance -> Grok Vision -> Grok Text -> Grok Video
-- Uses all system capabilities including vision of images

INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  '33333333-3333-3333-3333-333333333333',
  'Full Vision-Enriched Pipeline',
  'Uses all capabilities: Gemini image enhancement, Grok Vision analysis, Grok Text prompt enrichment, then Grok video generation.',
  1,
  true
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  is_active = EXCLUDED.is_active;

-- Step 0: Gemini Image Enhancement
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  0,
  'image_enhance',
  'Cinematic Filter',
  'gemini',
  '{"model": "gemini-2.0-flash-exp", "prompt_template": "Apply a cinematic color grade to this image. Enhance contrast, add dramatic lighting and warm tones. Keep the subject identical. {{user_prompt}}", "quality": "high"}',
  '{"image": "pipeline.user_image"}',
  '{"enhanced_image": "result.image_url", "enhanced_image_storage_path": "result.storage_path"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

-- Step 1: Grok Vision - analyze the ENHANCED image (from step 0)
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  1,
  'image_analyze',
  'Analyze Enhanced Image',
  'grok',
  '{"model": "grok-2-vision-1212", "prompt_template": "Describe in detail what you see in this image: the subject, setting, mood, and notable details.", "output_key": "image_description", "max_tokens": 300}',
  '{"image": "pipeline.enhanced_image"}',
  '{"image_description": "result.image_description"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

-- Step 2: Grok Text - enrich prompt using vision description
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  2,
  'prompt_enrich',
  'Enrich Prompt',
  'grok',
  '{"model": "grok-3-mini-fast", "prompt_template": "You are a creative video director. Image description: ''{{image_description}}''. Effect goal: ''{{effect_concept}}''. User request: ''{{user_prompt}}''. Write a detailed, personalized video generation prompt that weaves specific details from the image into the effect concept. Keep it under 100 words.", "output_key": "enriched_prompt", "max_tokens": 500}',
  '{"prompt_context": "pipeline.image_description"}',
  '{"enriched_prompt": "result.enriched_prompt"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

-- Step 3: Grok Video - use enhanced image + enriched prompt
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  3,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "enriched_prompt", "image_source": "enhanced_image", "duration": 5, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.enhanced_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

-- 4. Create effect and link to full pipeline
INSERT INTO public.effects (
  id, name, description, category_id, is_active, system_prompt_template, provider
) VALUES (
  'c3333333-3333-3333-3333-333333333333',
  'Full Pipeline Adventure',
  'Tests all capabilities: Gemini enhancement, Grok Vision, Grok Text enrichment, and Grok video generation.',
  (SELECT id FROM public.effect_categories WHERE name = 'pipeline_tests' LIMIT 1),
  true,
  'The subject suddenly starts dancing to funky music in a vibrant, colorful environment. Magical particles float around.',
  'grok'
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template;

-- Link effect to full pipeline (upsert by deleting and re-inserting to handle no unique constraint)
DELETE FROM public.effect_pipelines WHERE effect_id = 'c3333333-3333-3333-3333-333333333333';
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('c3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', true);
