-- =============================================================================
-- Migration 00009: Remove prompt_enrich steps, switch image_analyze to Gemini
--
-- 1. Delete all prompt_enrich steps from pipelines
-- 2. Update image_analyze steps: provider → gemini, model → gemini-3.1-pro-preview,
--    merged prompt templates that produce ready-to-use video prompts
-- 3. Update video_generate steps: prompt_source → video_prompt
-- 4. Re-number step_orders to fill gaps
-- 5. Update generation_globals
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Deactivate all prompt_enrich steps and shift their step_order out of the way
-- (Can't DELETE due to FK from pipeline_step_executions preserving history)
-- =============================================================================
UPDATE public.pipeline_steps
SET is_active = false, step_order = step_order + 1000
WHERE step_type = 'prompt_enrich';

-- =============================================================================
-- STEP 2: Update image_analyze steps — switch to Gemini with merged prompts
-- =============================================================================

-- Cinematic Pre-Enhancement (11111111) — live DB has 4 steps via admin panel
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "You are a VFX supervisor. Describe this person in detail: face shape, hair, clothing, accessories, pose, expression, dominant colors and textures. Then write a video generation prompt for a magical cinematic scene with glowing particles floating in the air, the subject in slow motion, looking like a high-end fashion editorial. Weave the specific visual details you observed into the prompt. Output ONLY the final video generation prompt, under 90 words.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = '11111111-1111-1111-1111-111111111111'
  AND step_type = 'image_analyze';

-- Room Breathing (fd100001) — live DB has 4 steps via admin panel
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "You are a VFX supervisor. Describe the subject and the room/environment in this image: the person (face, clothing, pose, expression) and the space (walls, lighting, atmosphere). Then write a video generation prompt where the walls of the room slowly breathe — expanding and contracting with a noticeable, unsettling heartbeat rhythm. The lighting pulses with each breath. The subject reacts subtly to the claustrophobic movement. Weave the specific visual details you observed into the prompt. Output ONLY the final video generation prompt, under 90 words.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = 'fd100001-0001-4000-8000-000000000001'
  AND step_type = 'image_analyze';

-- Pipeline B (22222222): Vision-Enriched Generation (generic test pipeline)
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "Analyze this image in detail: identify the subject, setting, mood, and notable details. Then, using your analysis, write a video generation prompt that weaves the specific image details into the following effect concept: ''{{effect_concept}}''. If the user provided additional context, incorporate it: ''{{user_prompt}}''. Your output must be ONLY the final video generation prompt text, ready to use for video generation. Keep it under 100 words.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = '22222222-2222-2222-2222-222222222222'
  AND step_type = 'image_analyze';

-- Pipeline C (33333333): Full Vision-Enriched Pipeline (generic test pipeline)
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "Analyze this image in detail: identify the subject, setting, mood, and notable details. Then, using your analysis, write a video generation prompt that weaves the specific image details into the following effect concept: ''{{effect_concept}}''. If the user provided additional context, incorporate it: ''{{user_prompt}}''. Your output must be ONLY the final video generation prompt text, ready to use for video generation. Keep it under 100 words.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = '33333333-3333-3333-3333-333333333333'
  AND step_type = 'image_analyze';

-- Selective Time Aging (fd100002)
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "You are a time-manipulation VFX director. Analyze this image carefully and identify all distinct objects. Focus on objects that would show visible aging — flowers, plants, wood, fabric, skin, metal, food. For each, note its name, position, and material type. Then pick the ONE most visually dramatic object to age rapidly. Write a single video generation prompt (under 80 words) where only that chosen object decays or ages over 5 seconds while everything else stays completely frozen in time. Be specific about the aging process for that material. Output ONLY the final video generation prompt, nothing else.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = 'fd100002-0002-4000-8000-000000000002'
  AND step_type = 'image_analyze';

-- Slow Reality (fd100003)
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "You are a time-bending cinematographer. Analyze the layers of this image: 1) The main subject in the foreground — who or what, their position and pose. 2) Background elements — environment, objects, people, anything that could have independent motion. Then write a video generation prompt where the foreground subject moves at normal speed while ALL background elements move in dreamy slow motion (about 4x slower). Describe specific background motions based on what you see. Output ONLY the final video generation prompt, under 90 words.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = 'fd100003-0003-4000-8000-000000000003'
  AND step_type = 'image_analyze';

-- Emotional Environment (fd100004)
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "You are an environment designer for emotional cinema. Analyze this person''s facial expression and body language. Classify the dominant emotion as ONE of: sad, happy, confident, anxious, angry, peaceful, surprised, contemplative. Also note their appearance briefly. Then map the detected emotion to an environment: sad → rain-soaked apartment with droplets on windows; confident → golden-hour rooftop skyline; happy → sun-drenched meadow; anxious → flickering fluorescent office; angry → stormy seascape; peaceful → misty mountain lake; surprised → surreal floating objects; contemplative → quiet library at dusk. Write a single video generation prompt placing this person in the matching environment with atmospheric details. Output ONLY the final video generation prompt, under 80 words.",
    "output_key": "video_prompt",
    "max_tokens": 500
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = 'fd100004-0004-4000-8000-000000000004'
  AND step_type = 'image_analyze';

-- Nanite Disassembly (fd100005)
UPDATE public.pipeline_steps SET
  provider = 'gemini',
  config = '{
    "model": "gemini-3.1-pro-preview",
    "prompt_template": "You are a VFX supervisor writing a cinematic image-to-video animation prompt. Analyze this image carefully: identify the main focal subject (the most visually central and semantically important element), its silhouette, proportions, surface textures and materials, the surrounding environment, and the lighting direction. Then write a video generation prompt for this effect: the focal subject gradually breaks down into countless nanite-like particles — microscopic metallic fragments or luminous programmable grains — that are immediately carried away by the wind as they detach, flowing in streams, arcs, and curved trails. No accumulation. The subject progressively loses all visible structure until completely gone. The surrounding environment remains stable with only subtle wind reactions (vegetation, fabric). Lighting stays consistent with the original; particles reflect and shimmer as they drift. Static centered cinematic camera. Subject completely absent by the end. Output ONLY the final video generation prompt, under 90 words.",
    "output_key": "video_prompt",
    "max_tokens": 600
  }'::jsonb,
  output_mapping = '{"video_prompt": "result.video_prompt"}'::jsonb
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_type = 'image_analyze';

-- =============================================================================
-- STEP 3: Update video_generate steps — prompt_source from enriched_prompt to video_prompt
-- =============================================================================
UPDATE public.pipeline_steps SET
  config = jsonb_set(config, '{prompt_source}', '"video_prompt"')
WHERE step_type = 'video_generate'
  AND config->>'prompt_source' = 'enriched_prompt';

-- =============================================================================
-- STEP 4: Re-number step_orders to fill gaps left by deleted prompt_enrich
-- =============================================================================

-- 3-step → 2-step pipelines: video_generate moves from step_order 2 to 1
-- (prompt_enrich at step_order 1 was deleted, so 1 is now free)
UPDATE public.pipeline_steps SET step_order = 1
WHERE step_type = 'video_generate'
  AND step_order = 2
  AND pipeline_id IN (
    'fd100002-0002-4000-8000-000000000002',
    'fd100003-0003-4000-8000-000000000003',
    'fd100004-0004-4000-8000-000000000004',
    '22222222-2222-2222-2222-222222222222'
  );

-- 4-step → 3-step pipelines: video_generate moves from step_order 3 to 2
-- (prompt_enrich at step_order 2 was deleted, so 2 is now free)
UPDATE public.pipeline_steps SET step_order = 2
WHERE step_type = 'video_generate'
  AND step_order = 3
  AND pipeline_id IN (
    '11111111-1111-1111-1111-111111111111',
    'fd100001-0001-4000-8000-000000000001',
    'fd100005-0005-4000-8000-000000000005',
    '33333333-3333-3333-3333-333333333333'
  );

-- =============================================================================
-- STEP 5: Update generation_globals — disable prompt_enrich
-- =============================================================================
UPDATE public.system_config
SET value = jsonb_set(value, '{prompt_enrich_enabled}', 'false')
WHERE key = 'generation_globals';

COMMIT;
