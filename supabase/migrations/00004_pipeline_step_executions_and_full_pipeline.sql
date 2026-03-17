-- =============================================================================
-- Full 3-Step Pipeline (Gemini Enhance + Gemini Vision + Grok Video)
-- Uses all system capabilities including vision of images.
-- Note: pipeline_step_executions and pipeline_execution_id are in 00002.
-- =============================================================================

-- 1. Ensure pipeline_tests category exists
INSERT INTO public.effect_categories (id, name, display_name, sort_order, is_active)
VALUES ('00000000-0000-0000-0000-000000000001', 'pipeline_tests', 'Pipeline Tests', 99, true)
ON CONFLICT (name) DO UPDATE SET display_name = EXCLUDED.display_name, is_active = true;

-- 4. Full 3-Step Pipeline: Gemini Enhance -> Gemini Vision -> Grok Video
-- Uses all system capabilities including vision of images

INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  '33333333-3333-3333-3333-333333333333',
  'Full Vision-Enriched Pipeline',
  '3 steps: Gemini image enhancement, Gemini Vision analysis (direct to video prompt), then Grok video generation. No text enrichment.',
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

-- Step 1: Gemini Vision - analyze the ENHANCED image and produce video prompt directly
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  1,
  'image_analyze',
  'Analyze Enhanced Image',
  'gemini',
  '{"model": "gemini-3.1-pro-preview", "prompt_template": "Analyze this image in detail: identify the subject, setting, mood, and notable details. Then, using your analysis, write a video generation prompt that weaves the specific image details into the following effect concept: ''{{effect_concept}}''. If the user provided additional context, incorporate it: ''{{user_prompt}}''. Your output must be ONLY the final video generation prompt text, ready to use for video generation. Keep it under 100 words.", "output_key": "video_prompt", "max_tokens": 500}',
  '{"image": "pipeline.enhanced_image"}',
  '{"video_prompt": "result.video_prompt"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

-- Step 2: Grok Video - use enhanced image + video prompt from Gemini Vision
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  2,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "video_prompt", "image_source": "enhanced_image", "duration": 6, "aspect_ratio": "9:16"}',
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
