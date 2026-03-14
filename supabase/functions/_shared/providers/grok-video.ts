import { Logger, withRetry } from "../logger.ts";

export interface GrokVideoInput {
  imageUrl: string;
  prompt: string;
  model?: string;
  duration?: number;
  aspectRatio?: string;
  resolution?: string;
}

export interface GrokVideoOutput {
  requestId: string;
}

export async function executeGrokVideo(
  input: GrokVideoInput,
  logger: Logger,
): Promise<GrokVideoOutput> {
  const apiKey = Deno.env.get("GROK_API_KEY");
  if (!apiKey) throw new Error("GROK_API_KEY not configured");

  const model = input.model || "grok-imagine-video";
  logger.info("grok.video.start", {
    metadata: {
      model,
      duration: input.duration,
      aspect_ratio: input.aspectRatio,
      resolution: input.resolution,
    },
  });

  const body: Record<string, unknown> = {
    model,
    prompt: input.prompt,
    image: { url: input.imageUrl },
    duration: input.duration || 10,
    aspect_ratio: input.aspectRatio || "9:16",
    resolution: input.resolution || "720p",
  };

  const grokCall = async () => {
    const res = await fetch("https://api.x.ai/v1/videos/generations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Grok Video API ${res.status}: ${errText}`);
    }
    return res.json();
  };

  const retryResult = await withRetry(grokCall, logger, { maxRetries: 1 });

  if ("error" in retryResult) {
    throw retryResult.error;
  }

  const result = retryResult.result;
  if (!result || !result.request_id) {
    const errMsg = result?.error?.message || "Grok did not return a request_id";
    throw new Error(errMsg);
  }

  logger.info("grok.video.queued", { metadata: { request_id: result.request_id } });
  return { requestId: result.request_id };
}
