import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "./logger.ts";

export interface GenerationGlobals {
  video_resolution: string | null;
  video_max_duration: number | null;
  video_aspect_ratio: string | null;
  image_enhance_enabled: boolean;
  image_analyze_enabled: boolean;
  prompt_enrich_enabled: boolean;
  image_enhance_model: string | null;
  image_analyze_model: string | null;
  prompt_enrich_model: string | null;
  video_generate_model: string | null;
  pipelines_enabled: boolean;
}

const DEFAULTS: GenerationGlobals = {
  video_resolution: null,
  video_max_duration: null,
  video_aspect_ratio: null,
  image_enhance_enabled: true,
  image_analyze_enabled: true,
  prompt_enrich_enabled: true,
  image_enhance_model: null,
  image_analyze_model: null,
  prompt_enrich_model: null,
  video_generate_model: null,
  pipelines_enabled: true,
};

let cached: GenerationGlobals | null = null;
let cachedAt = 0;
const CACHE_TTL_MS = 30_000;

export async function loadGenerationGlobals(
  supabase: ReturnType<typeof createClient>,
  logger: Logger,
): Promise<GenerationGlobals> {
  if (cached && Date.now() - cachedAt < CACHE_TTL_MS) {
    return cached;
  }

  try {
    const { data, error } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "generation_globals")
      .maybeSingle();

    if (error || !data) {
      logger.warn("generation_globals.load_failed", { metadata: { error: error?.message } });
      cached = { ...DEFAULTS };
    } else {
      cached = { ...DEFAULTS, ...(data.value as Partial<GenerationGlobals>) };
    }
  } catch (e) {
    logger.warn("generation_globals.exception", { metadata: { error: String(e) } });
    cached = { ...DEFAULTS };
  }

  cachedAt = Date.now();
  logger.info("generation_globals.loaded", { metadata: { globals: cached } });
  return cached;
}

export function applyVideoGlobals(
  globals: GenerationGlobals,
  params: { duration?: number; resolution?: string; aspectRatio?: string; model?: string },
): { duration: number; resolution: string; aspectRatio: string; model: string } {
  let duration = params.duration || 10;
  if (globals.video_max_duration != null && duration > globals.video_max_duration) {
    duration = globals.video_max_duration;
  }

  const resolution = globals.video_resolution || params.resolution || "720p";
  const aspectRatio = globals.video_aspect_ratio || params.aspectRatio || "9:16";
  const model = globals.video_generate_model || params.model || "grok-imagine-video";

  return { duration, resolution, aspectRatio, model };
}

export function isStepEnabled(globals: GenerationGlobals, stepType: string): boolean {
  switch (stepType) {
    case "image_enhance":
      return globals.image_enhance_enabled !== false;
    case "image_analyze":
      return globals.image_analyze_enabled !== false;
    case "prompt_enrich":
      return globals.prompt_enrich_enabled !== false;
    default:
      return true;
  }
}

export function getModelOverride(globals: GenerationGlobals, stepType: string): string | null {
  switch (stepType) {
    case "image_enhance":
      return globals.image_enhance_model || null;
    case "image_analyze":
      return globals.image_analyze_model || null;
    case "prompt_enrich":
      return globals.prompt_enrich_model || null;
    case "video_generate":
      return globals.video_generate_model || null;
    default:
      return null;
  }
}
