import { Logger } from "../logger.ts";

export interface GrokTextInput {
  prompt: string;
  model?: string;
  maxTokens?: number;
  temperature?: number;
}

export interface GrokTextOutput {
  text: string;
}

export async function executeGrokText(
  input: GrokTextInput,
  logger: Logger,
): Promise<GrokTextOutput> {
  const apiKey = Deno.env.get("GROK_API_KEY");
  if (!apiKey) throw new Error("GROK_API_KEY not configured");

  const model = input.model || "grok-3-mini-fast";
  logger.info("grok.text.start", { metadata: { model, prompt_length: input.prompt.length } });

  const body = {
    model,
    messages: [
      { role: "user", content: input.prompt },
    ],
    max_tokens: input.maxTokens || 1000,
    temperature: input.temperature ?? 0.7,
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
    throw new Error(`Grok Text API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const text = data.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error("Grok Text returned no content");

  logger.info("grok.text.completed", { metadata: { output_length: text.length } });
  return { text };
}
