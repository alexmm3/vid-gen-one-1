-- =============================================================================
-- Migration 00010: Apply master vision prompts & ensure 2-step architecture
--
-- 1. Deactivate image_enhance for Room Breathing (→ 2-step pipeline)
-- 2. Reorder Nanite Disassembly & Room Breathing to (0: analyze, 1: video)
-- 3. Fix stale enhanced_image references → user_image
-- 4. Apply exact master prompts for Aging, Nanite, Breathing Room
-- 5. Remove token limits (set max_tokens = 8192) on ALL image_analyze steps
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Room Breathing — deactivate image_enhance, collapse to 2 steps
-- =============================================================================
UPDATE public.pipeline_steps
SET is_active = false, step_order = 999
WHERE pipeline_id = 'fd100001-0001-4000-8000-000000000001'
  AND step_type = 'image_enhance'
  AND step_order = 0;

UPDATE public.pipeline_steps SET step_order = 0
WHERE pipeline_id = 'fd100001-0001-4000-8000-000000000001'
  AND step_type = 'image_analyze' AND step_order = 1;

UPDATE public.pipeline_steps SET step_order = 1
WHERE pipeline_id = 'fd100001-0001-4000-8000-000000000001'
  AND step_type = 'video_generate' AND step_order = 2;

-- =============================================================================
-- STEP 2: Nanite Disassembly — reorder from (1,2) to (0,1)
-- =============================================================================
UPDATE public.pipeline_steps SET step_order = 999
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_type = 'image_enhance' AND step_order = 0 AND is_active = false;

UPDATE public.pipeline_steps SET step_order = 0
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_type = 'image_analyze' AND step_order = 1;

UPDATE public.pipeline_steps SET step_order = 1
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_type = 'video_generate' AND step_order = 2;

-- =============================================================================
-- STEP 3: Fix input_mapping from enhanced_image → user_image
-- =============================================================================
UPDATE public.pipeline_steps
SET input_mapping = '{"image": "pipeline.user_image"}'::jsonb
WHERE pipeline_id IN (
  'fd100001-0001-4000-8000-000000000001',
  'fd100005-0005-4000-8000-000000000005'
)
AND step_type IN ('image_analyze', 'video_generate')
AND is_active = true;

UPDATE public.pipeline_steps
SET config = jsonb_set(config, '{image_source}', '"user_image"')
WHERE pipeline_id IN (
  'fd100001-0001-4000-8000-000000000001',
  'fd100005-0005-4000-8000-000000000005'
)
AND step_type = 'video_generate'
AND is_active = true;

-- =============================================================================
-- STEP 4: Apply master prompts
-- =============================================================================

-- Selective Time Aging (fd100002)
UPDATE public.pipeline_steps SET
  config = jsonb_set(config, '{prompt_template}', to_jsonb(
'You are a vision-language model analyzing an image in order to generate a cinematic image-to-video animation prompt for Grok''s video generation model.
Your goal is to create a one-way forward time-lapse where the environment and objects in the scene visibly age and decay over decades — while all people remain in their present moment, alive and casually moving.

STEP 1 — SCENE ANALYSIS
Study the uploaded image. Identify:

every person present
the environment type (indoor, outdoor, street, landscape, etc.)
all objects, surfaces, structures, vegetation, food, and drinks visible

STEP 2 — WHAT AGES
Everything that is not a person ages forward through decades of time:

Buildings and structures — walls crack, paint peels, metal rusts, wood rots, surfaces stain and weather
Vegetation — plants overgrow, go wild, vines climb walls, weeds push through cracks, moss spreads
Food and drinks — spoil, mold, dry out, decompose, containers stain and corrode
Furniture and objects — fade, wear, corrode, collect dust, deteriorate
Roads and ground — crack, sprout weeds, potholes form
Glass — hazes, cracks, goes opaque
Fabric (not on people) — fades, frays, tears

Structures remain standing. This is decades of neglect, not total ruin.

STEP 3 — WHAT DOES NOT AGE
All people remain exactly as they are — alive, present, in their current moment.
Each person exhibits subtle casual micro-movements appropriate to their context:

gentle breathing
a slow blink
slight weight shift
hair moving softly
fingers adjusting
small natural gestures

Their clothing, accessories, and anything they hold or carry stays in current condition and moves naturally with their body.

STEP 4 — GENERATE THE PROMPT
Using your analysis, generate a single cinematic prompt for Grok. Maximum 200 words.
Structure:
Camera: Static tripod shot, no movement.
People: Describe each person with specific micro-movements. Use only active, living language — breathing, blinking, shifting. Never use words like "frozen," "static," "unchanged," "preserved," or "untouched." Never put the word "age" or "decay" in the same sentence as a person.
Environment: Describe how each visible element ages — name specific things and what happens to them. Be concrete and visual.
Tone: Hauntingly beautiful — a world quietly crumbling around people who simply continue to breathe.

STEP 5 — LANGUAGE RULE
When writing the final prompt, describe people and aging in separate sentences. People get living verbs. The environment gets aging verbs. These never mix in the same sentence.'::text))
WHERE pipeline_id = 'fd100002-0002-4000-8000-000000000002'
  AND step_type = 'image_analyze' AND is_active = true;

-- Nanite Disassembly (fd100005)
UPDATE public.pipeline_steps SET
  config = jsonb_set(config, '{prompt_template}', to_jsonb(
'Particle Breakdown with Wind Dispersion

You are a vision-language model analyzing an image in order to generate a cinematic image-to-video animation prompt.

Your goal is to create a wind-driven particle breakdown effect where the main focal subject or object gradually breaks down into countless small particles.

As the subject disintegrates, the particles are immediately carried away by the wind.

The subject progressively loses its visible structure until it completely disappears.

The animation must preserve the visual style, lighting, color palette, textures, and environment of the original image.

The surrounding environment should remain mostly stable.

STEP 1 — SCENE ANALYSIS

Carefully study the uploaded image.

Identify:

• the main focal subject or object
• the surrounding environment
• the subject''s silhouette and proportions
• recognizable visual features
• surface textures and materials
• lighting direction and atmospheric conditions

Possible focal subjects may include:

person
animal
creature
vehicle
statue
artifact
machine
object
plant

The subject must be clearly recognizable before transformation begins.

STEP 2 — FOCAL PRIORITY DETECTION

Identify the strongest focal subject in the scene.

The transforming subject must be:

• visually central
• semantically important
• the object the viewer naturally notices first

All other environmental elements remain stable and unchanged.

STEP 3 — PARTICLE CHARACTERISTICS

The subject breaks down into nanite-like particles.

Particles may appear as:

• microscopic metallic fragments
• tiny geometric machine cells
• reflective micro-particles
• luminous programmable grains

Particles must appear technological or luminous, not like sand or natural dust.

Particle size should remain extremely small and numerous.

STEP 4 — PARTICLE BREAKDOWN MECHANISM

The subject gradually breaks down into particles across its entire visible surface.

Important rules:

• particles detach continuously from the subject
• breakdown occurs across the visible form
• no large pieces separate
• no surface layers peel away

The subject progressively loses structure as more particles detach.

This creates the effect that the subject is disintegrating into particles.

STEP 5 — SIMULTANEOUS WIND DISPERSION

As soon as particles detach from the subject, they are immediately carried away by the wind.

Two actions occur simultaneously:

the subject breaks down into particles

those particles flow away with the wind

Particles do not accumulate around the subject.

They immediately enter the wind flow.

STEP 6 — WIND DYNAMICS

Wind direction must be clearly visible through particle movement.

Wind may produce:

• flowing particle streams
• drifting arcs
• curved particle trails
• small swirling eddies

Particles travel consistently in the direction of the wind.

Particle density gradually decreases as they move farther from the subject.

STEP 7 — ENVIRONMENTAL RESPONSE

The surrounding environment remains mostly stable.

Minor reactions may include:

• subtle vegetation movement
• slight fabric flutter
• drifting atmospheric haze

These reactions help reveal wind direction.

STEP 8 — LIGHTING AND ATMOSPHERE

Lighting must remain consistent with the original image.

Particles may interact with light through:

• reflective glints
• subtle glow
• shimmering trails

Atmospheric effects may include:

light haze
drifting particles
soft motion blur

STEP 9 — FINAL PROMPT GENERATION

Using the analysis above, generate a cinematic animation prompt using the following structure.

Camera

A centered static cinematic shot.

The camera remains completely still.

Subject Identification

Identify the focal subject and describe its defining visual characteristics.

Particle Disintegration

Describe how the subject gradually breaks down into countless tiny particles.

Wind-Driven Motion

Describe how those particles are immediately carried away by the wind.

Environment

Describe subtle environmental reactions while the environment remains stable.

Atmosphere

Describe drifting particles, particle trails, and lighting interaction.

Tone

The motion should feel cinematic, controlled, and atmospheric — a gradual particle disintegration carried away by wind.

STEP 10 — FINAL STATE RULE

The animation must end with the subject completely gone.

Only the stable environment remains.

The final particles disperse into the distance until the frame becomes calm again.'::text))
WHERE pipeline_id = 'fd100005-0005-4000-8000-000000000005'
  AND step_type = 'image_analyze' AND is_active = true;

-- Room Breathing (fd100001)
UPDATE public.pipeline_steps SET
  config = jsonb_set(config, '{prompt_template}', to_jsonb(
'You are a vision-language model analyzing an image in order to generate a cinematic image-to-video animation prompt.

Your goal is to create a dramatic "breathing architecture" effect where the environment elastically contracts and releases while remaining physically coherent and structurally intact based on the uploaded image.

The animation must preserve the visual style of the image while applying controlled structural deformation.

STEP 1 — SCENE ANALYSIS

Carefully study the uploaded image.

Identify:

• the type of environment (room, corridor, street, courtyard, landscape, etc.)
• the main subject or focal element
• all major environmental structures
• surfaces and objects present in the scene
• structural geometry and symmetry
• the likely material of each element

Common structural elements may include:

walls
buildings
facades
floors
ceilings
windows
balconies
railings
furniture
vegetation
terrain
roads
water surfaces

Determine the material of each element:

glass
steel
metal
concrete
brick
stone
wood
fabric
vegetation
soil
water
asphalt

STEP 2 — STRUCTURAL HIERARCHY

Classify all detected elements into three categories:

PRIMARY STRUCTURES
large load-bearing architecture or terrain

examples:
buildings, walls, cliffs, terrain, large structures

SECONDARY STRUCTURES
elements rigidly attached to primary structures

examples:
windows, balconies, railings, doors, facade panels

TERTIARY OBJECTS
objects resting within the environment

examples:
furniture, vehicles, loose objects, plants

Movement intensity will depend on this hierarchy.

STEP 3 — STRUCTURAL AXIS DETECTION

Determine the natural deformation axes of the environment.

Examples:

buildings flex along vertical structural frames
walls bend along their length
corridors compress along their central axis
rooms compress across opposing walls
terrain flexes along surface contours

Deformation must follow these natural axes.

STEP 4 — MOTION PHASE SYSTEM

The animation occurs in three phases.

PHASE 1 — NEUTRAL STATE

The environment appears completely still and stable in its original geometry exactly as seen in the uploaded image.

PHASE 2 — CONTRACTION PHASE

Primary structures begin to flex inward along their structural axes as if the environment is inhaling.

Large structures bend dramatically but elastically.

Buildings curve inward.
Walls bow inward.
Architectural frames compress.

SECONDARY structures remain attached and deform with the primary structures:

windows curve with the facade
balconies bend with the building
railings follow the structural motion

TERTIARY objects react subtly:

furniture shifts slightly
small objects vibrate
plants sway

The ground remains mostly stable.

PHASE 3 — RELEASE PHASE

The structures elastically relax back to their original geometry as if the environment is exhaling.

All structural elements progressively unfold and straighten until the entire environment returns to its exact neutral configuration.

STEP 5 — CURVATURE PROPAGATION WAVES

Structural deformation does not occur instantly.

Instead, curvature travels through the structure like a wave.

Examples:

facades begin bending at one structural segment, then the curvature spreads across the building

walls begin flexing near structural joints and the bending travels across their length

balconies follow the curvature wave with slight delay

This creates a continuous flowing deformation rather than simultaneous bending.

STEP 6 — STRUCTURAL INERTIA TIMING

Large structures move slower than small ones.

Primary structures
move slowly with heavy inertia

Secondary structures
follow slightly delayed

Tertiary objects
react last with small vibrations or shifts

This creates realistic motion timing.

STEP 7 — AMPLITUDE SCALING

Deformation intensity depends on object scale.

Large architectural structures
bend dramatically with visible curvature.

Medium structures
bend moderately.

Small objects
barely deform but react through vibration or shifting.

No element detaches from its structure.

STEP 8 — MATERIAL RESPONSE

Each material behaves according to physical properties.

glass
distorts reflections and vibrates

metal
resonates with tension

concrete and stone
emit deep structural creaks

wood
flexes and produces strained timber sounds

fabric
ripples and rustles

vegetation
bends and brushes against itself

No materials break or shatter.

All deformation is elastic and reversible.

STEP 9 — ATMOSPHERIC RESPONSE

Environmental motion may release particles appropriate to the scene.

Examples:

dust from architectural seams
mist near the ground
small debris shifting

Lighting and reflections remain consistent with the original image.

STEP 10 — FINAL PROMPT GENERATION

Using the analysis above, generate a cinematic animation prompt using this exact structure.

STRUCTURE:

Study the uploaded image carefully and treat it as a single frozen cinematic moment. The visual style, lighting, color palette, textures, and atmosphere must remain exactly the same as in the original image.

Camera:

A centered wide-angle static shot. The camera does not move. The frame remains perfectly locked throughout the scene, like a tripod-mounted cinematic shot.

Subject Behavior:

The main subject of the image remains mostly still and stable, preserving its original pose and placement. Only extremely subtle natural micro-movements may occur.

Environmental Transformation:

Describe how the structures detected in the scene elastically flex inward during the contraction phase and return during the release phase.

Motion Dynamics:

Describe the curvature propagation waves and structural inertia timing.

Atmosphere:

Describe environmental particles and lighting interactions.

Tone:

The motion should feel dramatic yet controlled — powerful elastic deformation rather than destruction.

STEP 11 — NEUTRAL RESTORATION RULE

The animation must end with the environment returning to the exact neutral configuration seen in the original image.

The final frame must match the initial geometry and structure so that the breathing cycle forms a closed loop.'::text))
WHERE pipeline_id = 'fd100001-0001-4000-8000-000000000001'
  AND step_type = 'image_analyze' AND is_active = true;

-- =============================================================================
-- STEP 5: Set max_tokens = 8192 on ALL active image_analyze steps
-- =============================================================================
UPDATE public.pipeline_steps
SET config = jsonb_set(config, '{max_tokens}', '8192')
WHERE step_type = 'image_analyze' AND is_active = true;

COMMIT;
