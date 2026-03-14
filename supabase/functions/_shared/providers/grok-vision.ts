import { Logger } from "../logger.ts";

export interface GrokVisionInput {
  imageUrl: string;
  prompt: string;
  model?: string;
  maxTokens?: number;
}

export interface GrokVisionOutput {
  description: string;
}

export async function executeGrokVision(
  input: GrokVisionInput,
  logger: Logger,
): Promise<GrokVisionOutput> {
  const apiKey = Deno.env.get("GROK_API_KEY");
  if (!apiKey) throw new Error("GROK_API_KEY not configured");

  const model = input.model || "grok-4-1-fast-non-reasoning";
  logger.info("grok.vision.start", { metadata: { model, prompt_length: input.prompt.length } });

  const body = {
    model,
    messages: [
      {
        role: "user",
        content: [
          { type: "image_url", image_url: { url: input.imageUrl } },
          { type: "text", text: input.prompt },
        ],
      },
    ],
    max_tokens: input.maxTokens || 500,
    temperature: 0.3,
  };

  const res = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Grok Vision API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const description = data.choices?.[0]?.message?.content?.trim();
  if (!description) throw new Error("Grok Vision returned no content");

  logger.info("grok.vision.completed", { metadata: { description_length: description.length } });
  return { description };
}
