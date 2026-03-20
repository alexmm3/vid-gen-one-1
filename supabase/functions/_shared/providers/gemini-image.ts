import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../logger.ts";

export interface GeminiImageInput {
  imageUrl: string;
  prompt: string;
  model?: string;
  quality?: string;
  /** Target output aspect ratio (e.g. "9:16", "16:9"). Supported by gemini-3.1-flash-image-preview. */
  targetAspectRatio?: string;
}

export interface GeminiImageOutput {
  imageUrl: string;
  storagePath: string;
}

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

export async function executeGeminiImage(
  input: GeminiImageInput,
  supabase: ReturnType<typeof createClient>,
  logger: Logger,
  executionId: string,
): Promise<GeminiImageOutput> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const model = input.model || "gemini-3.1-flash-image-preview";
  logger.info("gemini.image.start", {
    metadata: { model, prompt_length: input.prompt.length, target_aspect_ratio: input.targetAspectRatio },
  });

  const { base64, mimeType } = await fetchImageAsBase64(input.imageUrl);
  logger.info("gemini.image.fetched_source", { metadata: { mime: mimeType } });

  const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  // deno-lint-ignore no-explicit-any
  const generationConfig: Record<string, any> = {
    responseModalities: ["IMAGE", "TEXT"],
    temperature: 0.4,
  };

  generationConfig.imageConfig = {
    imageSize: "2K",
  };

  if (input.targetAspectRatio) {
    generationConfig.imageConfig.aspectRatio = input.targetAspectRatio;
  }

  const body = {
    contents: [
      {
        parts: [
          { text: input.prompt },
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

  if (!res.ok) {
    const errText = await res.text();
    // Fallback for region restrictions
    if (res.status === 400 && errText.includes("not available in your country")) {
      logger.warn("gemini.image.region_blocked", { metadata: { error: errText } });
      return { imageUrl: input.imageUrl, storagePath: "" };
    }
    throw new Error(`Gemini API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  logger.info("gemini.image.response_received");

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
    logger.warn("gemini.image.no_image_data", { metadata: { message: "Gemini response contained no image data, falling back to original image" } });
    return { imageUrl: input.imageUrl, storagePath: "" };
  }

  const ext = resultMime.includes("png") ? "png" : "jpg";
  const storagePath = `pipeline/${executionId}/enhanced.${ext}`;

  let binary = "";
  const decoded = atob(resultBase64);
  for (let i = 0; i < decoded.length; i++) {
    binary += String.fromCharCode(decoded.charCodeAt(i));
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

  const imageUrl = publicUrlData.publicUrl;
  logger.info("gemini.image.completed", { metadata: { storage_path: storagePath, url: imageUrl } });

  return { imageUrl, storagePath };
}
