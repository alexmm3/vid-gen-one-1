import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

async function fetchImageAsBase64(url: string): Promise<{ base64: string; mimeType: string }> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch image: HTTP ${res.status}`);
  const buffer = await res.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  const mimeType = res.headers.get("content-type") || "image/jpeg";

  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return { base64: btoa(binary), mimeType };
}

serve(async (req) => {
  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const bodyJson = await req.json();
    const prompt = bodyJson.prompt || "Transform this image into a high-end cinematic film still.";
    const imageUrl = bodyJson.imageUrl || "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&q=80";
    const model = bodyJson.model || "gemini-3.1-flash-image-preview";
    const responseModalities = bodyJson.responseModalities || ["IMAGE", "TEXT"];

    const { base64, mimeType } = await fetchImageAsBase64(imageUrl);

    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const generationConfig: Record<string, any> = {
      responseModalities,
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

    const res = await fetch(apiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    const data = await res.json();
    const candidates = data.candidates;
    if (!candidates?.length) throw new Error("Gemini returned no candidates");

    let resultBase64: string | null = null;
    let resultMime = "image/png";

    for (const part of candidates[0].content?.parts || []) {
      const inlineData = part.inlineData || part.inline_data;
      if (inlineData) {
        resultBase64 = inlineData.data;
        resultMime = inlineData.mimeType || inlineData.mime_type || "image/png";
        break;
      }
    }

    if (!resultBase64) {
      return new Response(JSON.stringify({ error: "No image data returned", data }), { status: 400 });
    }

    const ext = resultMime.includes("png") ? "png" : "jpg";
    const storagePath = `test-gemini/enhanced-${Date.now()}.${ext}`;

    let binaryResult = "";
    const decoded = atob(resultBase64);
    for (let i = 0; i < decoded.length; i++) {
      binaryResult += String.fromCharCode(decoded.charCodeAt(i));
    }
    const imageBytes = new Uint8Array(decoded.length);
    for (let i = 0; i < decoded.length; i++) {
      imageBytes[i] = decoded.charCodeAt(i);
    }

    const { error: uploadErr } = await supabase.storage
      .from("pipeline-artifacts")
      .upload(storagePath, imageBytes, { contentType: resultMime, upsert: true });

    if (uploadErr) throw new Error(`Storage upload failed: ${uploadErr.message}`);

    const { data: publicUrlData } = supabase.storage
      .from("pipeline-artifacts")
      .getPublicUrl(storagePath);

    return new Response(JSON.stringify({ imageUrl: publicUrlData.publicUrl }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});