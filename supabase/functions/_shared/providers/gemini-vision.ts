import { Logger } from "../logger.ts";

export interface GeminiVisionInput {
  imageUrl: string;
  prompt: string;
  model?: string;
  maxTokens?: number;
}

export interface GeminiVisionOutput {
  description: string;
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

export async function executeGeminiVision(
  input: GeminiVisionInput,
  logger: Logger,
): Promise<GeminiVisionOutput> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const model = input.model || "gemini-3.1-pro-preview";
  logger.info("gemini.vision.start", {
    metadata: { model, prompt_length: input.prompt.length },
  });

  const { base64, mimeType } = await fetchImageAsBase64(input.imageUrl);
  logger.info("gemini.vision.fetched_source", { metadata: { mime: mimeType } });

  const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const body = {
    contents: [
      {
        parts: [
          { text: input.prompt },
          { inline_data: { mime_type: mimeType, data: base64 } },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.4,
      maxOutputTokens: input.maxTokens || 500,
    },
  };

  const res = await fetch(apiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini Vision API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const candidates = data.candidates;
  if (!candidates?.length) throw new Error("Gemini Vision returned no candidates");

  let description = "";
  for (const part of candidates[0].content?.parts || []) {
    if (part.text) {
      description += part.text;
    }
  }

  description = description.trim();
  if (!description) throw new Error("Gemini Vision returned no text content");

  logger.info("gemini.vision.completed", {
    metadata: { description_length: description.length },
  });
  return { description };
}
