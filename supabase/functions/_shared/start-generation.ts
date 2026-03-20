import { Logger, withRetry } from "./logger.ts";
import { runPipeline, type PipelineContext } from "./pipeline-orchestrator.ts";
import { loadGenerationGlobals, applyVideoGlobals } from "./generation-globals.ts";
import { resolveTargetAspectRatio } from "./aspect-ratio.ts";
import { toClientSafeMessage } from "./client-safe-message.ts";
import type { SupabaseClientLike } from "./supabase-client.ts";

interface ProviderConfig {
  default_duration?: number;
  default_resolution?: string;
  default_aspect_ratio?: string;
  default_model_id?: string;
}

interface GrokStartResponse {
  request_id?: string;
  error?: { message?: string };
}

export interface StartableEffect {
  id: string;
  name: string;
  is_active: boolean;
  system_prompt_template: string;
  generation_params?: Record<string, unknown> | null;
  ai_model_id?: string | null;
}

export interface StartGenerationInput {
  generationId: string;
  deviceId: string;
  effect: StartableEffect;
  inputImageUrl: string;
  secondaryImageUrl?: string | null;
  userPrompt?: string | null;
  detectedAspectRatio?: string | null;
  finalPrompt: string;
  existingPipelineExecutionId?: string | null;
}

export interface StartGenerationResult {
  success: boolean;
  status: "processing" | "completed" | "failed";
  pipelineExecutionId?: string;
  providerRequestId?: string;
  error?: string;
}

interface RecoverableGenerationRow {
  id: string;
  device_id: string;
  effect_id: string;
  input_image_url: string;
  secondary_image_url: string | null;
  prompt: string | null;
  input_payload: Record<string, unknown> | null;
  pipeline_execution_id: string | null;
}

async function loadProviderConfig(
  supabase: SupabaseClientLike,
  provider: string,
): Promise<ProviderConfig> {
  const { data } = await supabase
    .from("provider_config")
    .select("config")
    .eq("provider", provider)
    .maybeSingle();
  return (data?.config as ProviderConfig) ?? {};
}

function stripLegacyUserPromptPlaceholder(template: string): string {
  if (!template.includes("{{user_prompt}}")) {
    return template;
  }

  return template.replace("{{user_prompt}}", "").trim();
}

async function supersedePipelineExecution(
  supabase: SupabaseClientLike,
  pipelineExecutionId: string | null | undefined,
  logger: Logger,
) {
  if (!pipelineExecutionId) return;

  logger.info("pipeline.superseding_existing_execution", {
    metadata: { pipeline_execution_id: pipelineExecutionId },
  });

  await supabase
    .from("pipeline_executions")
    .update({
      status: "failed",
      error_message: "Superseded by backend recovery restart",
      completed_at: new Date().toISOString(),
    })
    .eq("id", pipelineExecutionId)
    .neq("status", "completed");
}

export async function startGeneration(
  supabase: SupabaseClientLike,
  logger: Logger,
  input: StartGenerationInput,
): Promise<StartGenerationResult> {
  const {
    generationId,
    deviceId,
    effect,
    inputImageUrl,
    secondaryImageUrl,
    userPrompt,
    detectedAspectRatio,
    finalPrompt,
    existingPipelineExecutionId,
  } = input;

  logger.setGenerationId(generationId);

  await supabase
    .from("generations")
    .update({
      request_id: logger.getRequestId(),
      error_message: null,
      last_error_at: null,
    })
    .eq("id", generationId);

  const preGlobals = await loadGenerationGlobals(supabase, logger);

  const { data: effectPipeline } = await supabase
    .from("effect_pipelines")
    .select("pipeline_id, config_overrides, pipeline_templates!inner(id, is_active)")
    .eq("effect_id", effect.id)
    .eq("is_active", true)
    .limit(1)
    .maybeSingle();

  if (effectPipeline?.pipeline_id && preGlobals.pipelines_enabled !== false) {
    logger.info("pipeline.routing", { metadata: { pipeline_id: effectPipeline.pipeline_id } });

    try {
      await supersedePipelineExecution(supabase, existingPipelineExecutionId, logger);

      const targetAspectRatio = resolveTargetAspectRatio({
        detectedAspectRatio: detectedAspectRatio ?? undefined,
        effectDefaultAspectRatio: (effect.generation_params as Record<string, unknown> | undefined)?.aspect_ratio as
          | string
          | undefined,
      });

      const pipelineContext: PipelineContext = {
        user_image: inputImageUrl,
        user_prompt: userPrompt || "",
        effect_id: effect.id,
        effect_name: effect.name,
        effect_concept: effect.system_prompt_template,
        effect_concept_resolved: finalPrompt,
        target_aspect_ratio: targetAspectRatio,
        ...(secondaryImageUrl ? { secondary_image: secondaryImageUrl } : {}),
      };

      const pipelineResult = await runPipeline(
        effectPipeline.pipeline_id,
        generationId,
        pipelineContext,
        supabase,
        logger,
      );

      if (pipelineResult.providerRequestId) {
        await supabase
          .from("generations")
          .update({
            status: "processing",
            prompt: pipelineResult.finalPrompt || finalPrompt,
            provider_request_id: pipelineResult.providerRequestId,
            pipeline_execution_id: pipelineResult.pipelineExecutionId,
            api_response: {
              provider: "grok",
              request_id: pipelineResult.providerRequestId,
              pipeline_execution_id: pipelineResult.pipelineExecutionId,
            },
            error_log: logger.getLogs(),
          })
          .eq("id", generationId);

        return {
          success: true,
          status: "processing",
          pipelineExecutionId: pipelineResult.pipelineExecutionId,
          providerRequestId: pipelineResult.providerRequestId,
        };
      }

      await supabase
        .from("generations")
        .update({
          status: "completed",
          pipeline_execution_id: pipelineResult.pipelineExecutionId,
          error_log: logger.getLogs(),
        })
        .eq("id", generationId);

      return {
        success: true,
        status: "completed",
        pipelineExecutionId: pipelineResult.pipelineExecutionId,
      };
    } catch (pipelineError) {
      const errMsg = pipelineError instanceof Error ? pipelineError.message : String(pipelineError);
      logger.error("pipeline.failed", pipelineError instanceof Error ? pipelineError : new Error(errMsg));

      const clientMsg = toClientSafeMessage(errMsg);

      await supabase
        .from("generations")
        .update({
          status: "failed",
          error_message: clientMsg,
          error_log: logger.getLogs(),
        })
        .eq("id", generationId);

      await supabase.from("failed_generations").insert({
        original_generation_id: generationId,
        device_id: deviceId,
        failure_reason: "pipeline_execution_failed",
        final_error_message: clientMsg,
        error_log: logger.getLogs(),
        retry_count: 0,
      });

      return {
        success: false,
        status: "failed",
        error: clientMsg,
      };
    }
  }

  const grokApiKey = Deno.env.get("GROK_API_KEY");
  if (!grokApiKey) {
    logger.error("config.missing", "GROK_API_KEY not configured");
    const clientMsg = toClientSafeMessage("GROK_API_KEY not configured");
    await supabase
      .from("generations")
      .update({
        status: "failed",
        error_message: clientMsg,
        error_log: logger.getLogs(),
      })
      .eq("id", generationId);

    return {
      success: false,
      status: "failed",
      error: clientMsg,
    };
  }

  const providerCfg = await loadProviderConfig(supabase, "grok");
  const effectParams = (effect.generation_params || {}) as Record<string, unknown>;
  const globals = await loadGenerationGlobals(supabase, logger);

  const rawDuration = (effectParams.duration as number) ?? providerCfg.default_duration ?? 10;
  const rawResolution = (effectParams.resolution as string) ?? providerCfg.default_resolution ?? "720p";
  const rawAspectRatio = (effectParams.aspect_ratio as string) ?? providerCfg.default_aspect_ratio ?? "9:16";
  const rawModel = effect.ai_model_id
    || (effectParams.model_id as string)
    || providerCfg.default_model_id
    || "grok-imagine-video";

  const videoParams = applyVideoGlobals(globals, {
    duration: rawDuration,
    resolution: rawResolution,
    aspectRatio: rawAspectRatio,
    model: rawModel,
  });

  let grokPrompt = finalPrompt;
  if (userPrompt && userPrompt.trim().length > 0) {
    grokPrompt += `\n\n---
USER'S CUSTOM INSTRUCTIONS:
The user has provided additional specific wishes for this video. You must maintain the overall style and core concept described in the prompt above, but please try your best to incorporate the following user recommendations:
"${userPrompt.trim()}"
---`;
  }

  const grokBody: Record<string, unknown> = {
    model: videoParams.model,
    prompt: grokPrompt,
    image: { url: inputImageUrl },
    duration: videoParams.duration,
    aspect_ratio: videoParams.aspectRatio,
    resolution: videoParams.resolution,
  };

  logger.info("grok.calling", {
    metadata: {
      duration: videoParams.duration,
      resolution: videoParams.resolution,
      aspect_ratio: videoParams.aspectRatio,
      globals_applied: true,
    },
  });

  const grokCall = async (): Promise<GrokStartResponse> => {
    const res = await fetch("https://api.x.ai/v1/videos/generations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${grokApiKey}`,
      },
      body: JSON.stringify(grokBody),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Grok API ${res.status}: ${errText}`);
    }

    return res.json();
  };

  const retryResult = await withRetry(grokCall, logger, { maxRetries: 1 });

  if ("error" in retryResult) {
    logger.error("grok.failed_permanently", retryResult.error);
    const clientMsg = toClientSafeMessage(retryResult.error.message);
    await supabase
      .from("generations")
      .update({
        status: "failed",
        error_message: clientMsg,
        retry_count: retryResult.attempts,
        last_error_at: new Date().toISOString(),
        error_log: logger.getLogs(),
      })
      .eq("id", generationId);

    await supabase.from("failed_generations").insert({
      original_generation_id: generationId,
      device_id: deviceId,
      failure_reason: "grok_api_call_failed",
      final_error_message: clientMsg,
      error_log: logger.getLogs(),
      retry_count: retryResult.attempts,
    });

    return {
      success: false,
      status: "failed",
      error: clientMsg,
    };
  }

  const grokResult = retryResult.result;
  logger.info("grok.response_received", { api_response: grokResult });

  if (!grokResult.request_id) {
    const errMsg = grokResult.error?.message || "Grok did not return a request_id";
    logger.error("grok.no_request_id", errMsg);
    const clientMsg = toClientSafeMessage(errMsg);

    await supabase
      .from("generations")
      .update({
        status: "failed",
        error_message: clientMsg,
        api_response: grokResult,
        error_log: logger.getLogs(),
      })
      .eq("id", generationId);

    return {
      success: false,
      status: "failed",
      error: clientMsg,
    };
  }

  await supabase
    .from("generations")
    .update({
      status: "processing",
      provider_request_id: grokResult.request_id,
      api_response: { provider: "grok", request_id: grokResult.request_id },
      retry_count: retryResult.attempts,
      error_log: logger.getLogs(),
    })
    .eq("id", generationId);

  logger.info("grok.generation_queued", { metadata: { grok_request_id: grokResult.request_id } });

  return {
    success: true,
    status: "processing",
    providerRequestId: grokResult.request_id,
  };
}

export async function recoverGenerationStart(
  supabase: SupabaseClientLike,
  logger: Logger,
  generationId: string,
): Promise<StartGenerationResult | null> {
  const { data: generation, error: generationError } = await supabase
    .from("generations")
    .select("id, device_id, effect_id, input_image_url, secondary_image_url, prompt, input_payload, pipeline_execution_id")
    .eq("id", generationId)
    .single();

  if (generationError || !generation) {
    logger.warn("recovery.generation_not_found", { metadata: { generation_id: generationId } });
    return null;
  }

  const generationRow = generation as RecoverableGenerationRow;

  if (!generationRow.effect_id || !generationRow.input_image_url) {
    logger.warn("recovery.generation_missing_required_fields", { metadata: { generation_id: generationId } });
    return null;
  }

  const { data: effect, error: effectError } = await supabase
    .from("effects")
    .select("id, name, is_active, system_prompt_template, generation_params, ai_model_id")
    .eq("id", generationRow.effect_id)
    .single();

  if (effectError || !effect) {
    logger.warn("recovery.effect_not_found", {
      metadata: { generation_id: generationId, effect_id: generationRow.effect_id },
    });
    return null;
  }

  const payload = (generationRow.input_payload || {}) as Record<string, unknown>;
  const userPrompt = typeof payload.user_prompt === "string" ? payload.user_prompt : null;
  const detectedAspectRatio = typeof payload.detected_aspect_ratio === "string"
    ? payload.detected_aspect_ratio
    : (typeof payload.target_aspect_ratio === "string" ? payload.target_aspect_ratio : null);
  const finalPrompt = generationRow.prompt
    || stripLegacyUserPromptPlaceholder(effect.system_prompt_template);

  logger.info("recovery.restarting_generation", { metadata: { generation_id: generationId } });

  return startGeneration(supabase, logger, {
    generationId: generationRow.id,
    deviceId: generationRow.device_id,
    effect,
    inputImageUrl: generationRow.input_image_url,
    secondaryImageUrl: generationRow.secondary_image_url,
    userPrompt,
    detectedAspectRatio,
    finalPrompt,
    existingPipelineExecutionId: generationRow.pipeline_execution_id,
  });
}
