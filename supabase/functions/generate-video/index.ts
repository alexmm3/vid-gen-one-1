import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../_shared/logger.ts";
import { checkDeviceSubscription } from "../_shared/subscription-check.ts";
import { isValidPublicUrl } from "../_shared/url-utils.ts";
import { startGeneration } from "../_shared/start-generation.ts";

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

    const startResult = await startGeneration(supabase, logger, {
      generationId: generation.id,
      deviceId: device.id,
      effect,
      inputImageUrl: input_image_url,
      secondaryImageUrl: secondary_image_url || null,
      userPrompt: user_prompt ?? null,
      detectedAspectRatio: detected_aspect_ratio ?? null,
      finalPrompt,
      existingPipelineExecutionId: generation.pipeline_execution_id,
    });

    if (!startResult.success) {
      return new Response(
        JSON.stringify({
          success: false,
          generation_id: generation.id,
          status: "failed",
          error: startResult.error,
          request_id: logger.getRequestId(),
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        generation_id: generation.id,
        status: startResult.status,
        ...(startResult.pipelineExecutionId ? { pipeline_execution_id: startResult.pipelineExecutionId } : {}),
        ...(startResult.providerRequestId
          ? { api_response: { provider: "grok", request_id: startResult.providerRequestId } }
          : {}),
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
