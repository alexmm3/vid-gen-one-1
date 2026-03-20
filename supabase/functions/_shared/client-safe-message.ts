/**
 * User-facing copy must not reveal vendors, models, or infrastructure.
 * Use for HTTP error bodies, generations.error_message, and related fields shown in the app.
 */

export const CLIENT_SAFE_GENERATION_FAILED =
  "We couldn’t finish your video. Please try again in a moment.";

/** Internal / logging-only detail; pair with CLIENT_SAFE_GENERATION_FAILED for clients. */
export function toInternalErrorDetail(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

const LEAK_PATTERN = new RegExp(
  [
    "grok",
    "groq",
    "gemini",
    "supabase",
    "openai",
    "anthropic",
    "claude",
    "mistral",
    "replicate",
    "nanobanana",
    "modelslab",
    "together\\.ai",
    "fireworks\\.ai",
    "cohere",
    "deepseek",
    "vertex",
    "generativelanguage",
    "googleapis",
    "gpt-",
    "gpt4",
    "\\bx\\.ai\\b",
    "api\\.x\\.ai",
    "GROK_",
    "GEMINI_",
    "OPENAI_",
    "\\bgrok[-_]",
    "\\bgemini[-_]",
    "dall-?e",
    "stable\\s*diffusion",
    "midjourney",
  ].join("|"),
  "i",
);

const MAX_CLIENT_ERROR_LEN = 320;

function looksLikeNetworkDump(msg: string): boolean {
  if (msg.length > MAX_CLIENT_ERROR_LEN) return true;
  if (/https?:\/\//i.test(msg)) return true;
  if (/^\s*[\[{][\s\S]*[}\]]\s*$/.test(msg) && msg.includes('"')) return true;
  return false;
}

/**
 * Returns a string safe to show in the mobile app or store on generation rows.
 */
export function toClientSafeMessage(raw: unknown, fallback = CLIENT_SAFE_GENERATION_FAILED): string {
  if (raw == null) return fallback;
  const msg = typeof raw === "string" ? raw.trim() : String(raw).trim();
  if (!msg) return fallback;
  if (LEAK_PATTERN.test(msg)) return fallback;
  if (looksLikeNetworkDump(msg)) return fallback;
  return msg;
}

/** For nullable DB fields: null stays null; leaky strings become the generic client message. */
export function toNullableClientSafeMessage(
  raw: unknown | null | undefined,
): string | null {
  if (raw == null) return null;
  const msg = typeof raw === "string" ? raw.trim() : String(raw).trim();
  if (!msg) return null;
  if (LEAK_PATTERN.test(msg)) return CLIENT_SAFE_GENERATION_FAILED;
  if (looksLikeNetworkDump(msg)) return CLIENT_SAFE_GENERATION_FAILED;
  return msg;
}

/**
 * Strip provider/model details from generation api_response before sending to clients.
 */
export function redactGenerationApiResponseForClient(
  apiResponse: unknown,
): Record<string, unknown> | null {
  if (!apiResponse || typeof apiResponse !== "object" || Array.isArray(apiResponse)) {
    return null;
  }
  const o = apiResponse as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  if (typeof o.request_id === "string") out.request_id = o.request_id;
  if (typeof o.id === "number") out.id = o.id;
  if (typeof o.status === "string") out.status = o.status;
  if (typeof o.eta === "number") out.eta = o.eta;
  if (typeof o.pipeline_execution_id === "string") {
    out.pipeline_execution_id = o.pipeline_execution_id;
  }
  return Object.keys(out).length ? out : null;
}
