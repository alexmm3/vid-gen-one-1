import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger, withRetry } from "../_shared/logger.ts";
import { checkDeviceSubscription } from "../_shared/subscription-check.ts";
import { isValidPublicUrl } from "../_shared/url-utils.ts";
import { runPipeline, type PipelineContext } from "../_shared/pipeline-orchestrator.ts";
import { loadGenerationGlobals, applyVideoGlobals } from "../_shared/generation-globals.ts";
import { resolveTargetAspectRatio } from "../_shared/aspect-ratio.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface GenerateVideoRequest {
  device_id: string;
  effect_id: string;
  input_image_url: string;
  secondary_image_url?: string;
  user_prompt?: string;
  detected_aspect_ratio?: string;
}

interface ProviderConfig {
  default_duration?: number;
  default_resolution?: string;
  default_aspect_ratio?: string;
  default_model_id?: string;
  poll_interval_seconds?: number;
  poll_timeout_minutes?: number;
}

interface GrokStartResponse {
  request_id?: string;
  error?: { message?: string };
}

async function loadProviderConfig(
  supabase: ReturnType<typeof createClient>,
  provider: string,
): Promise<ProviderConfig> {
  const { data } = await supabase
    .from("provider_config")
    .select("config")
    .eq("provider", provider)
    .maybeSingle();
  return (data?.config as ProviderConfig) ?? {};
}

serve(async (req) => {
  const logger = new Logger("generate-video");

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    logger.info("request.received", { metadata: { method: req.method } });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    const body: GenerateVideoRequest = await req.json();

    const { device_id, effect_id, input_image_url, secondary_image_url, user_prompt, detected_aspect_ratio } = body;

    logger.info("request.parsed", {
      metadata: { device_id, effect_id, has_prompt: !!user_prompt, has_secondary: !!secondary_image_url },
    });

    if (!device_id || !effect_id || !input_image_url) {
      logger.warn("validation.failed.missing_fields", {
        metadata: { device_id: !!device_id, effect_id: !!effect_id, input_image_url: !!input_image_url },
      });
      return new Response(
        JSON.stringify({ error: "Missing required fields: device_id, effect_id, input_image_url", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!isValidPublicUrl(input_image_url)) {
      logger.warn("validation.invalid_primary_url", { metadata: { url_prefix: input_image_url.substring(0, 30) } });
      return new Response(
        JSON.stringify({ error: "input_image_url must be a publicly accessible HTTP(S) URL.", error_code: "INVALID_URL", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (secondary_image_url && !isValidPublicUrl(secondary_image_url)) {
      logger.warn("validation.invalid_secondary_url", { metadata: { url_prefix: secondary_image_url.substring(0, 30) } });
      return new Response(
        JSON.stringify({ error: "secondary_image_url must be a publicly accessible HTTP(S) URL.", error_code: "INVALID_URL", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: effect, error: effectError } = await supabase
      .from("effects")
      .select("*")
      .eq("id", effect_id)
      .single();

    if (effectError || !effect) {
      logger.error("effect.fetch_failed", effectError || new Error(`Effect not found: ${effect_id}`));
      return new Response(
        JSON.stringify({ error: "Effect not found or invalid", error_code: "EFFECT_NOT_FOUND", request_id: logger.getRequestId() }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!effect.is_active) {
      logger.warn("effect.inactive", { metadata: { effect_id } });
      return new Response(
        JSON.stringify({ error: "This effect is no longer active", error_code: "EFFECT_INACTIVE", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (effect.requires_secondary_photo && !secondary_image_url) {
      logger.warn("validation.failed.missing_secondary", { metadata: { effect_id } });
      return new Response(
        JSON.stringify({ error: "This effect requires a secondary photo.", error_code: "MISSING_SECONDARY_PHOTO", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let finalPrompt = effect.system_prompt_template;
    if (finalPrompt.includes("{{user_prompt}}")) {
      // Legacy support: strip the placeholder. We automatically append user instructions later.
      finalPrompt = finalPrompt.replace("{{user_prompt}}", "").trim();
    }

    let { data: device } = await supabase.from("devices").select("id").eq("device_id", device_id).single();

    if (!device) {
      logger.info("device.creating", { metadata: { device_id } });
      const { data: newDevice, error: insertError } = await supabase
        .from("devices")
        .insert({ device_id })
        .select("id")
        .single();

      if (insertError) {
        logger.error("device.create_failed", insertError);
        return new Response(
          JSON.stringify({ error: "Failed to create device record", request_id: logger.getRequestId(), details: insertError }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      device = newDevice;
      logger.info("device.created", { metadata: { device_uuid: device.id } });
    }

    const subscriptionCheck = await checkDeviceSubscription(supabase, device.id, device_id);

    if (!subscriptionCheck.valid) {
      logger.warn("subscription.invalid", {
        metadata: { error_code: subscriptionCheck.errorCode, error: subscriptionCheck.error, device_id },
      });
      const statusCode = subscriptionCheck.errorCode === "LIMIT_REACHED" ? 429 : 403;
      return new Response(
        JSON.stringify({
          error: subscriptionCheck.error,
          error_code: subscriptionCheck.errorCode,
          limit: subscriptionCheck.generationLimit,
          period_days: subscriptionCheck.periodDays,
          used: subscriptionCheck.generationsUsed,
          remaining: subscriptionCheck.generationsRemaining,
          request_id: logger.getRequestId(),
        }),
        { status: statusCode, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: generation, error: genError } = await supabase
      .from("generations")
      .insert({
        device_id: device.id,
        effect_id: effect_id,
        input_image_url: input_image_url,
        secondary_image_url: secondary_image_url || null,
        reference_video_url: null,
        prompt: finalPrompt,
        status: "pending",
        provider: "grok",
        request_id: logger.getRequestId(),
        input_payload: { user_prompt: user_prompt ?? null },
        error_log: [],
      })
      .select()
      .single();

    if (genError) {
      logger.error("generation.create_failed", genError);
      return new Response(
        JSON.stringify({ error: "Failed to create generation record", request_id: logger.getRequestId(), details: genError }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    logger.setGenerationId(generation.id);
    logger.info("generation.created", { metadata: { generation_id: generation.id } });

    // --- Pipeline routing: check if this effect has an active pipeline ---
    const preGlobals = await loadGenerationGlobals(supabase, logger);

    const { data: effectPipeline } = await supabase
      .from("effect_pipelines")
      .select("pipeline_id, config_overrides, pipeline_templates!inner(id, is_active)")
      .eq("effect_id", effect_id)
      .eq("is_active", true)
      .limit(1)
      .maybeSingle();

    if (effectPipeline?.pipeline_id && preGlobals.pipelines_enabled !== false) {
      logger.info("pipeline.routing", { metadata: { pipeline_id: effectPipeline.pipeline_id } });

      try {
        const targetAspectRatio = resolveTargetAspectRatio({
          detectedAspectRatio: detected_aspect_ratio,
          effectDefaultAspectRatio: (effect.generation_params as Record<string, unknown>)?.aspect_ratio as string | undefined,
        });

        const pipelineContext: PipelineContext = {
          user_image: input_image_url,
          user_prompt: user_prompt || "",
          effect_id,
          effect_name: effect.name,
          effect_concept: effect.system_prompt_template,
          effect_concept_resolved: finalPrompt,
          target_aspect_ratio: targetAspectRatio,
          ...(secondary_image_url ? { secondary_image: secondary_image_url } : {}),
        };

        const pipelineResult = await runPipeline(
          effectPipeline.pipeline_id,
          generation.id,
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
            .eq("id", generation.id);

          return new Response(
            JSON.stringify({
              success: true,
              generation_id: generation.id,
              status: "processing",
              pipeline_execution_id: pipelineResult.pipelineExecutionId,
              api_response: { provider: "grok", request_id: pipelineResult.providerRequestId },
              request_id: logger.getRequestId(),
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        } else {
          await supabase
            .from("generations")
            .update({ status: "completed", error_log: logger.getLogs() })
            .eq("id", generation.id);

          return new Response(
            JSON.stringify({
              success: true,
              generation_id: generation.id,
              status: "completed",
              pipeline_execution_id: pipelineResult.pipelineExecutionId,
              request_id: logger.getRequestId(),
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      } catch (pipelineError) {
        const errMsg = pipelineError instanceof Error ? pipelineError.message : String(pipelineError);
        logger.error("pipeline.failed", pipelineError instanceof Error ? pipelineError : new Error(errMsg));

        await supabase
          .from("generations")
          .update({
            status: "failed",
            error_message: `Pipeline failed: ${errMsg}`,
            error_log: logger.getLogs(),
          })
          .eq("id", generation.id);

        await supabase.from("failed_generations").insert({
          original_generation_id: generation.id,
          device_id: device.id,
          failure_reason: "pipeline_execution_failed",
          final_error_message: errMsg,
          error_log: logger.getLogs(),
          retry_count: 0,
        });

        return new Response(
          JSON.stringify({
            success: false,
            generation_id: generation.id,
            status: "failed",
            error: errMsg,
            request_id: logger.getRequestId(),
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // --- Direct-to-Grok flow (no pipeline) ---
    const grokApiKey = Deno.env.get("GROK_API_KEY");
    if (!grokApiKey) {
      logger.error("config.missing", "GROK_API_KEY not configured");
      await supabase
        .from("generations")
        .update({
          status: "failed",
          error_message: "GROK_API_KEY not configured",
          error_log: logger.getLogs(),
        })
        .eq("id", generation.id);
      return new Response(
        JSON.stringify({ error: "Configuration Error: GROK_API_KEY missing", request_id: logger.getRequestId() }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const providerCfg = await loadProviderConfig(supabase, "grok");
    const effectParams = (effect.generation_params || {}) as Record<string, unknown>;
    const globals = await loadGenerationGlobals(supabase, logger);

    const rawDuration = (effectParams.duration as number) ?? providerCfg.default_duration ?? 10;
    const rawResolution = (effectParams.resolution as string) ?? providerCfg.default_resolution ?? "720p";
    const rawAspectRatio = (effectParams.aspect_ratio as string) ?? providerCfg.default_aspect_ratio ?? "9:16";
    const rawModel = effect.ai_model_id || (effectParams.model_id as string) || providerCfg.default_model_id || "grok-imagine-video";

    const videoParams = applyVideoGlobals(globals, {
      duration: rawDuration,
      resolution: rawResolution,
      aspectRatio: rawAspectRatio,
      model: rawModel,
    });

    let grokPrompt = finalPrompt;
    if (user_prompt && user_prompt.trim().length > 0) {
      grokPrompt += `\n\n---
USER'S CUSTOM INSTRUCTIONS:
The user has provided additional specific wishes for this video. You must maintain the overall style and core concept described in the prompt above, but please try your best to incorporate the following user recommendations:
"${user_prompt.trim()}"
---`;
    }

    const grokBody: Record<string, unknown> = {
      model: videoParams.model,
      prompt: grokPrompt,
      image: { url: input_image_url },
      duration: videoParams.duration,
      aspect_ratio: videoParams.aspectRatio,
      resolution: videoParams.resolution,
    };

    logger.info("grok.calling", { metadata: { duration: videoParams.duration, resolution: videoParams.resolution, aspect_ratio: videoParams.aspectRatio, globals_applied: true } });

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
      await supabase
        .from("generations")
        .update({
          status: "failed",
          error_message: retryResult.error.message,
          retry_count: retryResult.attempts,
          last_error_at: new Date().toISOString(),
          error_log: logger.getLogs(),
        })
        .eq("id", generation.id);

      await supabase.from("failed_generations").insert({
        original_generation_id: generation.id,
        device_id: device.id,
        failure_reason: "grok_api_call_failed",
        final_error_message: retryResult.error.message,
        error_log: logger.getLogs(),
        retry_count: retryResult.attempts,
      });

      return new Response(
        JSON.stringify({ success: false, generation_id: generation.id, status: "failed", error: retryResult.error.message, request_id: logger.getRequestId() }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const grokResult = retryResult.result;
    logger.info("grok.response_received", { api_response: grokResult });

    if (!grokResult.request_id) {
      const errMsg = grokResult.error?.message || "Grok did not return a request_id";
      logger.error("grok.no_request_id", errMsg);
      await supabase
        .from("generations")
        .update({
          status: "failed",
          error_message: errMsg,
          api_response: grokResult,
          error_log: logger.getLogs(),
        })
        .eq("id", generation.id);

      return new Response(
        JSON.stringify({ success: false, generation_id: generation.id, status: "failed", error: errMsg, request_id: logger.getRequestId() }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
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
      .eq("id", generation.id);

    logger.info("grok.generation_queued", { metadata: { grok_request_id: grokResult.request_id } });

    return new Response(
      JSON.stringify({
        success: true,
        generation_id: generation.id,
        status: "processing",
        api_response: { provider: "grok", request_id: grokResult.request_id },
        request_id: logger.getRequestId(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    logger.error("request.unhandled_error", error instanceof Error ? error : new Error(String(error)));
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: errorMessage, request_id: logger.getRequestId(), details: error }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
