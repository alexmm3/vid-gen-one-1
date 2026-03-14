/**
 * Aspect ratio detection and resolution utilities.
 *
 * Maps arbitrary image dimensions to the set of standard ratios supported by
 * both Gemini image editing and Grok video generation, and resolves the final
 * target aspect ratio for a pipeline run using the priority chain:
 *   effect.forced_aspect_ratio → client detected → effect default → provider default → "9:16"
 */

export const SUPPORTED_ASPECT_RATIOS = [
  "9:16",
  "3:4",
  "1:1",
  "4:3",
  "16:9",
] as const;

export type SupportedAspectRatio = (typeof SUPPORTED_ASPECT_RATIOS)[number];

const RATIO_VALUES: Record<SupportedAspectRatio, number> = {
  "9:16": 9 / 16,   // 0.5625
  "3:4": 3 / 4,     // 0.75
  "1:1": 1,
  "4:3": 4 / 3,     // 1.333
  "16:9": 16 / 9,   // 1.778
};

/**
 * Classify a width/height ratio to the nearest supported standard.
 * Boundaries are geometric midpoints between adjacent ratios.
 */
export function classifyAspectRatio(widthOverHeight: number): SupportedAspectRatio {
  if (widthOverHeight < 0.66) return "9:16";
  if (widthOverHeight < 0.87) return "3:4";
  if (widthOverHeight < 1.15) return "1:1";
  if (widthOverHeight < 1.55) return "4:3";
  return "16:9";
}

function isSupported(value: string): value is SupportedAspectRatio {
  return (SUPPORTED_ASPECT_RATIOS as readonly string[]).includes(value);
}

/**
 * Parse an aspect ratio string like "9:16" into a numeric w/h value.
 */
export function parseAspectRatio(ratio: string): number | null {
  const parts = ratio.split(":");
  if (parts.length !== 2) return null;
  const w = parseFloat(parts[0]);
  const h = parseFloat(parts[1]);
  if (!w || !h) return null;
  return w / h;
}

/**
 * Get the numeric w/h value for a supported aspect ratio string.
 */
export function aspectRatioValue(ratio: SupportedAspectRatio): number {
  return RATIO_VALUES[ratio];
}

export interface AspectRatioResolutionInput {
  /** Admin-configured forced ratio on the effect (overrides everything) */
  effectForcedAspectRatio?: string;
  /** Client-detected ratio sent from iOS */
  detectedAspectRatio?: string;
  /** Default ratio from effect.generation_params.aspect_ratio */
  effectDefaultAspectRatio?: string;
  /** Default from provider_config */
  providerDefaultAspectRatio?: string;
}

/**
 * Resolve the target aspect ratio for a generation run.
 *
 * Priority: forced → detected → effect default → provider default → "9:16"
 *
 * Any value that isn't in SUPPORTED_ASPECT_RATIOS is ignored so that an
 * invalid client value can never break the pipeline.
 */
export function resolveTargetAspectRatio(
  input: AspectRatioResolutionInput,
): SupportedAspectRatio {
  const candidates = [
    input.effectForcedAspectRatio,
    input.detectedAspectRatio,
    input.effectDefaultAspectRatio,
    input.providerDefaultAspectRatio,
  ];

  for (const candidate of candidates) {
    if (candidate && isSupported(candidate)) {
      return candidate;
    }
  }

  return "9:16";
}
