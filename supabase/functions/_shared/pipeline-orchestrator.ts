import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "./logger.ts";
import { executeGeminiImage } from "./providers/gemini-image.ts";
import { executeGeminiVision } from "./providers/gemini-vision.ts";
import { executeGrokVision } from "./providers/grok-vision.ts";
import { executeGrokText } from "./providers/grok-text.ts";
import { executeGrokVideo } from "./providers/grok-video.ts";
import {
  loadGenerationGlobals,
  applyVideoGlobals,
  isStepEnabled,
  getModelOverride,
  type GenerationGlobals,
} from "./generation-globals.ts";

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;

export interface PipelineContext {
  user_image: string;
  user_prompt: string;
  effect_id: string;
  effect_name: string;
  effect_concept: string;
  secondary_image?: string;
  /** Resolved target aspect ratio for all pipeline steps (e.g. "9:16", "16:9", "1:1") */
  target_aspect_ratio?: string;
  [key: string]: unknown;
}

export interface PipelineStep {
  id: string;
  pipeline_id: string;
  step_order: number;
  step_type: string;
  name: string;
  provider: string;
  config: Json;
  input_mapping: Json;
  output_mapping: Json;
  is_required: boolean;
  timeout_seconds: number;
  retry_config: Json;
  is_active: boolean;
}

export interface PipelineResult {
  pipelineExecutionId: string;
  providerRequestId?: string;
  finalPrompt?: string;
  finalImageUrl?: string;
  context: PipelineContext;
  grokVideoAttempts?: number;
}

/**
 * Resolve a dotted path from the pipeline context.
 * Supports: "pipeline.user_image", "steps.image_analyze.output.image_description"
 */
function resolveContextValue(context: PipelineContext, path: string): unknown {
  const parts = path.split(".");
  if (parts[0] === "pipeline") {
    return context[parts.slice(1).join(".")];
  }
  
  // deno-lint-ignore no-explicit-any
  let current: any = context;
  for (const part of parts) {
    if (current == null) return undefined;
    current = current[part];
  }
  return current;
}

/**
 * Resolve all input mappings for a step from the pipeline context.
 */
function resolveInputs(context: PipelineContext, inputMapping: Json): Json {
  const resolved: Json = {};
  for (const [key, path] of Object.entries(inputMapping)) {
    if (typeof path === "string") {
      resolved[key] = resolveContextValue(context, path);
    } else {
      resolved[key] = path;
    }
  }
  return resolved;
}

/**
 * Store step outputs into the pipeline context via output_mapping.
 */
function storeOutputs(context: PipelineContext, stepName: string, outputMapping: Json, result: Json): void {
  // Store in the steps namespace
  if (!context.steps) {
    context.steps = {};
  }
  (context.steps as any)[stepName] = { output: result };

  // Also map to specific context keys if requested
  for (const [contextKey, resultPath] of Object.entries(outputMapping)) {
    if (typeof resultPath === "string") {
      let path = resultPath;
      if (path.startsWith("result.")) {
        path = path.substring(7); // remove "result."
      }
      const parts = path.split(".");
      // deno-lint-ignore no-explicit-any
      let current: any = result;
      for (const part of parts) {
        if (current == null) break;
        current = current[part];
      }
      context[contextKey] = current;
    }
  }
}

/**
 * Substitute template variables like {{image_description}} from context.
 */
function substituteTemplate(template: string, context: PipelineContext): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key) => {
    const value = context[key];
    return value != null ? String(value) : "";
  });
}

/**
 * Execute a single pipeline step.
 */
async function executeStep(
  step: PipelineStep,
  context: PipelineContext,
  supabase: ReturnType<typeof createClient>,
  logger: Logger,
  pipelineExecutionId: string,
  globals: GenerationGlobals,
): Promise<{ result: Json; providerRequestId?: string }> {
  const inputs = resolveInputs(context, step.input_mapping);
  const config = step.config;
  const modelOverride = getModelOverride(globals, step.step_type);

  const promptTemplate = config.prompt_template as string | undefined;
  const resolvedPrompt = promptTemplate ? substituteTemplate(promptTemplate, context) : "";

  switch (step.step_type) {
    case "image_enhance": {
      const imageUrl = (inputs.image as string) || context.user_image;
      const output = await executeGeminiImage(
        {
          imageUrl,
          prompt: resolvedPrompt,
          model: modelOverride || (config.model as string | undefined),
          quality: config.quality as string | undefined,
          targetAspectRatio: (config.aspect_ratio as string) || (context.target_aspect_ratio as string) || undefined,
        },
        supabase,
        logger,
        pipelineExecutionId,
      );
      return {
        result: {
          image_url: output.imageUrl,
          storage_path: output.storagePath,
        },
      };
    }

    case "image_analyze": {
      const imageUrl = (inputs.image as string) || context.user_image;
      const outputKey = (config.output_key as string) || "image_description";

      if (step.provider === "gemini") {
        const output = await executeGeminiVision(
          {
            imageUrl,
            prompt: resolvedPrompt,
            model: modelOverride || (config.model as string | undefined),
            maxTokens: config.max_tokens as number | undefined,
          },
          logger,
        );
        return { result: { [outputKey]: output.description } };
      }

      const output = await executeGrokVision(
        {
          imageUrl,
          prompt: resolvedPrompt,
          model: modelOverride || (config.model as string | undefined),
          maxTokens: config.max_tokens as number | undefined,
        },
        logger,
      );
      return { result: { [outputKey]: output.description } };
    }

    case "prompt_enrich": {
      const output = await executeGrokText(
        {
          prompt: resolvedPrompt,
          model: modelOverride || (config.model as string | undefined),
          maxTokens: config.max_tokens as number | undefined,
        },
        logger,
      );
      const outputKey = (config.output_key as string) || "enriched_prompt";
      return { result: { [outputKey]: output.text } };
    }

    case "video_generate": {
      const promptSource = config.prompt_source as string | undefined;
      const imageSource = config.image_source as string | undefined;

      const finalPrompt = promptSource
        ? (context[promptSource] as string) || resolvedPrompt
        : resolvedPrompt || context.effect_concept;

      const finalImage = imageSource
        ? (context[imageSource] as string) || context.user_image
        : context.user_image;

      const rawAspectRatio = (context.target_aspect_ratio as string)
        || (config.aspect_ratio as string)
        || undefined;

      const videoParams = applyVideoGlobals(globals, {
        duration: config.duration as number | undefined,
        resolution: config.resolution as string | undefined,
        aspectRatio: rawAspectRatio,
        model: config.model as string | undefined,
      });

      const output = await executeGrokVideo(
        {
          imageUrl: finalImage,
          prompt: finalPrompt,
          model: videoParams.model,
          duration: videoParams.duration,
          aspectRatio: videoParams.aspectRatio,
          resolution: videoParams.resolution,
        },
        logger,
      );
      return {
        result: { request_id: output.requestId },
        providerRequestId: output.requestId,
      };
    }

    default:
      throw new Error(`Unknown step type: ${step.step_type}`);
  }
}

/**
 * Main pipeline orchestrator.
 * Loads steps, creates execution records, runs steps sequentially,
 * and returns the final result (including the video generation request_id).
 */
export async function runPipeline(
  pipelineId: string,
  generationId: string,
  context: PipelineContext,
  supabase: ReturnType<typeof createClient>,
  logger: Logger,
): Promise<PipelineResult> {
  logger.info("pipeline.start", { metadata: { pipeline_id: pipelineId, generation_id: generationId } });

  const globals = await loadGenerationGlobals(supabase, logger);

  const { data: steps, error: stepsError } = await supabase
    .from("pipeline_steps")
    .select("*")
    .eq("pipeline_id", pipelineId)
    .eq("is_active", true)
    .order("step_order", { ascending: true });

  if (stepsError || !steps?.length) {
    throw new Error(`Failed to load pipeline steps: ${stepsError?.message || "no steps found"}`);
  }

  logger.info("pipeline.steps_loaded", { metadata: { step_count: steps.length } });

  // Pre-flight: warn about input mappings that reference context keys not produced by earlier steps
  const producedKeys = new Set(["user_image", "user_prompt", "effect_id", "effect_name", "effect_concept", "secondary_image", "target_aspect_ratio", "effect_concept_resolved"]);
  for (const s of (steps as PipelineStep[])) {
    for (const [, path] of Object.entries(s.input_mapping)) {
      if (typeof path === "string" && path.startsWith("pipeline.")) {
        const key = path.substring(9);
        if (!producedKeys.has(key)) {
          logger.warn("pipeline.preflight.missing_input", {
            metadata: { step_name: s.name, step_order: s.step_order, missing_key: key },
          });
        }
      }
    }
    for (const [contextKey] of Object.entries(s.output_mapping)) {
      producedKeys.add(contextKey);
    }
  }

  const { data: pipelineExecution, error: peError } = await supabase
    .from("pipeline_executions")
    .insert({
      generation_id: generationId,
      pipeline_id: pipelineId,
      status: "running",
      current_step: 0,
      total_steps: steps.length,
      context,
      started_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (peError) throw new Error(`Failed to create pipeline execution: ${peError.message}`);
  const pipelineExecutionId = pipelineExecution.id;

  await supabase
    .from("generations")
    .update({ pipeline_execution_id: pipelineExecutionId })
    .eq("id", generationId);

  let lastProviderRequestId: string | undefined;
  let grokVideoAttempts: number | undefined;

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i] as PipelineStep;
    const stepStartTime = Date.now();

    if (!isStepEnabled(globals, step.step_type)) {
      logger.info("pipeline.step.skipped_by_globals", {
        metadata: { step_order: step.step_order, step_type: step.step_type, step_name: step.name },
      });

      await supabase
        .from("pipeline_step_executions")
        .insert({
          pipeline_execution_id: pipelineExecutionId,
          step_id: step.id,
          step_order: step.step_order,
          status: "skipped",
          input_data: {},
          output_data: { skipped_reason: "disabled_by_generation_globals" },
          started_at: new Date().toISOString(),
          completed_at: new Date().toISOString(),
          duration_ms: 0,
        });

      continue;
    }

    logger.info("pipeline.step.start", {
      metadata: { step_order: step.step_order, step_type: step.step_type, step_name: step.name },
    });

    const { data: stepExec } = await supabase
      .from("pipeline_step_executions")
      .insert({
        pipeline_execution_id: pipelineExecutionId,
        step_id: step.id,
        step_order: step.step_order,
        status: "running",
        input_data: resolveInputs(context, step.input_mapping),
        started_at: new Date().toISOString(),
      })
      .select()
      .single();

    await supabase
      .from("pipeline_executions")
      .update({ current_step: i + 1 })
      .eq("id", pipelineExecutionId);

    try {
      const { result, providerRequestId } = await executeStep(
        step,
        context,
        supabase,
        logger,
        pipelineExecutionId,
        globals,
      );

      storeOutputs(context, step.name, step.output_mapping, result);

      if (providerRequestId) {
        lastProviderRequestId = providerRequestId;
      }

      const durationMs = Date.now() - stepStartTime;

      if (stepExec) {
        await supabase
          .from("pipeline_step_executions")
          .update({
            status: "completed",
            output_data: result,
            provider_request_id: providerRequestId || null,
            completed_at: new Date().toISOString(),
            duration_ms: durationMs,
          })
          .eq("id", stepExec.id);
      }

      logger.info("pipeline.step.completed", {
        metadata: { step_order: step.step_order, step_type: step.step_type, duration_ms: durationMs },
      });
    } catch (error) {
      const durationMs = Date.now() - stepStartTime;
      const errMsg = error instanceof Error ? error.message : String(error);

      if (stepExec) {
        await supabase
          .from("pipeline_step_executions")
          .update({
            status: "failed",
            error_message: errMsg,
            completed_at: new Date().toISOString(),
            duration_ms: durationMs,
          })
          .eq("id", stepExec.id);
      }

      logger.error("pipeline.step.failed", error instanceof Error ? error : new Error(errMsg));

      if (step.is_required) {
        await supabase
          .from("pipeline_executions")
          .update({
            status: "failed",
            error_message: `Step "${step.name}" failed: ${errMsg}`,
            completed_at: new Date().toISOString(),
          })
          .eq("id", pipelineExecutionId);

        throw new Error(`Pipeline step "${step.name}" failed: ${errMsg}`);
      }

      if (stepExec) {
        await supabase
          .from("pipeline_step_executions")
          .update({ status: "skipped" })
          .eq("id", stepExec.id);
      }
    }
  }

  const finalStatus = lastProviderRequestId ? "running" : "completed";
  await supabase
    .from("pipeline_executions")
    .update({
      status: finalStatus,
      context,
      step_results: steps.map((s: PipelineStep) => ({
        step_id: s.id,
        step_type: s.step_type,
        name: s.name,
      })),
      ...(finalStatus === "completed" ? { completed_at: new Date().toISOString() } : {}),
    })
    .eq("id", pipelineExecutionId);

  logger.info("pipeline.orchestration_done", {
    metadata: {
      pipeline_execution_id: pipelineExecutionId,
      status: finalStatus,
      has_video_request: !!lastProviderRequestId,
    },
  });

  return {
    pipelineExecutionId,
    providerRequestId: lastProviderRequestId,
    finalPrompt: (context.video_prompt as string) || (context.enriched_prompt as string) || (context.effect_concept as string),
    finalImageUrl: (context.enhanced_image as string) || context.user_image,
    context,
    grokVideoAttempts,
  };
}
