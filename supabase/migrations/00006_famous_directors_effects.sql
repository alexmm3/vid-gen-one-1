-- =============================================================================
-- Famous Directors: 6 effects and their pipelines
-- 1. Perspective Warp (Direct)
-- 2. Room Breathing (Pipeline A: enhance -> video)
-- 3. Selective Time Aging (Pipeline B: analyze -> video)
-- 4. Slow Reality (Pipeline B: analyze -> video)
-- 5. Emotional Environment (Pipeline B: emotion analyze -> video)
-- 6. Nanite Disassembly (Pipeline C: enhance -> analyze -> video)
-- =============================================================================

-- Category (upsert by id so re-runs are safe)
INSERT INTO public.effect_categories (id, name, display_name, sort_order, is_active)
VALUES (
  'fd000000-0000-4000-8000-000000000001',
  'famous_directors',
  'Famous Directors',
  10,
  true
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  display_name = EXCLUDED.display_name,
  sort_order = EXCLUDED.sort_order,
  is_active = EXCLUDED.is_active;

-- =============================================================================
-- 1. PERSPECTIVE WARP — Direct (no pipeline)
-- =============================================================================
INSERT INTO public.effects (
  id, name, description, category_id, is_active, is_premium, sort_order,
  requires_secondary_photo, system_prompt_template, provider, generation_params
) VALUES (
  'fd200001-0001-4000-8000-000000000001',
  'Perspective Warp',
  'Vertigo-style dolly zoom: the room bends inward as the camera pushes toward the subject.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  1,
  false,
  'A dramatic Vertigo-style dolly zoom effect. The room gradually warps and bends inward as if the walls are being pulled toward the subject. The distortion increases slowly, creating a surreal, disorienting feeling. The subject stays sharp and undistorted. Cinematic, smooth motion.',
  'grok',
  '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template,
  generation_params = EXCLUDED.generation_params;

-- =============================================================================
-- 2. ROOM BREATHING — Pipeline A (image_enhance -> video_generate)
-- =============================================================================
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  'fd100001-0001-4000-8000-000000000001',
  'Room Breathing',
  'Enhance mood then generate breathing walls effect.',
  1,
  true
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES
(
  'fd100001-0001-4000-8000-000000000001',
  0,
  'image_enhance',
  'Anxious Mood',
  'gemini',
  '{"model": "gemini-3.1-flash-image-preview", "prompt_template": "Shift this image toward a slightly desaturated, anxious mood. Add subtle vignetting and cooler shadows. Keep all geometry and subjects identical. {{user_prompt}}", "quality": "high"}',
  '{"image": "pipeline.user_image"}',
  '{"enhanced_image": "result.image_url", "enhanced_image_storage_path": "result.storage_path"}',
  true
),
(
  'fd100001-0001-4000-8000-000000000001',
  1,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "effect_concept_resolved", "image_source": "enhanced_image", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.enhanced_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
)
ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

INSERT INTO public.effects (
  id, name, description, category_id, is_active, is_premium, sort_order,
  requires_secondary_photo, system_prompt_template, provider, generation_params
) VALUES (
  'fd200002-0002-4000-8000-000000000002',
  'Room Breathing',
  'Walls expand and contract with a subtle heartbeat rhythm. Unsettling, claustrophobic.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  2,
  false,
  'The walls of the room slowly breathe — expanding and contracting with an almost imperceptible heartbeat rhythm. The movement is subtle, unsettling, claustrophobic. Lighting pulses very slightly with each breath. The subject remains still. No dialogue.',
  'grok',
  '{}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template;

DELETE FROM public.effect_pipelines WHERE effect_id = 'fd200002-0002-4000-8000-000000000002';
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('fd200002-0002-4000-8000-000000000002', 'fd100001-0001-4000-8000-000000000001', true);

-- =============================================================================
-- 3. SELECTIVE TIME AGING — Pipeline B (image_analyze -> video_generate)
-- =============================================================================
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  'fd100002-0002-4000-8000-000000000002',
  'Selective Time Aging',
  'Identify objects, pick one to age, generate video.',
  1,
  true
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES
(
  'fd100002-0002-4000-8000-000000000002',
  0,
  'image_analyze',
  'Identify Objects',
  'gemini',
  '{"model": "gemini-3.1-pro-preview", "prompt_template": "You are a time-manipulation VFX director. Analyze this image carefully and identify all distinct objects. Focus on objects that would show visible aging — flowers, plants, wood, fabric, skin, metal, food. For each, note its name, position, and material type. Then pick the ONE most visually dramatic object to age rapidly. Write a single video generation prompt (under 80 words) where only that chosen object decays or ages over 5 seconds while everything else stays completely frozen in time. Be specific about the aging process for that material. Output ONLY the final video generation prompt, nothing else.", "output_key": "video_prompt", "max_tokens": 500}',
  '{"image": "pipeline.user_image"}',
  '{"video_prompt": "result.video_prompt"}',
  true
),
(
  'fd100002-0002-4000-8000-000000000002',
  1,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "video_prompt", "image_source": "user_image", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.user_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
)
ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

INSERT INTO public.effects (
  id, name, description, category_id, is_active, is_premium, sort_order,
  requires_secondary_photo, system_prompt_template, provider, generation_params
) VALUES (
  'fd200003-0003-4000-8000-000000000003',
  'Selective Time Aging',
  'Only one object in frame ages rapidly; everything else stays frozen.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  3,
  false,
  'A cinematic shot where one object rapidly wilts or decays while the rest of the scene remains completely frozen in time.',
  'grok',
  '{}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template;

DELETE FROM public.effect_pipelines WHERE effect_id = 'fd200003-0003-4000-8000-000000000003';
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('fd200003-0003-4000-8000-000000000003', 'fd100002-0002-4000-8000-000000000002', true);

-- =============================================================================
-- 4. SLOW REALITY — Pipeline B
-- =============================================================================
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  'fd100003-0003-4000-8000-000000000003',
  'Slow Reality',
  'Describe foreground/background, then enrich prompt for dual-speed motion.',
  1,
  true
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES
(
  'fd100003-0003-4000-8000-000000000003',
  0,
  'image_analyze',
  'Describe Layers',
  'gemini',
  '{"model": "gemini-3.1-pro-preview", "prompt_template": "You are a time-bending cinematographer. Analyze the layers of this image: 1) The main subject in the foreground — who or what, their position and pose. 2) Background elements — environment, objects, people, anything that could have independent motion. Then write a video generation prompt where the foreground subject moves at normal speed while ALL background elements move in dreamy slow motion (about 4x slower). Describe specific background motions based on what you see. Output ONLY the final video generation prompt, under 90 words.", "output_key": "video_prompt", "max_tokens": 500}',
  '{"image": "pipeline.user_image"}',
  '{"video_prompt": "result.video_prompt"}',
  true
),
(
  'fd100003-0003-4000-8000-000000000003',
  1,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "video_prompt", "image_source": "user_image", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.user_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
)
ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

INSERT INTO public.effects (
  id, name, description, category_id, is_active, is_premium, sort_order,
  requires_secondary_photo, system_prompt_template, provider, generation_params
) VALUES (
  'fd200004-0004-4000-8000-000000000004',
  'Slow Reality',
  'You move normally; everything behind you is in slow motion.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  4,
  false,
  'The person in the foreground moves at normal speed while everything behind them moves in ethereal slow motion.',
  'grok',
  '{}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template;

DELETE FROM public.effect_pipelines WHERE effect_id = 'fd200004-0004-4000-8000-000000000004';
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('fd200004-0004-4000-8000-000000000004', 'fd100003-0003-4000-8000-000000000003', true);

-- =============================================================================
-- 5. EMOTIONAL ENVIRONMENT — Pipeline B (emotion-focused analyze)
-- =============================================================================
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  'fd100004-0004-4000-8000-000000000004',
  'Emotional Environment',
  'Detect emotion from face, map to environment, generate.',
  1,
  true
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES
(
  'fd100004-0004-4000-8000-000000000004',
  0,
  'image_analyze',
  'Emotion and Appearance',
  'gemini',
  '{"model": "gemini-3.1-pro-preview", "prompt_template": "You are an environment designer for emotional cinema. Analyze this person''s facial expression and body language. Classify the dominant emotion as ONE of: sad, happy, confident, anxious, angry, peaceful, surprised, contemplative. Also note their appearance briefly. Then map the detected emotion to an environment: sad → rain-soaked apartment with droplets on windows; confident → golden-hour rooftop skyline; happy → sun-drenched meadow; anxious → flickering fluorescent office; angry → stormy seascape; peaceful → misty mountain lake; surprised → surreal floating objects; contemplative → quiet library at dusk. Write a single video generation prompt placing this person in the matching environment with atmospheric details. Output ONLY the final video generation prompt, under 80 words.", "output_key": "video_prompt", "max_tokens": 500}',
  '{"image": "pipeline.user_image"}',
  '{"video_prompt": "result.video_prompt"}',
  true
),
(
  'fd100004-0004-4000-8000-000000000004',
  1,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "video_prompt", "image_source": "user_image", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.user_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
)
ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

INSERT INTO public.effects (
  id, name, description, category_id, is_active, is_premium, sort_order,
  requires_secondary_photo, system_prompt_template, provider, generation_params
) VALUES (
  'fd200005-0005-4000-8000-000000000005',
  'Emotional Environment',
  'Your facial emotion drives the room: sad -> rainy apartment, confident -> golden-hour skyline.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  5,
  false,
  'The subject is placed in an environment that matches their emotional expression.',
  'grok',
  '{}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template;

DELETE FROM public.effect_pipelines WHERE effect_id = 'fd200005-0005-4000-8000-000000000005';
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('fd200005-0005-4000-8000-000000000005', 'fd100004-0004-4000-8000-000000000004', true);

-- =============================================================================
-- 6. NANITE DISASSEMBLY — Pipeline C (3 steps)
-- =============================================================================
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  'fd100005-0005-4000-8000-000000000005',
  'Nanite Disassembly',
  'Sci-fi enhance, analyze subject, generate.',
  1,
  true
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO public.pipeline_steps (
  pipeline_id, step_order, step_type, name, provider, config, input_mapping, output_mapping, is_required
) VALUES
(
  'fd100005-0005-4000-8000-000000000005',
  0,
  'image_enhance',
  'Sci-Fi Aesthetic',
  'gemini',
  '{"model": "gemini-3.1-flash-image-preview", "prompt_template": "Enhance this image for cinematic quality: sharpen the focal subject, balance exposure and contrast, and ensure the lighting direction reads clearly. Preserve the original color palette, textures, and visual style exactly. Do not add any tints, overlays, or stylistic changes. Keep the subject fully recognizable and identical. {{user_prompt}}", "quality": "high"}',
  '{"image": "pipeline.user_image"}',
  '{"enhanced_image": "result.image_url", "enhanced_image_storage_path": "result.storage_path"}',
  true
),
(
  'fd100005-0005-4000-8000-000000000005',
  1,
  'image_analyze',
  'Describe Subject',
  'gemini',
  '{"model": "gemini-3.1-pro-preview", "prompt_template": "You are a VFX supervisor writing a cinematic image-to-video animation prompt. Analyze this image carefully: identify the main focal subject (the most visually central and semantically important element), its silhouette, proportions, surface textures and materials, the surrounding environment, and the lighting direction. Then write a video generation prompt for this effect: the focal subject gradually breaks down into countless nanite-like particles — microscopic metallic fragments or luminous programmable grains — that are immediately carried away by the wind as they detach, flowing in streams, arcs, and curved trails. No accumulation. The subject progressively loses all visible structure until completely gone. The surrounding environment remains stable with only subtle wind reactions (vegetation, fabric). Lighting stays consistent with the original; particles reflect and shimmer as they drift. Static centered cinematic camera. Subject completely absent by the end. Output ONLY the final video generation prompt, under 90 words.", "output_key": "video_prompt", "max_tokens": 600}',
  '{"image": "pipeline.enhanced_image"}',
  '{"video_prompt": "result.video_prompt"}',
  true
),
(
  'fd100005-0005-4000-8000-000000000005',
  2,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "video_prompt", "image_source": "enhanced_image", "duration": 6, "aspect_ratio": "9:16"}',
  '{"image": "pipeline.enhanced_image"}',
  '{"provider_request_id": "result.request_id"}',
  true
)
ON CONFLICT (pipeline_id, step_order) DO UPDATE SET
  config = EXCLUDED.config,
  input_mapping = EXCLUDED.input_mapping,
  output_mapping = EXCLUDED.output_mapping;

INSERT INTO public.effects (
  id, name, description, category_id, is_active, is_premium, sort_order,
  requires_secondary_photo, system_prompt_template, provider, generation_params
) VALUES (
  'fd200006-0006-4000-8000-000000000006',
  'Nanite Disassembly',
  'Subject dissolves into nanite particles swept away by wind until completely gone. Atmospheric sci-fi.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  6,
  false,
  'The focal subject gradually breaks down into countless nanite-like particles that are immediately carried away by the wind until the subject completely disappears, leaving only the stable environment.',
  'grok',
  '{}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  system_prompt_template = EXCLUDED.system_prompt_template;

DELETE FROM public.effect_pipelines WHERE effect_id = 'fd200006-0006-4000-8000-000000000006';
INSERT INTO public.effect_pipelines (effect_id, pipeline_id, is_active)
VALUES ('fd200006-0006-4000-8000-000000000006', 'fd100005-0005-4000-8000-000000000005', true);
