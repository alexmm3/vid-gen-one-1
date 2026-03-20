import { load } from "https://deno.land/std@0.208.0/dotenv/mod.ts";

async function run() {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const model = "gemini-3.1-flash-image-preview";
  const prompt = "Transform this image into a high-end cinematic film still. Apply a heavy, visible cinematic transformation — not a subtle enhancement. Crush the blacks. Deepen the shadows with cool or teal bias. Protect and roll off the highlights with warm, filmic softness. Push strong contrast between light and dark — carve the subject out of the background using light alone. Reshape the lighting into dramatic cinematic structure. Sculpt the subject with hard directional key light. Add strong rim light or backlight for edge separation. If the existing light is flat or ambient, introduce bold, motivated lighting that makes sense for the scene. Light should sculpt form, not just illuminate it. If people are visible: preserve their identity, face, anatomy, and expression exactly. Sculpt the face with dramatic key light. Add bright catch-lights in the eyes. Add rim or hair light separating them from background. Skin should glow with warm subsurface light. Apply shallow depth of field — subject razor-sharp, background falling into rich cinematic bokeh. Apply a punchy cinematic color grade — teal and orange, or cool shadows against warm highlights, or deep complementary split. Saturate selectively, not globally. Midtones rich and weighted. Add deep atmosphere — haze, volumetric light, mist, dust motes, or ambient particulate, whatever fits the scene. Push it until the air has visible texture. Add fine film grain across the full frame. Add gentle halation bloom on the hottest highlights. Add a subtle optical vignette pulling the eye inward. Every surface should feel premium and tactile under cinematic light — glass, metal, skin, fabric, wood, water — all with rich light interaction, specular kick, and micro-shadow detail. Preserve the original composition, framing, subject placement, and scene content exactly. Do not add, remove, or relocate anything. Only transform the light, contrast, color, atmosphere, depth, and texture — aggressively. The result must look like a single frame pulled from a high-budget film. Shot on celluloid. Graded by a master colorist. Unmistakably cinematic.";
  
  const imageUrl = "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&q=80";

  const resImage = await fetch(imageUrl);
  const buffer = await resImage.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  const mimeType = resImage.headers.get("content-type") || "image/jpeg";

  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64 = btoa(binary);

  const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const generationConfig: Record<string, any> = {
    responseModalities: ["IMAGE", "TEXT"],
    temperature: 0.4,
  };

  const body = {
    contents: [
      {
        parts: [
          { text: prompt },
          { inline_data: { mime_type: mimeType, data: base64 } },
        ],
      },
    ],
    generationConfig,
  };

  console.log("Sending request...");
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const data = await res.json();
  console.log(JSON.stringify(data, null, 2).substring(0, 1000));
}

run().catch(console.error);
