-- =============================================================================
-- Famous Directors: 6 effects and their pipelines
-- 1. Perspective Warp (Direct)
-- 2. Room Breathing (Pipeline A: enhance -> video)
-- 3. Selective Time Aging (Pipeline B: analyze -> enrich -> video)
-- 4. Slow Reality (Pipeline B: analyze -> enrich -> video)
-- 5. Emotional Environment (Pipeline B: emotion analyze -> enrich -> video)
-- 6. Nanite Disassembly (Pipeline C: enhance -> analyze -> enrich -> video)
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
  '{"duration": 5, "aspect_ratio": "9:16"}'::jsonb
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
  '{"model": "grok-imagine-video", "prompt_source": "effect_concept_resolved", "image_source": "enhanced_image", "duration": 5, "aspect_ratio": "9:16"}',
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
-- 3. SELECTIVE TIME AGING — Pipeline B (image_analyze -> prompt_enrich -> video_generate)
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
  'grok',
  '{"model": "grok-4-1-fast-non-reasoning", "prompt_template": "Identify all distinct objects in this image. For each object list: name, position, material type. Focus on objects that would show visible aging — flowers, plants, wood, fabric, skin, metal, food. Return a structured list.", "output_key": "image_description", "max_tokens": 400}',
  '{"image": "pipeline.user_image"}',
  '{"image_description": "result.image_description"}',
  true
),
(
  'fd100002-0002-4000-8000-000000000002',
  1,
  'prompt_enrich',
  'Pick One to Age',
  'grok',
  '{"model": "grok-3-mini-fast", "prompt_template": "You are a time-manipulation director. Objects in scene: ''{{image_description}}''. Pick the ONE most visually dramatic object to age rapidly. Write a single video generation prompt where only that object decays or ages over 5 seconds while everything else stays completely frozen. Be specific about the aging process for that material. Under 80 words.", "output_key": "enriched_prompt", "max_tokens": 300}',
  '{}',
  '{"enriched_prompt": "result.enriched_prompt"}',
  true
),
(
  'fd100002-0002-4000-8000-000000000002',
  2,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "enriched_prompt", "image_source": "user_image", "duration": 5, "aspect_ratio": "9:16"}',
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
  'grok',
  '{"model": "grok-4-1-fast-non-reasoning", "prompt_template": "Describe the layers of this image: 1) Main subject in foreground — who or what, position, pose. 2) Background elements — environment, objects, people, anything that could have motion. Be specific.", "output_key": "image_description", "max_tokens": 350}',
  '{"image": "pipeline.user_image"}',
  '{"image_description": "result.image_description"}',
  true
),
(
  'fd100003-0003-4000-8000-000000000003',
  1,
  'prompt_enrich',
  'Dual-Speed Prompt',
  'grok',
  '{"model": "grok-3-mini-fast", "prompt_template": "You are a time-bending cinematographer. Scene: ''{{image_description}}''. Write a video prompt: the foreground subject moves at normal speed; ALL background elements move in dreamy slow motion (about 4x slower). Describe specific background motions. Under 90 words.", "output_key": "enriched_prompt", "max_tokens": 350}',
  '{}',
  '{"enriched_prompt": "result.enriched_prompt"}',
  true
),
(
  'fd100003-0003-4000-8000-000000000003',
  2,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "enriched_prompt", "image_source": "user_image", "duration": 5, "aspect_ratio": "9:16"}',
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
  'grok',
  '{"model": "grok-4-1-fast-non-reasoning", "prompt_template": "Analyze the person''s facial expression and body language. Classify the dominant emotion as ONE of: sad, happy, confident, anxious, angry, peaceful, surprised, contemplative. Also describe the person''s appearance briefly. Return format: EMOTION: [emotion] DESCRIPTION: [brief appearance and setting].", "output_key": "image_description", "max_tokens": 200}',
  '{"image": "pipeline.user_image"}',
  '{"image_description": "result.image_description"}',
  true
),
(
  'fd100004-0004-4000-8000-000000000004',
  1,
  'prompt_enrich',
  'Map Emotion to Environment',
  'grok',
  '{"model": "grok-3-mini-fast", "prompt_template": "You are an environment designer for emotional cinema. The subject feels: ''{{image_description}}''. Map this emotion to an environment: sad -> rain-soaked apartment with droplets on windows; confident -> golden-hour rooftop skyline; happy -> sun-drenched meadow; anxious -> flickering fluorescent office; angry -> stormy seascape; peaceful -> misty mountain lake; surprised -> surreal floating objects; contemplative -> quiet library at dusk. Write one video prompt placing this person in the matching environment with atmospheric details. Under 80 words.", "output_key": "enriched_prompt", "max_tokens": 300}',
  '{}',
  '{"enriched_prompt": "result.enriched_prompt"}',
  true
),
(
  'fd100004-0004-4000-8000-000000000004',
  2,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "enriched_prompt", "image_source": "user_image", "duration": 5, "aspect_ratio": "9:16"}',
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
-- 6. NANITE DISASSEMBLY — Pipeline C (4 steps)
-- =============================================================================
INSERT INTO public.pipeline_templates (id, name, description, version, is_active)
VALUES (
  'fd100005-0005-4000-8000-000000000005',
  'Nanite Disassembly',
  'Sci-fi enhance, analyze subject, enrich nanite prompt, generate.',
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
  '{"model": "gemini-3.1-flash-image-preview", "prompt_template": "Enhance this image with a subtle sci-fi aesthetic: add a faint metallic sheen to skin, slightly boost contrast, add a very subtle blue-tech tint to highlights. Keep the subject fully recognizable and identical. {{user_prompt}}", "quality": "high"}',
  '{"image": "pipeline.user_image"}',
  '{"enhanced_image": "result.image_url", "enhanced_image_storage_path": "result.storage_path"}',
  true
),
(
  'fd100005-0005-4000-8000-000000000005',
  1,
  'image_analyze',
  'Describe Subject',
  'grok',
  '{"model": "grok-4-1-fast-non-reasoning", "prompt_template": "Describe the subject in detail: face shape, hair, clothing, accessories, pose, expression. What colors dominate? What textures are visible?", "output_key": "image_description", "max_tokens": 300}',
  '{"image": "pipeline.enhanced_image"}',
  '{"image_description": "result.image_description"}',
  true
),
(
  'fd100005-0005-4000-8000-000000000005',
  2,
  'prompt_enrich',
  'Nanite Sequence',
  'grok',
  '{"model": "grok-3-mini-fast", "prompt_template": "You are a VFX supervisor. Subject: ''{{image_description}}''. Create a nanite disassembly sequence: the subject breaks apart into thousands of tiny glowing particles (starting from one edge or the center). The particles swarm, pulse with light matching the subject''s colors, then reassemble into a slightly transformed, elevated version. 5 seconds. Under 90 words.", "output_key": "enriched_prompt", "max_tokens": 400}',
  '{}',
  '{"enriched_prompt": "result.enriched_prompt"}',
  true
),
(
  'fd100005-0005-4000-8000-000000000005',
  3,
  'video_generate',
  'Generate Video',
  'grok',
  '{"model": "grok-imagine-video", "prompt_source": "enriched_prompt", "image_source": "enhanced_image", "duration": 5, "aspect_ratio": "9:16"}',
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
  'Subject breaks into swarming nanites that reassemble differently. Sci-fi flair.',
  'fd000000-0000-4000-8000-000000000001',
  true,
  false,
  6,
  false,
  'The subject disintegrates into thousands of glowing nanite particles that swarm and reassemble into a transformed version.',
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
