import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../_shared/logger.ts";
import { classifyGrokPollHttpFailure } from "../_shared/grok-polling.ts";
import { recoverGenerationStart } from "../_shared/start-generation.ts";
import { toClientSafeMessage } from "../_shared/client-safe-message.ts";
import type { SupabaseClientLike } from "../_shared/supabase-client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface Generation {
  id: string;
  device_id: string;
  status: string;
  request_id: string | null;
  provider: string | null;
  provider_request_id: string | null;
  api_response: Record<string, unknown> | null;
  poll_count: number;
  retry_count: number;
  max_retries: number;
  error_log: unknown[];
  created_at: string;
  pipeline_execution_id: string | null;
}

interface PollResult {
  generation_id: string;
  previous_status: string;
  new_status: string;
  success: boolean;
  error?: string;
}

interface GrokPollResponse {
  status: "pending" | "done" | "expired";
  video?: {
    url: string;
    duration?: number;
    respect_moderation?: boolean;
  };
  model?: string;
}

function getGenerationAgeMinutes(createdAt: string, requestId: string | null): number {
  const requestTimestamp = requestId?.match(/^req_(\d+)_/)?.[1];
  const effectiveStartedAt = requestTimestamp ? Number(requestTimestamp) : new Date(createdAt).getTime();
  return (Date.now() - effectiveStartedAt) / 60000;
}

serve(async (req) => {
  const logger = new Logger('poll-pending-generations');

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const grokApiKey = Deno.env.get("GROK_API_KEY");

    const supabase: SupabaseClientLike = createClient(supabaseUrl, supabaseKey);

    logger.info('cron.started');

    if (!grokApiKey) {
      logger.error('config.missing', 'GROK_API_KEY not configured');
      return new Response(
        JSON.stringify({ error: toClientSafeMessage("GROK_API_KEY not configured") }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let grokTimeoutMinutes = 10;
    const { data: grokCfg } = await supabase
      .from("provider_config")
      .select("config")
      .eq("provider", "grok")
      .maybeSingle();
    if (grokCfg?.config) {
      const cfg = grokCfg.config as Record<string, unknown>;
      if (typeof cfg.poll_timeout_minutes === "number") grokTimeoutMinutes = cfg.poll_timeout_minutes;
    }

    const { data: processingGenerations, error: fetchError } = await supabase
      .from("generations")
      .select("id, device_id, status, request_id, provider, provider_request_id, api_response, poll_count, retry_count, max_retries, error_log, created_at, pipeline_execution_id")
      .eq("status", "processing")
      .order("created_at", { ascending: true })
      .limit(50);

    if (fetchError) {
      logger.error('fetch.failed', fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch generations" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const generations = processingGenerations as Generation[];
    logger.info('generations.found', { metadata: { count: generations.length } });

    if (generations.length === 0) {
      return new Response(
        JSON.stringify({ message: "No pending generations to poll", processed: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const results: PollResult[] = [];

    for (const gen of generations) {
      const genLogger = new Logger('poll-generation', logger.getRequestId());
      genLogger.setGenerationId(gen.id);

      try {
        if (!gen.provider_request_id) {
          if (!gen.request_id) {
            genLogger.warn("generation.recovery_attempt");
            const recoveryResult = await recoverGenerationStart(supabase, genLogger, gen.id);

            if (recoveryResult) {
              results.push({
                generation_id: gen.id,
                previous_status: "processing",
                new_status: recoveryResult.status,
                success: recoveryResult.success,
                error: recoveryResult.error
                  ? toClientSafeMessage(recoveryResult.error)
                  : undefined,
              });
              continue;
            }
          }

          genLogger.warn('grok.no_request_id');
          const ageMinutes = getGenerationAgeMinutes(gen.created_at, gen.request_id);
          if (ageMinutes > grokTimeoutMinutes) {
            await markAsFailed(supabase, gen, `No request_id after ${Math.round(ageMinutes)} min`, genLogger);
            results.push({ generation_id: gen.id, previous_status: "processing", new_status: "failed", success: false, error: "No request_id" });
          }
          continue;
        }

        genLogger.info('grok.polling', { metadata: { request_id: gen.provider_request_id } });

        const pollRes = await fetch(`https://api.x.ai/v1/videos/${gen.provider_request_id}`, {
          headers: { "Authorization": `Bearer ${grokApiKey}` },
        });

        if (!pollRes.ok) {
          const errText = await pollRes.text();
          const ageMinutes = getGenerationAgeMinutes(gen.created_at, gen.request_id);
          const failureReason = classifyGrokPollHttpFailure({
            statusCode: pollRes.status,
            ageMinutes,
            timeoutMinutes: grokTimeoutMinutes,
          });
          genLogger.warn('grok.poll_http_error', { metadata: { status: pollRes.status, body: errText.substring(0, 200) } });

          if (failureReason) {
            await markAsFailed(supabase, gen, failureReason, genLogger);
            results.push({
              generation_id: gen.id,
              previous_status: "processing",
              new_status: "failed",
              success: false,
              error: toClientSafeMessage(failureReason),
            });
            continue;
          }

          results.push({ generation_id: gen.id, previous_status: "processing", new_status: "processing", success: false, error: `HTTP ${pollRes.status}` });
          await supabase.from("generations").update({
            poll_count: gen.poll_count + 1,
            last_polled_at: new Date().toISOString(),
            error_log: [...(Array.isArray(gen.error_log) ? gen.error_log : []), ...genLogger.getLogs()],
          }).eq("id", gen.id);
          continue;
        }

        const grokData: GrokPollResponse = await pollRes.json();
        genLogger.info('grok.poll_response', { api_response: grokData });

        const currentErrorLog = Array.isArray(gen.error_log) ? gen.error_log : [];
        const newPollCount = gen.poll_count + 1;

        if (grokData.status === "done" && grokData.video?.url) {
          let finalVideoUrl = grokData.video.url;

          try {
            genLogger.info('grok.downloading_video', { metadata: { source_url: grokData.video.url } });
            const videoRes = await fetch(grokData.video.url);
            if (videoRes.ok) {
              const videoBytes = new Uint8Array(await videoRes.arrayBuffer());
              const storagePath = `grok/${gen.id}.mp4`;

              const { error: uploadErr } = await supabase.storage
                .from("generated-videos")
                .upload(storagePath, videoBytes, { contentType: "video/mp4", upsert: true });

              if (uploadErr) {
                genLogger.warn('grok.storage_upload_failed', { metadata: { error: uploadErr.message } });
              } else {
                const { data: publicUrlData } = supabase.storage
                  .from("generated-videos")
                  .getPublicUrl(storagePath);
                finalVideoUrl = publicUrlData.publicUrl;
                genLogger.info('grok.stored_to_supabase', { metadata: { storage_url: finalVideoUrl } });
              }
            } else {
              genLogger.warn('grok.video_download_failed', { metadata: { status: videoRes.status } });
            }
          } catch (storageErr) {
            genLogger.warn('grok.storage_error', { metadata: { error: storageErr instanceof Error ? storageErr.message : String(storageErr) } });
          }

          await supabase.from("generations").update({
            status: "completed",
            output_video_url: finalVideoUrl,
            api_response: grokData,
            poll_count: newPollCount,
            last_polled_at: new Date().toISOString(),
            error_log: [...currentErrorLog, ...genLogger.getLogs()],
          }).eq("id", gen.id);

          genLogger.info('grok.completed', { metadata: { output_url: finalVideoUrl } });
          await updatePipelineExecution(supabase, gen, "completed");
          results.push({ generation_id: gen.id, previous_status: "processing", new_status: "completed", success: true });

        } else if (grokData.status === "expired") {
          await markAsFailed(
            supabase,
            gen,
            "This video took too long and expired. Please try again.",
            genLogger,
          );
          results.push({ generation_id: gen.id, previous_status: "processing", new_status: "failed", success: false, error: "expired" });

        } else {
          const ageMinutes = getGenerationAgeMinutes(gen.created_at, gen.request_id);
          if (ageMinutes > grokTimeoutMinutes) {
            genLogger.warn('grok.timeout', { metadata: { age_minutes: ageMinutes } });
            await markAsFailed(supabase, gen, `Generation timed out after ${Math.round(ageMinutes)} minutes`, genLogger);
            results.push({ generation_id: gen.id, previous_status: "processing", new_status: "failed", success: false, error: "Timed out" });
          } else {
            await supabase.from("generations").update({
              api_response: grokData,
              poll_count: newPollCount,
              last_polled_at: new Date().toISOString(),
              error_log: [...currentErrorLog, ...genLogger.getLogs()],
            }).eq("id", gen.id);
            genLogger.info('grok.still_pending', { metadata: { poll_count: newPollCount, age_minutes: Math.round(ageMinutes) } });
            results.push({ generation_id: gen.id, previous_status: "processing", new_status: "processing", success: true });
          }
        }

        await new Promise(resolve => setTimeout(resolve, 300));

      } catch (error) {
        genLogger.error('poll.error', error instanceof Error ? error : new Error(String(error)));
        results.push({
          generation_id: gen.id,
          previous_status: "processing",
          new_status: "processing",
          success: false,
          error: toClientSafeMessage(error instanceof Error ? error.message : "Unknown error"),
        });
      }
    }

    const completed = results.filter(r => r.new_status === "completed").length;
    const failed = results.filter(r => r.new_status === "failed").length;
    const stillProcessing = results.filter(r => r.new_status === "processing").length;

    logger.info('cron.completed', {
      metadata: { total: results.length, completed, failed, still_processing: stillProcessing }
    });

    return new Response(
      JSON.stringify({ message: "Polling completed", processed: results.length, completed, failed, still_processing: stillProcessing, results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    logger.error('cron.unhandled_error', error instanceof Error ? error : new Error(String(error)));
    return new Response(
      JSON.stringify({
        error: toClientSafeMessage(error instanceof Error ? error.message : "Unknown error"),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// deno-lint-ignore no-explicit-any
async function updatePipelineExecution(supabase: any, gen: Generation, status: "completed" | "failed", errorMessage?: string) {
  if (!gen.pipeline_execution_id) return;
  await supabase.from("pipeline_executions").update({
    status,
    ...(errorMessage ? { error_message: errorMessage } : {}),
    completed_at: new Date().toISOString(),
  }).eq("id", gen.pipeline_execution_id);
}

// deno-lint-ignore no-explicit-any
async function markAsFailed(supabase: any, gen: Generation, reason: string, logger: Logger) {
  const currentErrorLog = Array.isArray(gen.error_log) ? gen.error_log : [];
  const clientReason = toClientSafeMessage(reason);

  await supabase.from("generations").update({
    status: "failed",
    error_message: clientReason,
    last_error_at: new Date().toISOString(),
    error_log: [...currentErrorLog, ...logger.getLogs()],
  }).eq("id", gen.id);

  await supabase.from("failed_generations").insert({
    original_generation_id: gen.id,
    device_id: gen.device_id,
    failure_reason: "generation_failed",
    final_error_message: clientReason,
    error_log: [...currentErrorLog, ...logger.getLogs()],
    retry_count: gen.retry_count,
  });

  await updatePipelineExecution(supabase, gen, "failed", clientReason);
  logger.info('generation.moved_to_dlq', { generation_id: gen.id });
}
