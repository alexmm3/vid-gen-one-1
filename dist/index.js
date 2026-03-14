// supabase/functions/generate-video/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// supabase/functions/_shared/logger.ts
function generateRequestId() {
  return `req_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}
function createLogEntry(level, event, context, details) {
  return {
    timestamp: (/* @__PURE__ */ new Date()).toISOString(),
    level,
    event,
    request_id: context.request_id,
    generation_id: context.generation_id,
    ...details
  };
}
var Logger = class {
  context;
  logs = [];
  constructor(functionName, requestId) {
    this.context = {
      function_name: functionName,
      request_id: requestId || generateRequestId()
    };
  }
  setGenerationId(id) {
    this.context.generation_id = id;
  }
  getRequestId() {
    return this.context.request_id;
  }
  getLogs() {
    return this.logs;
  }
  log(level, event, details) {
    const entry = createLogEntry(level, event, this.context, details);
    this.logs.push(entry);
    const logMethod = level === "error" ? console.error : level === "warn" ? console.warn : level === "debug" ? console.debug : console.info;
    logMethod(JSON.stringify(entry));
    return entry;
  }
  debug(event, details) {
    return this.log("debug", event, details);
  }
  info(event, details) {
    return this.log("info", event, details);
  }
  warn(event, details) {
    return this.log("warn", event, details);
  }
  error(event, error, details) {
    const errorObj = error instanceof Error ? { message: error.message, stack: error.stack } : { message: error };
    return this.log("error", event, { ...details, error: errorObj });
  }
};
var DEFAULT_RETRY_CONFIG = {
  maxRetries: 3,
  initialDelayMs: 5e3,
  maxDelayMs: 6e4,
  backoffMultiplier: 2
};
async function withRetry(fn, logger, config = {}) {
  const { maxRetries, initialDelayMs, maxDelayMs, backoffMultiplier } = {
    ...DEFAULT_RETRY_CONFIG,
    ...config
  };
  let lastError = null;
  let delay = initialDelayMs;
  for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
    try {
      logger.info("retry.attempt", { retry_attempt: attempt, metadata: { max_retries: maxRetries } });
      const startTime = Date.now();
      const result = await fn();
      const duration = Date.now() - startTime;
      logger.info("retry.success", { retry_attempt: attempt, duration_ms: duration });
      return { result, attempts: attempt };
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      logger.warn("retry.failed", {
        retry_attempt: attempt,
        error: { message: lastError.message },
        metadata: { will_retry: attempt <= maxRetries, next_delay_ms: delay }
      });
      if (attempt <= maxRetries) {
        await new Promise((resolve) => setTimeout(resolve, delay));
        delay = Math.min(delay * backoffMultiplier, maxDelayMs);
      }
    }
  }
  logger.error("retry.exhausted", lastError, { metadata: { total_attempts: maxRetries + 1 } });
  return { error: lastError, attempts: maxRetries + 1 };
}

// supabase/functions/_shared/subscription-check.ts
function getAdminDeviceId() {
  return Deno.env.get("ADMIN_DEVICE_ID") || null;
}
async function isSubscriptionCheckEnabled(supabase) {
  const { data } = await supabase.from("system_config").select("value").eq("key", "subscription_check_enabled").maybeSingle();
  if (!data) return true;
  return data.value === true || data.value === "true";
}
async function countGenerationsInPeriod(supabase, deviceUuid, periodDays) {
  const periodStart = new Date(Date.now() - periodDays * 24 * 60 * 60 * 1e3);
  const { count } = await supabase.from("generations").select("*", { count: "exact", head: true }).eq("device_id", deviceUuid).gte("created_at", periodStart.toISOString());
  return count || 0;
}
async function validateGenerationLimits(supabase, deviceUuid, planId, generationLimit, periodDays) {
  if (periodDays === null) {
    return {
      valid: true,
      planId,
      generationLimit,
      periodDays: null,
      generationsRemaining: -1
    };
  }
  const used = await countGenerationsInPeriod(supabase, deviceUuid, periodDays);
  const remaining = Math.max(0, generationLimit - used);
  if (remaining <= 0) {
    return {
      valid: false,
      planId,
      generationLimit,
      periodDays,
      generationsUsed: used,
      generationsRemaining: 0,
      error: `Generation limit reached (${generationLimit} per ${periodDays} days)`,
      errorCode: "LIMIT_REACHED"
    };
  }
  return {
    valid: true,
    planId,
    generationLimit,
    periodDays,
    generationsUsed: used,
    generationsRemaining: remaining
  };
}
async function checkDeviceSubscriptionTable(supabase, deviceUuid) {
  const { data: subscription } = await supabase.from("device_subscriptions").select("plan_id, expires_at, subscription_plans(generation_limit, period_days)").eq("device_id", deviceUuid).maybeSingle();
  if (!subscription) return null;
  const plan = subscription.subscription_plans;
  if (subscription.expires_at && new Date(subscription.expires_at) < /* @__PURE__ */ new Date()) {
    return {
      valid: false,
      error: "Subscription expired. Please renew to continue.",
      errorCode: "SUBSCRIPTION_EXPIRED"
    };
  }
  return validateGenerationLimits(
    supabase,
    deviceUuid,
    subscription.plan_id,
    plan.generation_limit,
    plan.period_days
  );
}
async function checkAppleReceipts(supabase, deviceUuid) {
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const { data: receipt } = await supabase.from("apple_receipts").select("id, product_id, expires_at").eq("device_id", deviceUuid).gt("expires_at", now).order("expires_at", { ascending: false }).limit(1).maybeSingle();
  if (!receipt) return null;
  const { data: productMapping } = await supabase.from("apple_product_mappings").select("plan_id, subscription_plans(generation_limit, period_days)").eq("apple_product_id", receipt.product_id).maybeSingle();
  if (!productMapping) return null;
  const plan = productMapping.subscription_plans;
  return validateGenerationLimits(
    supabase,
    deviceUuid,
    productMapping.plan_id,
    plan.generation_limit,
    plan.period_days
  );
}
async function checkDeviceSubscription(supabase, deviceUuid, deviceId) {
  const adminDeviceId = getAdminDeviceId();
  if (adminDeviceId && deviceId === adminDeviceId) {
    return { valid: true, generationsRemaining: -1 };
  }
  const checkEnabled = await isSubscriptionCheckEnabled(supabase);
  if (!checkEnabled) {
    return { valid: true, generationsRemaining: -1 };
  }
  const subscriptionResult = await checkDeviceSubscriptionTable(supabase, deviceUuid);
  if (subscriptionResult) {
    return subscriptionResult;
  }
  const receiptResult = await checkAppleReceipts(supabase, deviceUuid);
  if (receiptResult) {
    return receiptResult;
  }
  return {
    valid: false,
    error: "No active subscription. Please subscribe to continue.",
    errorCode: "NO_SUBSCRIPTION"
  };
}

// supabase/functions/_shared/url-utils.ts
function isValidPublicUrl(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

// supabase/functions/_shared/providers/gemini-image.ts
async function fetchImageAsBase64(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch image: HTTP ${res.status}`);
  const buffer = await res.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  const mimeType = res.headers.get("content-type") || "image/jpeg";
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return { base64: btoa(binary), mimeType };
}
async function executeGeminiImage(input, supabase, logger, executionId) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");
  const model = input.model || "gemini-3.1-flash-lite-preview";
  logger.info("gemini.image.start", {
    metadata: { model, prompt_length: input.prompt.length, target_aspect_ratio: input.targetAspectRatio }
  });
  const { base64, mimeType } = await fetchImageAsBase64(input.imageUrl);
  logger.info("gemini.image.fetched_source", { metadata: { mime: mimeType } });
  const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const generationConfig = {
    responseModalities: ["IMAGE", "TEXT"],
    temperature: 0.4
  };
  if (input.targetAspectRatio) {
    generationConfig.imageConfig = { aspectRatio: input.targetAspectRatio };
  }
  const body = {
    contents: [
      {
        parts: [
          { text: input.prompt },
          { inline_data: { mime_type: mimeType, data: base64 } }
        ]
      }
    ],
    generationConfig
  };
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini API ${res.status}: ${errText}`);
  }
  const data = await res.json();
  logger.info("gemini.image.response_received");
  const candidates = data.candidates;
  if (!candidates?.length) throw new Error("Gemini returned no candidates");
  let resultBase64 = null;
  let resultMime = "image/png";
  for (const part of candidates[0].content?.parts || []) {
    if (part.inline_data) {
      resultBase64 = part.inline_data.data;
      resultMime = part.inline_data.mime_type || "image/png";
      break;
    }
  }
  if (!resultBase64) throw new Error("Gemini response contained no image data");
  const ext = resultMime.includes("png") ? "png" : "jpg";
  const storagePath = `pipeline/${executionId}/enhanced.${ext}`;
  let binary = "";
  const decoded = atob(resultBase64);
  for (let i = 0; i < decoded.length; i++) {
    binary += String.fromCharCode(decoded.charCodeAt(i));
  }
  const imageBytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i++) {
    imageBytes[i] = decoded.charCodeAt(i);
  }
  const { error: uploadErr } = await supabase.storage.from("pipeline-artifacts").upload(storagePath, imageBytes, { contentType: resultMime, upsert: true });
  if (uploadErr) throw new Error(`Storage upload failed: ${uploadErr.message}`);
  const { data: publicUrlData } = supabase.storage.from("pipeline-artifacts").getPublicUrl(storagePath);
  const imageUrl = publicUrlData.publicUrl;
  logger.info("gemini.image.completed", { metadata: { storage_path: storagePath, url: imageUrl } });
  return { imageUrl, storagePath };
}

// supabase/functions/_shared/providers/grok-vision.ts
async function executeGrokVision(input, logger) {
  const apiKey = Deno.env.get("GROK_API_KEY");
  if (!apiKey) throw new Error("GROK_API_KEY not configured");
  const model = input.model || "grok-2-vision-1212";
  logger.info("grok.vision.start", { metadata: { model, prompt_length: input.prompt.length } });
  const body = {
    model,
    messages: [
      {
        role: "user",
        content: [
          { type: "image_url", image_url: { url: input.imageUrl } },
          { type: "text", text: input.prompt }
        ]
      }
    ],
    max_tokens: input.maxTokens || 500,
    temperature: 0.3
  };
  const res = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`
    },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Grok Vision API ${res.status}: ${errText}`);
  }
  const data = await res.json();
  const description = data.choices?.[0]?.message?.content?.trim();
  if (!description) throw new Error("Grok Vision returned no content");
  logger.info("grok.vision.completed", { metadata: { description_length: description.length } });
  return { description };
}

// supabase/functions/_shared/providers/grok-text.ts
async function executeGrokText(input, logger) {
  const apiKey = Deno.env.get("GROK_API_KEY");
  if (!apiKey) throw new Error("GROK_API_KEY not configured");
  const model = input.model || "grok-3-mini-fast";
  logger.info("grok.text.start", { metadata: { model, prompt_length: input.prompt.length } });
  const body = {
    model,
    messages: [
      { role: "user", content: input.prompt }
    ],
    max_tokens: input.maxTokens || 1e3,
    temperature: input.temperature ?? 0.7
  };
  const res = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`
    },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Grok Text API ${res.status}: ${errText}`);
  }
  const data = await res.json();
  const text = data.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error("Grok Text returned no content");
  logger.info("grok.text.completed", { metadata: { output_length: text.length } });
  return { text };
}

// supabase/functions/_shared/providers/grok-video.ts
async function executeGrokVideo(input, logger) {
  const apiKey = Deno.env.get("GROK_API_KEY");
  if (!apiKey) throw new Error("GROK_API_KEY not configured");
  const model = input.model || "grok-imagine-video";
  logger.info("grok.video.start", {
    metadata: {
      model,
      duration: input.duration,
      aspect_ratio: input.aspectRatio,
      resolution: input.resolution
    }
  });
  const body = {
    model,
    prompt: input.prompt,
    image: { url: input.imageUrl },
    duration: input.duration || 10,
    aspect_ratio: input.aspectRatio || "9:16",
    resolution: input.resolution || "720p"
  };
  const grokCall = async () => {
    const res = await fetch("https://api.x.ai/v1/videos/generations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`
      },
      body: JSON.stringify(body)
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

// supabase/functions/_shared/pipeline-orchestrator.ts
function resolveContextValue(context, path) {
  const parts = path.split(".");
  if (parts[0] === "pipeline") {
    return context[parts.slice(1).join(".")];
  }
  let current = context;
  for (const part of parts) {
    if (current == null) return void 0;
    current = current[part];
  }
  return current;
}
function resolveInputs(context, inputMapping) {
  const resolved = {};
  for (const [key, path] of Object.entries(inputMapping)) {
    if (typeof path === "string") {
      resolved[key] = resolveContextValue(context, path);
    } else {
      resolved[key] = path;
    }
  }
  return resolved;
}
function storeOutputs(context, stepName, outputMapping, result) {
  if (!context.steps) {
    context.steps = {};
  }
  context.steps[stepName] = { output: result };
  for (const [contextKey, resultPath] of Object.entries(outputMapping)) {
    if (typeof resultPath === "string") {
      let path = resultPath;
      if (path.startsWith("result.")) {
        path = path.substring(7);
      }
      const parts = path.split(".");
      let current = result;
      for (const part of parts) {
        if (current == null) break;
        current = current[part];
      }
      context[contextKey] = current;
    }
  }
}
function substituteTemplate(template, context) {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key) => {
    const value = context[key];
    return value != null ? String(value) : "";
  });
}
async function executeStep(step, context, supabase, logger, pipelineExecutionId) {
  const inputs = resolveInputs(context, step.input_mapping);
  const config = step.config;
  const promptTemplate = config.prompt_template;
  const resolvedPrompt = promptTemplate ? substituteTemplate(promptTemplate, context) : "";
  switch (step.step_type) {
    case "image_enhance": {
      const imageUrl = inputs.image || context.user_image;
      const output = await executeGeminiImage(
        {
          imageUrl,
          prompt: resolvedPrompt,
          model: config.model,
          quality: config.quality,
          targetAspectRatio: config.aspect_ratio || context.target_aspect_ratio || void 0
        },
        supabase,
        logger,
        pipelineExecutionId
      );
      return {
        result: {
          image_url: output.imageUrl,
          storage_path: output.storagePath
        }
      };
    }
    case "image_analyze": {
      const imageUrl = inputs.image || context.user_image;
      const output = await executeGrokVision(
        {
          imageUrl,
          prompt: resolvedPrompt,
          model: config.model,
          maxTokens: config.max_tokens
        },
        logger
      );
      const outputKey = config.output_key || "image_description";
      return { result: { [outputKey]: output.description } };
    }
    case "prompt_enrich": {
      const output = await executeGrokText(
        {
          prompt: resolvedPrompt,
          model: config.model,
          maxTokens: config.max_tokens
        },
        logger
      );
      const outputKey = config.output_key || "enriched_prompt";
      return { result: { [outputKey]: output.text } };
    }
    case "video_generate": {
      const promptSource = config.prompt_source;
      const imageSource = config.image_source;
      const finalPrompt = promptSource ? context[promptSource] || resolvedPrompt : resolvedPrompt || context.effect_concept;
      const finalImage = imageSource ? context[imageSource] || context.user_image : context.user_image;
      const aspectRatio = config.aspect_ratio || context.target_aspect_ratio || void 0;
      const output = await executeGrokVideo(
        {
          imageUrl: finalImage,
          prompt: finalPrompt,
          model: config.model,
          duration: config.duration,
          aspectRatio,
          resolution: config.resolution
        },
        logger
      );
      return {
        result: { request_id: output.requestId },
        providerRequestId: output.requestId
      };
    }
    default:
      throw new Error(`Unknown step type: ${step.step_type}`);
  }
}
async function runPipeline(pipelineId, generationId, context, supabase, logger) {
  logger.info("pipeline.start", { metadata: { pipeline_id: pipelineId, generation_id: generationId } });
  const { data: steps, error: stepsError } = await supabase.from("pipeline_steps").select("*").eq("pipeline_id", pipelineId).eq("is_active", true).order("step_order", { ascending: true });
  if (stepsError || !steps?.length) {
    throw new Error(`Failed to load pipeline steps: ${stepsError?.message || "no steps found"}`);
  }
  logger.info("pipeline.steps_loaded", { metadata: { step_count: steps.length } });
  const { data: pipelineExecution, error: peError } = await supabase.from("pipeline_executions").insert({
    generation_id: generationId,
    pipeline_id: pipelineId,
    status: "running",
    current_step: 0,
    total_steps: steps.length,
    context,
    started_at: (/* @__PURE__ */ new Date()).toISOString()
  }).select().single();
  if (peError) throw new Error(`Failed to create pipeline execution: ${peError.message}`);
  const pipelineExecutionId = pipelineExecution.id;
  await supabase.from("generations").update({ pipeline_execution_id: pipelineExecutionId }).eq("id", generationId);
  let lastProviderRequestId;
  let grokVideoAttempts;
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    const stepStartTime = Date.now();
    logger.info("pipeline.step.start", {
      metadata: { step_order: step.step_order, step_type: step.step_type, step_name: step.name }
    });
    const { data: stepExec } = await supabase.from("pipeline_step_executions").insert({
      pipeline_execution_id: pipelineExecutionId,
      step_id: step.id,
      step_order: step.step_order,
      status: "running",
      input_data: resolveInputs(context, step.input_mapping),
      started_at: (/* @__PURE__ */ new Date()).toISOString()
    }).select().single();
    await supabase.from("pipeline_executions").update({ current_step: i + 1 }).eq("id", pipelineExecutionId);
    try {
      const { result, providerRequestId } = await executeStep(
        step,
        context,
        supabase,
        logger,
        pipelineExecutionId
      );
      storeOutputs(context, step.name, step.output_mapping, result);
      if (providerRequestId) {
        lastProviderRequestId = providerRequestId;
      }
      const durationMs = Date.now() - stepStartTime;
      if (stepExec) {
        await supabase.from("pipeline_step_executions").update({
          status: "completed",
          output_data: result,
          provider_request_id: providerRequestId || null,
          completed_at: (/* @__PURE__ */ new Date()).toISOString(),
          duration_ms: durationMs
        }).eq("id", stepExec.id);
      }
      logger.info("pipeline.step.completed", {
        metadata: { step_order: step.step_order, step_type: step.step_type, duration_ms: durationMs }
      });
    } catch (error) {
      const durationMs = Date.now() - stepStartTime;
      const errMsg = error instanceof Error ? error.message : String(error);
      if (stepExec) {
        await supabase.from("pipeline_step_executions").update({
          status: "failed",
          error_message: errMsg,
          completed_at: (/* @__PURE__ */ new Date()).toISOString(),
          duration_ms: durationMs
        }).eq("id", stepExec.id);
      }
      logger.error("pipeline.step.failed", error instanceof Error ? error : new Error(errMsg));
      if (step.is_required) {
        await supabase.from("pipeline_executions").update({
          status: "failed",
          error_message: `Step "${step.name}" failed: ${errMsg}`,
          completed_at: (/* @__PURE__ */ new Date()).toISOString()
        }).eq("id", pipelineExecutionId);
        throw new Error(`Pipeline step "${step.name}" failed: ${errMsg}`);
      }
      if (stepExec) {
        await supabase.from("pipeline_step_executions").update({ status: "skipped" }).eq("id", stepExec.id);
      }
    }
  }
  const finalStatus = lastProviderRequestId ? "running" : "completed";
  await supabase.from("pipeline_executions").update({
    status: finalStatus,
    context,
    step_results: steps.map((s) => ({
      step_id: s.id,
      step_type: s.step_type,
      name: s.name
    })),
    ...finalStatus === "completed" ? { completed_at: (/* @__PURE__ */ new Date()).toISOString() } : {}
  }).eq("id", pipelineExecutionId);
  logger.info("pipeline.orchestration_done", {
    metadata: {
      pipeline_execution_id: pipelineExecutionId,
      status: finalStatus,
      has_video_request: !!lastProviderRequestId
    }
  });
  return {
    pipelineExecutionId,
    providerRequestId: lastProviderRequestId,
    finalPrompt: context.enriched_prompt || context.effect_concept,
    finalImageUrl: context.enhanced_image || context.user_image,
    context,
    grokVideoAttempts
  };
}

// supabase/functions/generate-video/index.ts
var corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};
async function loadProviderConfig(supabase, provider) {
  const { data } = await supabase.from("provider_config").select("config").eq("provider", provider).maybeSingle();
  return data?.config ?? {};
}
serve(async (req) => {
  const logger = new Logger("generate-video");
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  try {
    logger.info("request.received", { metadata: { method: req.method } });
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = createClient(supabaseUrl, supabaseKey);
    const body = await req.json();
    const { device_id, effect_id, input_image_url, secondary_image_url, user_prompt } = body;
    logger.info("request.parsed", {
      metadata: { device_id, effect_id, has_prompt: !!user_prompt, has_secondary: !!secondary_image_url }
    });
    if (!device_id || !effect_id || !input_image_url) {
      logger.warn("validation.failed.missing_fields", {
        metadata: { device_id: !!device_id, effect_id: !!effect_id, input_image_url: !!input_image_url }
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
    const { data: effect, error: effectError } = await supabase.from("effects").select("*").eq("id", effect_id).single();
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
      if (user_prompt && user_prompt.trim().length > 0) {
        finalPrompt = finalPrompt.replace("{{user_prompt}}", user_prompt.trim());
      } else {
        finalPrompt = finalPrompt.replace("{{user_prompt}}", "").trim();
      }
    }
    let { data: device } = await supabase.from("devices").select("id").eq("device_id", device_id).single();
    if (!device) {
      logger.info("device.creating", { metadata: { device_id } });
      const { data: newDevice, error: insertError } = await supabase.from("devices").insert({ device_id }).select("id").single();
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
        metadata: { error_code: subscriptionCheck.errorCode, error: subscriptionCheck.error, device_id }
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
          request_id: logger.getRequestId()
        }),
        { status: statusCode, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const { data: generation, error: genError } = await supabase.from("generations").insert({
      device_id: device.id,
      effect_id,
      input_image_url,
      secondary_image_url: secondary_image_url || null,
      reference_video_url: null,
      prompt: finalPrompt,
      status: "pending",
      provider: "grok",
      request_id: logger.getRequestId(),
      input_payload: { user_prompt: user_prompt ?? null },
      error_log: []
    }).select().single();
    if (genError) {
      logger.error("generation.create_failed", genError);
      return new Response(
        JSON.stringify({ error: "Failed to create generation record", request_id: logger.getRequestId(), details: genError }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    logger.setGenerationId(generation.id);
    logger.info("generation.created", { metadata: { generation_id: generation.id } });
    const { data: effectPipeline } = await supabase.from("effect_pipelines").select("pipeline_id, config_overrides, pipeline_templates!inner(id, is_active)").eq("effect_id", effect_id).eq("is_active", true).limit(1).maybeSingle();
    if (effectPipeline?.pipeline_id) {
      logger.info("pipeline.routing", { metadata: { pipeline_id: effectPipeline.pipeline_id } });
      try {
        const pipelineContext = {
          user_image: input_image_url,
          user_prompt: user_prompt || "",
          effect_id,
          effect_name: effect.name,
          effect_concept: effect.system_prompt_template,
          effect_concept_resolved: finalPrompt,
          ...secondary_image_url ? { secondary_image: secondary_image_url } : {}
        };
        const pipelineResult = await runPipeline(
          effectPipeline.pipeline_id,
          generation.id,
          pipelineContext,
          supabase,
          logger
        );
        if (pipelineResult.providerRequestId) {
          await supabase.from("generations").update({
            status: "processing",
            prompt: pipelineResult.finalPrompt || finalPrompt,
            provider_request_id: pipelineResult.providerRequestId,
            pipeline_execution_id: pipelineResult.pipelineExecutionId,
            api_response: {
              provider: "grok",
              request_id: pipelineResult.providerRequestId,
              pipeline_execution_id: pipelineResult.pipelineExecutionId
            },
            error_log: logger.getLogs()
          }).eq("id", generation.id);
          return new Response(
            JSON.stringify({
              success: true,
              generation_id: generation.id,
              status: "processing",
              pipeline_execution_id: pipelineResult.pipelineExecutionId,
              api_response: { provider: "grok", request_id: pipelineResult.providerRequestId },
              request_id: logger.getRequestId()
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        } else {
          await supabase.from("generations").update({ status: "completed", error_log: logger.getLogs() }).eq("id", generation.id);
          return new Response(
            JSON.stringify({
              success: true,
              generation_id: generation.id,
              status: "completed",
              pipeline_execution_id: pipelineResult.pipelineExecutionId,
              request_id: logger.getRequestId()
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      } catch (pipelineError) {
        const errMsg = pipelineError instanceof Error ? pipelineError.message : String(pipelineError);
        logger.error("pipeline.failed", pipelineError instanceof Error ? pipelineError : new Error(errMsg));
        await supabase.from("generations").update({
          status: "failed",
          error_message: `Pipeline failed: ${errMsg}`,
          error_log: logger.getLogs()
        }).eq("id", generation.id);
        await supabase.from("failed_generations").insert({
          original_generation_id: generation.id,
          device_id: device.id,
          failure_reason: "pipeline_execution_failed",
          final_error_message: errMsg,
          error_log: logger.getLogs(),
          retry_count: 0
        });
        return new Response(
          JSON.stringify({
            success: false,
            generation_id: generation.id,
            status: "failed",
            error: errMsg,
            request_id: logger.getRequestId()
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }
    const grokApiKey = Deno.env.get("GROK_API_KEY");
    if (!grokApiKey) {
      logger.error("config.missing", "GROK_API_KEY not configured");
      await supabase.from("generations").update({
        status: "failed",
        error_message: "GROK_API_KEY not configured",
        error_log: logger.getLogs()
      }).eq("id", generation.id);
      return new Response(
        JSON.stringify({ error: "Configuration Error: GROK_API_KEY missing", request_id: logger.getRequestId() }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const providerCfg = await loadProviderConfig(supabase, "grok");
    const effectParams = effect.generation_params || {};
    const grokDuration = effectParams.duration ?? providerCfg.default_duration ?? 10;
    const grokResolution = effectParams.resolution ?? providerCfg.default_resolution ?? "720p";
    const grokAspectRatio = effectParams.aspect_ratio ?? providerCfg.default_aspect_ratio ?? "9:16";
    const grokBody = {
      model: effect.ai_model_id || effectParams.model_id || providerCfg.default_model_id || "grok-imagine-video",
      prompt: finalPrompt,
      image: { url: input_image_url },
      duration: grokDuration,
      aspect_ratio: grokAspectRatio,
      resolution: grokResolution
    };
    logger.info("grok.calling", { metadata: { duration: grokDuration, resolution: grokResolution, aspect_ratio: grokAspectRatio } });
    const grokCall = async () => {
      const res = await fetch("https://api.x.ai/v1/videos/generations", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${grokApiKey}`
        },
        body: JSON.stringify(grokBody)
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
      await supabase.from("generations").update({
        status: "failed",
        error_message: retryResult.error.message,
        retry_count: retryResult.attempts,
        last_error_at: (/* @__PURE__ */ new Date()).toISOString(),
        error_log: logger.getLogs()
      }).eq("id", generation.id);
      await supabase.from("failed_generations").insert({
        original_generation_id: generation.id,
        device_id: device.id,
        failure_reason: "grok_api_call_failed",
        final_error_message: retryResult.error.message,
        error_log: logger.getLogs(),
        retry_count: retryResult.attempts
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
      await supabase.from("generations").update({
        status: "failed",
        error_message: errMsg,
        api_response: grokResult,
        error_log: logger.getLogs()
      }).eq("id", generation.id);
      return new Response(
        JSON.stringify({ success: false, generation_id: generation.id, status: "failed", error: errMsg, request_id: logger.getRequestId() }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    await supabase.from("generations").update({
      status: "processing",
      provider_request_id: grokResult.request_id,
      api_response: { provider: "grok", request_id: grokResult.request_id },
      retry_count: retryResult.attempts,
      error_log: logger.getLogs()
    }).eq("id", generation.id);
    logger.info("grok.generation_queued", { metadata: { grok_request_id: grokResult.request_id } });
    return new Response(
      JSON.stringify({
        success: true,
        generation_id: generation.id,
        status: "processing",
        api_response: { provider: "grok", request_id: grokResult.request_id },
        request_id: logger.getRequestId()
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
