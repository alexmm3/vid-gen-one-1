-- =============================================================================
-- Nanite Disassembly — Wind Dispersion prompt update
-- Run this once in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/oquhbidxsntfrqsloocc/editor
-- =============================================================================

-- 1. Update effect description + system prompt
UPDATE public.effects
SET
  description          = 'Subject dissolves into nanite particles swept away by wind until completely gone. Atmospheric sci-fi.',
  system_prompt_template = 'The focal subject gradually breaks down into countless nanite-like particles that are immediately carried away by the wind until the subject completely disappears, leaving only the stable environment.'
WHERE id = 'fd200006-0006-4000-8000-000000000006';

-- 2. Update Step 0 — image_enhance (preserve original style, no sci-fi tints)
UPDATE public.pipeline_steps
SET config = config || jsonb_build_object(
  'prompt_template',
  'Enhance this image for cinematic quality: sharpen the focal subject, balance exposure and contrast, and ensure the lighting direction reads clearly. Preserve the original color palette, textures, and visual style exactly. Do not add any tints, overlays, or stylistic changes. Keep the subject fully recognizable and identical. {{user_prompt}}'
)
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_order = 0;

-- 3. Update Step 1 — image_analyze (full scene + focal priority detection)
UPDATE public.pipeline_steps
SET config = config || jsonb_build_object(
  'prompt_template',
  'Analyze this image carefully. Identify: the main focal subject (the most visually central and semantically important element — the first thing the viewer notices), its silhouette and proportions, recognizable visual features, surface textures and materials, the surrounding environment, the lighting direction and quality, and atmospheric conditions. Specify what the primary focal subject is and describe the stable background elements.'
)
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_order = 1;

-- 4. Update Step 2 — prompt_enrich (wind dispersion, subject disappears)
UPDATE public.pipeline_steps
SET config = config || jsonb_build_object(
  'prompt_template',
  'You are a VFX supervisor writing a cinematic image-to-video animation prompt. Subject: ''{{image_description}}''. Write a prompt for this effect: the focal subject gradually breaks down into countless nanite-like particles — microscopic metallic fragments or luminous programmable grains — that are immediately carried away by the wind as they detach, flowing in streams, arcs, and curved trails. No accumulation. The subject progressively loses all visible structure until completely gone. The surrounding environment remains stable with only subtle wind reactions (vegetation, fabric). Lighting stays consistent with the original; particles reflect and shimmer as they drift. Static centered cinematic camera. Subject completely absent by the end. Under 90 words.'
)
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_order = 2;

-- Verify
SELECT step_order, name, config->>'prompt_template' AS prompt
FROM public.pipeline_steps
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
ORDER BY step_order;
