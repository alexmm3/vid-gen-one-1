-- =============================================================================
-- Test Scenarios for Multi-Step Pipelines
-- Run this script in your Supabase SQL Editor to create test pipelines & effects
-- =============================================================================

-- 1. Create a category for test effects
INSERT INTO public.effect_categories (id, name, display_name, sort_order, is_active)
VALUES ('00000000-0000-0000-0000-000000000001', 'pipeline_tests', 'Pipeline Tests', 99, true)
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- SCENARIO A: Cinematic Pre-Enhancement (Gemini Image Edit -> Grok Video)
-- =============================================================================

-- Create Pipeline Template
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  '11111111-1111-1111-1111-111111111111', 
  'Cinematic Pre-Enhancement', 
  'Enhances the user photo using Gemini before generating the video', 
  1, 
  true
) ON CONFLICT (id) DO NOTHING;

-- Step 1: Gemini Image Enhancement
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  0,
  'image_enhance',
  'Cinematic Filter',
  'gemini',
  '{"model": "gemini-2.0-flash-exp", "prompt_template": "Apply a cinematic color grade to this image. Enhance contrast, add dramatic lighting and warm tones. Keep the subject identical. {{user_prompt}}", "quality": "high"}',
  '{"image": "pipeline.user_image"}',
  '{"enhanced_image": "result.image_url", "enhanced_image_storage_path": "result.storage_path"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO NOTHING;

-- Step 2: Grok Video Generation (uses effect_concept_resolved = prompt with user_prompt already substituted)
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  1,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "effect_concept_resolved", "image_source": "enhanced_image", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.enhanced_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  input_mapping = EXCLUDED.input_mapping;

-- Create Effect linked to Scenario A
INSERT INTO public.effects (
  id, name, description, category_id, is_active, system_prompt_template, provider
) VALUES (
  'a1111111-1111-1111-1111-111111111111',
  'Cinematic Magic (Pipeline A)',
  'Tests Gemini image enhancement before video generation.',
  (SELECT id FROM public.effect_categories WHERE name = 'pipeline_tests'),
  true,
  'A magical cinematic scene with glowing particles floating in the air. Slow motion.',
  'grok'
) ON CONFLICT (id) DO NOTHING;

-- Link Effect to Pipeline
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('a1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', true)
ON CONFLICT DO NOTHING;


-- =============================================================================
-- SCENARIO B: Vision-Enriched Generation (Gemini Vision Analysis -> Grok Video)
-- =============================================================================

-- Create Pipeline Template
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  '22222222-2222-2222-2222-222222222222', 
  'Vision-Enriched Generation', 
  'Analyzes the image to build a highly personalized prompt before generation', 
  1, 
  true
) ON CONFLICT (id) DO NOTHING;

-- Step 1: Gemini Vision Analysis
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  0,
  'image_analyze',
  'Analyze Image',
  'gemini',
  '{"model": "gemini-3.1-pro-preview", "prompt_template": "Analyze this image in detail: identify the subject, setting, mood, and notable details. Then, using your analysis, write a video generation prompt that weaves the specific image details into the following effect concept: ''{{effect_concept}}''. If the user provided additional context, incorporate it: ''{{user_prompt}}''. Your output must be ONLY the final video generation prompt text, ready to use for video generation. Keep it under 100 words.", "output_key": "video_prompt", "max_tokens": 500}',
  '{"image": "pipeline.user_image"}',
  '{"video_prompt": "result.video_prompt"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO NOTHING;

-- Step 2: Grok Video Generation
INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  1,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "video_prompt", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.user_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
) ON CONFLICT (pipeline_id, step_order) DO NOTHING;

-- Create Effect linked to Scenario B
INSERT INTO public.effects (
  id, name, description, category_id, is_active, system_prompt_template, provider
) VALUES (
  'b2222222-2222-2222-2222-222222222222',
  'Personalized Adventure (Pipeline B)',
  'Tests Grok Vision + Grok Text prompt enrichment before video generation.',
  (SELECT id FROM public.effect_categories WHERE name = 'pipeline_tests'),
  true,
  'The subject suddenly starts dancing to funky music in a vibrant, colorful environment.',
  'grok'
) ON CONFLICT (id) DO NOTHING;

-- Link Effect to Pipeline
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('b2222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', true)
ON CONFLICT DO NOTHING;
