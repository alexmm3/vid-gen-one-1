import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../_shared/logger.ts";
import { classifyGrokPollHttpFailure } from "../_shared/grok-polling.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface GrokPollResponse {
  status: "pending" | "done" | "expired" | "failed" | "error";
  video?: {
    url: string;
    duration?: number;
    respect_moderation?: boolean;
  };
  model?: string;
  error?: {
    message?: string;
    code?: string;
  };
}

serve(async (req) => {
  const logger = new Logger('check-generation-status');

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const grokApiKey = Deno.env.get("GROK_API_KEY");
    const supabase = createClient(supabaseUrl, supabaseKey);
    let grokTimeoutMinutes = 10;

    const { data: grokCfg } = await supabase
      .from("provider_config")
      .select("config")
      .eq("provider", "grok")
      .maybeSingle();

    if (grokCfg?.config) {
      const cfg = grokCfg.config as Record<string, unknown>;
      if (typeof cfg.poll_timeout_minutes === "number") {
        grokTimeoutMinutes = cfg.poll_timeout_minutes;
      }
    }

    const url = new URL(req.url);
    const generationId = url.searchParams.get("generation_id");

    logger.info('request.received', {
      generation_id: generationId || undefined,
    });

    if (!generationId) {
      logger.warn('validation.failed', { message: 'Missing generation_id' });
      return new Response(
        JSON.stringify({ error: "Missing generation_id parameter", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    logger.setGenerationId(generationId);

    const { data: generation, error } = await supabase
      .from("generations")
      .select("*")
      .eq("id", generationId)
      .single();

    if (error || !generation) {
      logger.warn('generation.not_found', { message: 'Generation not found' });
      return new Response(
        JSON.stringify({ error: "Generation not found", request_id: logger.getRequestId() }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // If it's processing and it's a Grok generation, poll Grok API
    if (generation.status === "processing" && generation.provider === "grok" && generation.provider_request_id && grokApiKey) {
      logger.info('grok.polling', { metadata: { request_id: generation.provider_request_id } });
      
      const pollRes = await fetch(`https://api.x.ai/v1/videos/${generation.provider_request_id}`, {
        headers: { "Authorization": `Bearer ${grokApiKey}` },
      });

      if (pollRes.ok) {
        const grokData: GrokPollResponse = await pollRes.json();
        logger.info('grok.poll_response', { api_response: grokData });

        const currentErrorLog = Array.isArray(generation.error_log) ? generation.error_log : [];
        const newPollCount = (generation.poll_count || 0) + 1;

        if (grokData.status === "done" && grokData.video?.url) {
          let finalVideoUrl = grokData.video.url;

          try {
            logger.info('grok.downloading_video', { metadata: { source_url: grokData.video.url } });
            const videoRes = await fetch(grokData.video.url);
            if (videoRes.ok) {
              const videoBytes = new Uint8Array(await videoRes.arrayBuffer());
              const storagePath = `grok/${generation.id}.mp4`;

              const { error: uploadErr } = await supabase.storage
                .from("generated-videos")
                .upload(storagePath, videoBytes, { contentType: "video/mp4", upsert: true });

              if (uploadErr) {
                logger.warn('grok.storage_upload_failed', { metadata: { error: uploadErr.message } });
              } else {
                const { data: publicUrlData } = supabase.storage
                  .from("generated-videos")
                  .getPublicUrl(storagePath);
                finalVideoUrl = publicUrlData.publicUrl;
                logger.info('grok.stored_to_supabase', { metadata: { storage_url: finalVideoUrl } });
              }
            } else {
              logger.warn('grok.video_download_failed', { metadata: { status: videoRes.status } });
            }
          } catch (storageErr) {
            logger.warn('grok.storage_error', { metadata: { error: storageErr instanceof Error ? storageErr.message : String(storageErr) } });
          }

          const updateData = {
            status: "completed",
            output_video_url: finalVideoUrl,
            api_response: grokData,
            poll_count: newPollCount,
            last_polled_at: new Date().toISOString(),
            error_log: [...currentErrorLog, ...logger.getLogs()],
          };

          await supabase.from("generations").update(updateData).eq("id", generation.id);
          
          if (generation.pipeline_execution_id) {
            await supabase.from("pipeline_executions").update({
              status: "completed",
              completed_at: new Date().toISOString(),
            }).eq("id", generation.pipeline_execution_id);
          }

          Object.assign(generation, updateData);
          logger.info('grok.completed', { metadata: { output_url: finalVideoUrl } });

        } else if (grokData.status === "expired" || grokData.status === "failed" || grokData.status === "error") {
          const errorMessage = grokData.error?.message || `Grok generation ${grokData.status}`;
          const updateData = {
            status: "failed",
            error_message: errorMessage,
            api_response: grokData,
            poll_count: newPollCount,
            last_polled_at: new Date().toISOString(),
            last_error_at: new Date().toISOString(),
            error_log: [...currentErrorLog, ...logger.getLogs()],
          };
          
          await supabase.from("generations").update(updateData).eq("id", generation.id);
          
          await supabase.from("failed_generations").insert({
            original_generation_id: generation.id,
            device_id: generation.device_id,
            failure_reason: errorMessage,
            final_error_message: errorMessage,
            error_log: [...currentErrorLog, ...logger.getLogs()],
            retry_count: generation.retry_count || 0,
          });

          if (generation.pipeline_execution_id) {
            await supabase.from("pipeline_executions").update({
              status: "failed",
              error_message: errorMessage,
              completed_at: new Date().toISOString(),
            }).eq("id", generation.pipeline_execution_id);
          }

          Object.assign(generation, updateData);
        } else {
          // Still processing
          const updateData = {
            api_response: grokData,
            poll_count: newPollCount,
            last_polled_at: new Date().toISOString(),
            error_log: [...currentErrorLog, ...logger.getLogs()],
          };
          await supabase.from("generations").update(updateData).eq("id", generation.id);
          Object.assign(generation, updateData);
        }
      } else {
        const errText = await pollRes.text();
        const ageMinutes = (Date.now() - new Date(generation.created_at).getTime()) / 60000;
        const failureReason = classifyGrokPollHttpFailure({
          statusCode: pollRes.status,
          ageMinutes,
          timeoutMinutes: grokTimeoutMinutes,
        });
        logger.warn('grok.poll_http_error', { metadata: { status: pollRes.status, body: errText.substring(0, 200) } });

        if (failureReason) {
          const currentErrorLog = Array.isArray(generation.error_log) ? generation.error_log : [];
          const updateData = {
            status: "failed",
            error_message: failureReason,
            poll_count: (generation.poll_count || 0) + 1,
            last_polled_at: new Date().toISOString(),
            last_error_at: new Date().toISOString(),
            error_log: [...currentErrorLog, ...logger.getLogs()],
          };

          await supabase.from("generations").update(updateData).eq("id", generation.id);

          await supabase.from("failed_generations").insert({
            original_generation_id: generation.id,
            device_id: generation.device_id,
            failure_reason: failureReason,
            final_error_message: failureReason,
            error_log: [...currentErrorLog, ...logger.getLogs()],
            retry_count: generation.retry_count || 0,
          });

          if (generation.pipeline_execution_id) {
            await supabase.from("pipeline_executions").update({
              status: "failed",
              error_message: failureReason,
              completed_at: new Date().toISOString(),
            }).eq("id", generation.pipeline_execution_id);
          }

          Object.assign(generation, updateData);
        }
      }
    }

    logger.info('generation.retrieved', { metadata: { status: generation.status } });

    return new Response(
      JSON.stringify({ ...generation, request_id: logger.getRequestId() }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    logger.error('request.unhandled_error', error instanceof Error ? error : new Error(String(error)));
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: errorMessage, request_id: logger.getRequestId() }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
