import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../_shared/logger.ts";
import { checkDeviceSubscription } from "../_shared/subscription-check.ts";
import { isValidPublicUrl } from "../_shared/url-utils.ts";
import { startGeneration, type StartableEffect } from "../_shared/start-generation.ts";
import {
  redactGenerationApiResponseForClient,
  toClientSafeMessage,
} from "../_shared/client-safe-message.ts";
import { isAuthorizedAdminToken } from "../_shared/admin-auth.ts";
import type { SupabaseClientLike } from "../_shared/supabase-client.ts";

type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-admin-token, x-file-name, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  "Content-Type": "application/json",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function getOptionalText(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function getGenerationParams(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {} as Record<string, Json>;
  }

  return value as Record<string, Json>;
}

function resolveTargetAspectRatio(detectedAspectRatio: unknown, generationParams: Record<string, Json>) {
  const detected = getOptionalText(detectedAspectRatio);
  const configured = getOptionalText(generationParams.aspect_ratio);
  return detected ?? configured ?? "9:16";
}

serve(async (req) => {
  const logger = new Logger("generate-video");

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    logger.info("request.received", { metadata: { method: req.method } });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Missing Supabase configuration", request_id: logger.getRequestId() }, 500);
    }

    const supabase: SupabaseClientLike = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json();
    const {
      device_id,
      effect_id,
      pipeline_id: directPipelineId,
      input_image_url,
      secondary_image_url,
      user_prompt,
      detected_aspect_ratio,
    } = body as {
      device_id?: string;
      effect_id?: string;
      pipeline_id?: string;
      input_image_url?: string;
      secondary_image_url?: string;
      user_prompt?: string;
      detected_aspect_ratio?: string;
    };

    logger.info("request.parsed", {
      metadata: {
        device_id,
        effect_id: effect_id ?? null,
        pipeline_id: directPipelineId ?? null,
        has_prompt: !!user_prompt,
        has_secondary: !!secondary_image_url,
      },
    });

    if (!device_id || !input_image_url) {
      return jsonResponse({ error: "Missing required fields: device_id, input_image_url", request_id: logger.getRequestId() }, 400);
    }

    if (!effect_id && !directPipelineId) {
      return jsonResponse({ error: "Either effect_id or pipeline_id is required", request_id: logger.getRequestId() }, 400);
    }

    if (!isValidPublicUrl(input_image_url)) {
      logger.warn("validation.invalid_primary_url", { metadata: { url_prefix: input_image_url.substring(0, 30) } });
      return jsonResponse({
        error: "input_image_url must be a publicly accessible HTTP(S) URL.",
        error_code: "INVALID_URL",
        request_id: logger.getRequestId(),
      }, 400);
    }

    if (secondary_image_url && !isValidPublicUrl(secondary_image_url)) {
      logger.warn("validation.invalid_secondary_url", { metadata: { url_prefix: secondary_image_url.substring(0, 30) } });
      return jsonResponse({
        error: "secondary_image_url must be a publicly accessible HTTP(S) URL.",
        error_code: "INVALID_URL",
        request_id: logger.getRequestId(),
      }, 400);
    }

    let effect: StartableEffect | null = null;
    if (effect_id) {
      const { data: effectData, error: effectError } = await supabase
        .from("effects")
        .select("*")
        .eq("id", effect_id)
        .single();

      if (effectError || !effectData) {
        logger.error("effect.fetch_failed", effectError || new Error(`Effect not found: ${effect_id}`));
        return jsonResponse({
          error: "Effect not found or invalid",
          error_code: "EFFECT_NOT_FOUND",
          request_id: logger.getRequestId(),
        }, 404);
      }

      if (!effectData.is_active) {
        logger.warn("effect.inactive", { metadata: { effect_id } });
        return jsonResponse({
          error: "This effect is no longer active",
          error_code: "EFFECT_INACTIVE",
          request_id: logger.getRequestId(),
        }, 400);
      }

      if (effectData.requires_secondary_photo && !secondary_image_url) {
        logger.warn("validation.failed.missing_secondary", { metadata: { effect_id } });
        return jsonResponse({
          error: "This effect requires a secondary photo.",
          error_code: "MISSING_SECONDARY_PHOTO",
          request_id: logger.getRequestId(),
        }, 400);
      }

      effect = effectData as StartableEffect;
    }

    if (directPipelineId) {
      const { data: pipelineData, error: pipelineError } = await supabase
        .from("pipeline_templates")
        .select("id")
        .eq("id", directPipelineId)
        .eq("is_active", true)
        .maybeSingle();

      if (pipelineError || !pipelineData) {
        return jsonResponse({ error: "Pipeline not found or inactive", request_id: logger.getRequestId() }, 404);
      }

      const { data: activeSteps, error: stepsError } = await supabase
        .from("pipeline_steps")
        .select("id")
        .eq("pipeline_id", directPipelineId)
        .eq("is_active", true)
        .limit(1);

      if (stepsError) {
        logger.error("pipeline.steps_lookup_failed", stepsError);
        return jsonResponse({ error: `Failed to load pipeline steps: ${stepsError.message}`, request_id: logger.getRequestId() }, 500);
      }

      if (!activeSteps?.length) {
        return jsonResponse({ error: "The selected pipeline has no active steps", request_id: logger.getRequestId() }, 400);
      }
    }

    const generationParams = effect ? getGenerationParams(effect.generation_params) : {};
    const targetAspectRatio = resolveTargetAspectRatio(detected_aspect_ratio, generationParams);

    let finalPrompt = effect?.system_prompt_template || "";
    if (finalPrompt.includes("{{user_prompt}}")) {
      finalPrompt = finalPrompt.replace("{{user_prompt}}", "").trim();
    }

    let { data: device } = await supabase.from("devices").select("id").eq("device_id", device_id).maybeSingle();

    if (!device) {
      logger.info("device.creating", { metadata: { device_id } });
      const { data: newDevice, error: insertError } = await supabase
        .from("devices")
        .insert({ device_id })
        .select("id")
        .single();

      if (insertError || !newDevice) {
        logger.error("device.create_failed", insertError || new Error("Device insert returned no row"));
        return jsonResponse({ error: "Failed to create device record", request_id: logger.getRequestId() }, 500);
      }

      device = newDevice;
      logger.info("device.created", { metadata: { device_uuid: device.id } });
    }

    const adminToken = (body as { adminToken?: string }).adminToken ?? req.headers.get("x-admin-token");
    const adminPassword = Deno.env.get("ADMIN_PASSWORD");
    const isAdmin = adminPassword ? await isAuthorizedAdminToken(adminToken, adminPassword) : false;

    if (isAdmin) {
      logger.info("subscription.admin_bypass", { metadata: { device_id } });
    }

    let shouldEnforceLimit = false;
    let subscriptionCheck: Awaited<ReturnType<typeof checkDeviceSubscription>> | null = null;

    if (!isAdmin) {
      subscriptionCheck = await checkDeviceSubscription(supabase, device.id, device_id);

      if (!subscriptionCheck.valid) {
        logger.warn("subscription.invalid", {
          metadata: { error_code: subscriptionCheck.errorCode, error: subscriptionCheck.error, device_id },
        });
        const statusCode = subscriptionCheck.errorCode === "LIMIT_REACHED" ? 429 : 403;
        return jsonResponse({
          error: subscriptionCheck.error || "Subscription invalid",
          error_code: subscriptionCheck.errorCode,
          limit: subscriptionCheck.generationLimit,
          period_days: subscriptionCheck.periodDays,
          used: subscriptionCheck.generationsUsed,
          remaining: subscriptionCheck.generationsRemaining,
          request_id: logger.getRequestId(),
        }, statusCode);
      }

      shouldEnforceLimit =
        typeof subscriptionCheck.generationLimit === "number" &&
        typeof subscriptionCheck.periodStart === "string";
    }

    const { data: reservation, error: reservationError } = await supabase
      .rpc("reserve_generation_slot", {
        p_device_id: device.id,
        p_effect_id: effect_id ?? null,
        p_input_image_url: input_image_url,
        p_secondary_image_url: secondary_image_url || null,
        p_reference_video_url: null,
        p_prompt: finalPrompt || null,
        p_provider: "grok",
        p_request_id: logger.getRequestId(),
        p_input_payload: {
          user_prompt: getOptionalText(user_prompt),
          detected_aspect_ratio: getOptionalText(detected_aspect_ratio),
          target_aspect_ratio: targetAspectRatio,
        },
        p_character_orientation: "image",
        p_copy_audio: false,
        p_error_log: [],
        p_enforce_limit: shouldEnforceLimit,
        p_generation_limit: subscriptionCheck?.generationLimit ?? null,
        p_period_start: subscriptionCheck?.periodStart ?? null,
      })
      .single();

    if (reservationError || !reservation) {
      logger.error(
        "generation.reserve_failed",
        reservationError || new Error("reserve_generation_slot returned no data"),
      );
      return jsonResponse({ error: "Failed to reserve generation slot", request_id: logger.getRequestId() }, 500);
    }

    if (!reservation.reserved || !reservation.generation_id) {
      logger.warn("generation.limit_reached_race", {
        metadata: {
          device_id,
          used: reservation.generations_used,
          remaining: reservation.generations_remaining,
        },
      });
      return jsonResponse({
        error: `Generation limit reached (${subscriptionCheck?.generationLimit} per ${subscriptionCheck?.periodDays} days)`,
        error_code: "LIMIT_REACHED",
        limit: subscriptionCheck?.generationLimit,
        period_days: subscriptionCheck?.periodDays,
        used: reservation.generations_used ?? subscriptionCheck?.generationsUsed,
        remaining: reservation.generations_remaining ?? 0,
        request_id: logger.getRequestId(),
      }, 429);
    }

    const generation = {
      id: reservation.generation_id as string,
      pipeline_execution_id: reservation.pipeline_execution_id as string | null,
    };

    logger.setGenerationId(generation.id);
    logger.info("generation.created", { metadata: { generation_id: generation.id } });

    const startableEffect: StartableEffect = effect || {
      id: `direct-pipeline:${directPipelineId}`,
      name: "Direct pipeline",
      is_active: true,
      system_prompt_template: finalPrompt,
      generation_params: generationParams,
      ai_model_id: null,
    };

    const startResult = await startGeneration(supabase, logger, {
      generationId: generation.id,
      deviceId: device.id,
      effect: startableEffect,
      inputImageUrl: input_image_url,
      secondaryImageUrl: secondary_image_url || null,
      userPrompt: getOptionalText(user_prompt),
      detectedAspectRatio: getOptionalText(detected_aspect_ratio),
      finalPrompt,
      existingPipelineExecutionId: generation.pipeline_execution_id,
    });

    if (!startResult.success) {
      return jsonResponse({
        success: false,
        generation_id: generation.id,
        status: "failed",
        error: toClientSafeMessage(startResult.error),
        request_id: logger.getRequestId(),
      }, 500);
    }

    const safeApi = redactGenerationApiResponseForClient({
      provider: "grok",
      status: startResult.status,
      id: null,
      ...(startResult.providerRequestId ? { request_id: startResult.providerRequestId } : {}),
      ...(startResult.pipelineExecutionId ? { pipeline_execution_id: startResult.pipelineExecutionId } : {}),
    });

    return jsonResponse({
      success: true,
      generation_id: generation.id,
      status: startResult.status,
      ...(startResult.pipelineExecutionId ? { pipeline_execution_id: startResult.pipelineExecutionId } : {}),
      ...(safeApi ? { api_response: safeApi } : {}),
      request_id: logger.getRequestId(),
    });
  } catch (error) {
    logger.error("request.unhandled_error", error instanceof Error ? error : new Error(String(error)));
    return jsonResponse({
      error: toClientSafeMessage(error instanceof Error ? error.message : "Internal error"),
      request_id: logger.getRequestId(),
    }, 500);
  }
});
