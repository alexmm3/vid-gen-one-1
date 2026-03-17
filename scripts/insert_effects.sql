DO $$ 
DECLARE
  viral_cat_id uuid;
BEGIN
  -- Insert or get the viral category
  INSERT INTO public.effect_categories (name, display_name, sort_order, is_active)
  VALUES ('viral', 'Viral', 1, true)
  ON CONFLICT (name) DO UPDATE SET display_name = EXCLUDED.display_name
  RETURNING id INTO viral_cat_id;

  -- Insert effects
  INSERT INTO public.effects (name, description, category_id, is_active, is_premium, sort_order, requires_secondary_photo, system_prompt_template, provider, generation_params)
  VALUES 
  (
    'The Cinematic Kiss', 
    'A highly realistic, romantic kissing scene between two people.', 
    viral_cat_id, true, false, 1, true, 
    'A highly realistic, cinematic, slow-motion video capturing a deeply romantic moment between the two people in the provided images. They lean in and share a passionate, tender kiss. The scene is beautifully composed with soft, warm golden-hour lighting, a shallow depth of field that blurs the background, and a gentle, dreamlike atmosphere. High fidelity, 4k resolution, photorealistic details. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Epic Dance Battle', 
    'Two people face off in a high-energy hip-hop dance battle.', 
    viral_cat_id, true, false, 2, true, 
    'A high-energy, dynamic video featuring the two people in the provided images engaged in an intense, fast-paced hip-hop breakdancing battle. The camera uses rapid, sweeping movements to capture their impressive, synchronized dance moves. The setting is an underground club with vibrant neon lighting, dynamic shadows, and a cheering crowd in the background. Cinematic motion blur, 4k resolution. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'We Got Married', 
    'A beautiful wedding ceremony scene walking down the aisle.', 
    viral_cat_id, true, false, 3, true, 
    'A hyper-realistic, beautiful video of the two people in the provided images walking down the aisle together at a luxurious, breathtaking wedding ceremony. They are wearing elegant, highly detailed wedding attire. The environment is filled with falling rose petals, bright joyful lighting, and elegantly dressed guests clapping in the background. Professional cinematography, 4k resolution, emotional and triumphant mood. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Pie in the Face', 
    'One person hilariously throws a cream pie into the other''s face.', 
    viral_cat_id, true, false, 4, true, 
    'A comedic, slapstick video where the first person in the provided images winds up and throws a massive, messy whipped cream pie directly into the face of the second person. The second person reacts with comical, exaggerated shock as the cream splatters everywhere. Shot in ultra slow-motion to emphasize the hilarious impact, with bright, cheerful lighting and sharp, realistic details. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Superhero Rescue', 
    'An action-movie scene where one person rescues the other.', 
    viral_cat_id, true, false, 5, true, 
    'A dramatic, Hollywood-style action-movie scene. The first person in the provided images is dressed in a highly detailed, textured superhero suit and swoops in to dramatically catch and rescue the second person from falling. The background features epic explosions, debris flying through the air, and cinematic high-contrast lighting. Wind blows through their hair in majestic slow motion. 4k resolution, blockbuster visual effects. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Slow-Mo Face Punch', 
    'A dramatic, slow-motion punch to the face from off-screen.', 
    viral_cat_id, true, false, 6, false, 
    'A dramatic, ultra slow-motion video of the person in the provided image getting punched in the face by a large, heavy boxing glove coming from the side of the screen. The person''s face ripples and distorts comically from the heavy impact, with sweat droplets flying through the air. Cinematic, high-contrast lighting highlights the textures and motion. Photorealistic, 4k resolution. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Anime Transformation', 
    'Morph into a stylized anime character performing a power move.', 
    viral_cat_id, true, false, 7, false, 
    'A dynamic, visually stunning video that starts with the realistic person in the provided image and seamlessly morphs them into a high-quality, 2D Japanese anime character. The character powers up with intense glowing auras, crackling energy sparks, and dynamic anime action lines streaking across the background. Vibrant colors, fluid animation, studio-quality anime aesthetic. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Age Timelapse', 
    'Rapidly age into an elderly person in a smooth timelapse.', 
    viral_cat_id, true, false, 8, false, 
    'A smooth, highly emotional timelapse video of the person in the provided image rapidly aging over time. Their face slowly and naturally develops realistic wrinkles, their hair gracefully turns gray and white, and their facial features mature into an elderly person. The transition is continuous and seamless, shot with soft, flattering studio lighting and photorealistic textures. 4k resolution. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Claymation Character', 
    'Transform into a cute, stop-motion claymation figure.', 
    viral_cat_id, true, false, 9, false, 
    'A cute, highly detailed stop-motion animation video where the person in the provided image transforms into a 3D claymation character, reminiscent of classic Aardman animations. The clay character blinks, smiles warmly, and waves playfully at the camera. The scene features tactile clay textures, visible fingerprints on the material, and a colorful, miniature-looking background. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Red Carpet Paparazzi', 
    'Strike a pose on a glamorous Hollywood red carpet.', 
    viral_cat_id, true, false, 10, false, 
    'A glamorous, high-fashion video of the person in the provided image standing confidently on a luxurious Hollywood red carpet. Hundreds of paparazzi cameras are flashing wildly in the background, creating a dazzling, energetic atmosphere. The person strikes a confident, stylish pose, smiling for the cameras. Cinematic depth of field, premium lighting, 4k resolution, photorealistic. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  ),
  (
    'Zombie Survivor', 
    'Transform into a gritty survivor in an apocalyptic wasteland.', 
    viral_cat_id, true, false, 11, false, 
    'A gritty, intense cinematic video where the person in the provided image transforms into a battle-worn survivor of a zombie apocalypse. The background shifts to a ruined, burning city with smoke billowing in the air. The person gets realistic dirt, grime, and scratches on their face, looking around with intense survival instincts. Dark, moody, apocalyptic lighting, 4k resolution, highly detailed. {{user_prompt}}', 
    'grok', 
    '{"duration": 6, "aspect_ratio": "9:16"}'::jsonb
  )
  ON CONFLICT DO NOTHING; -- Assuming we don't have a unique constraint on name, but we might. Let's just insert.
END $$;