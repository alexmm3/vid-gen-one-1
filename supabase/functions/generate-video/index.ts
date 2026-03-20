import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../_shared/logger.ts";
import { checkDeviceSubscription } from "../_shared/subscription-check.ts";
import { isValidPublicUrl } from "../_shared/url-utils.ts";
import { startGeneration } from "../_shared/start-generation.ts";
import {
  redactGenerationApiResponseForClient,
  toClientSafeMessage,
} from "../_shared/client-safe-message.ts";
import type { SupabaseClientLike } from "../_shared/supabase-client.ts";

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
    const supabase: SupabaseClientLike = createClient(supabaseUrl, supabaseKey);
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

    let { data: device } = await supabase
      .from("devices")
      .select("id")
      .eq("device_id", device_id)
      .maybeSingle();

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
          JSON.stringify({ error: "Failed to create device record", request_id: logger.getRequestId() }),
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

    const shouldEnforceLimit =
      typeof subscriptionCheck.generationLimit === "number" &&
      typeof subscriptionCheck.periodDays === "number";

    const { data: reservation, error: reservationError } = await supabase
      .rpc("reserve_generation_slot", {
        p_device_id: device.id,
        p_effect_id: effect_id,
        p_input_image_url: input_image_url,
        p_secondary_image_url: secondary_image_url || null,
        p_reference_video_url: null,
        p_prompt: finalPrompt,
        p_provider: "grok",
        p_request_id: logger.getRequestId(),
        p_input_payload: {
          user_prompt: user_prompt ?? null,
          detected_aspect_ratio: detected_aspect_ratio ?? null,
        },
        p_character_orientation: "image",
        p_copy_audio: false,
        p_error_log: [],
        p_enforce_limit: shouldEnforceLimit,
        p_generation_limit: subscriptionCheck.generationLimit ?? null,
        p_period_days: subscriptionCheck.periodDays ?? null,
      })
      .single();

    if (reservationError || !reservation) {
      logger.error(
        "generation.reserve_failed",
        reservationError || new Error("reserve_generation_slot returned no data")
      );
      return new Response(
        JSON.stringify({
          error: "Failed to reserve generation slot",
          request_id: logger.getRequestId(),
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!reservation.reserved || !reservation.generation_id) {
      logger.warn("generation.limit_reached_race", {
        metadata: {
          device_id,
          used: reservation.generations_used,
          remaining: reservation.generations_remaining,
        },
      });
      return new Response(
        JSON.stringify({
          error: `Generation limit reached (${subscriptionCheck.generationLimit} per ${subscriptionCheck.periodDays} days)`,
          error_code: "LIMIT_REACHED",
          limit: subscriptionCheck.generationLimit,
          period_days: subscriptionCheck.periodDays,
          used: reservation.generations_used ?? subscriptionCheck.generationsUsed,
          remaining: reservation.generations_remaining ?? 0,
          request_id: logger.getRequestId(),
        }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const generation = {
      id: reservation.generation_id as string,
      pipeline_execution_id: reservation.pipeline_execution_id as string | null,
    };

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
          error: toClientSafeMessage(startResult.error),
          request_id: logger.getRequestId(),
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const safeApi = startResult.providerRequestId
      ? redactGenerationApiResponseForClient({
        request_id: startResult.providerRequestId,
      })
      : null;

    return new Response(
      JSON.stringify({
        success: true,
        generation_id: generation.id,
        status: startResult.status,
        ...(startResult.pipelineExecutionId ? { pipeline_execution_id: startResult.pipelineExecutionId } : {}),
        ...(safeApi ? { api_response: safeApi } : {}),
        request_id: logger.getRequestId(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    logger.error("request.unhandled_error", error instanceof Error ? error : new Error(String(error)));
    const errorMessage = toClientSafeMessage(
      error instanceof Error ? error.message : "Unknown error",
    );
    return new Response(
      JSON.stringify({ error: errorMessage, request_id: logger.getRequestId() }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
