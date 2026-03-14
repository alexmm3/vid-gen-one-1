import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger, extractOutputUrl } from "../_shared/logger.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/**
 * Generic webhook endpoint for provider callbacks when video processing completes.
 *
 * Expected payload fields:
 * - track_id: our generation UUID (passed when submitting the job)
 * - status: "success" | "failed" | "error" | "processing"
 * - output: array of output URLs (when successful)
 * - message: error message (when failed)
 *
 * Updates the generations table immediately, triggering Supabase Realtime
 * to push the update to the iOS client.
 */
serve(async (req) => {
  const logger = new Logger('generation-webhook');

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      logger.warn('payload.invalid', { message: 'Could not parse JSON body' });
      return new Response(
        JSON.stringify({ error: "Invalid JSON payload" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const trackId = body.track_id as string | undefined;
    logger.info('webhook.received', {
      metadata: {
        track_id: trackId,
        status: body.status as string,
        has_output: !!(body.output),
      }
    });

    if (!trackId) {
      logger.warn('validation.missing_track_id');
      return new Response(
        JSON.stringify({ error: "Missing track_id", request_id: logger.getRequestId() }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: generation, error: fetchError } = await supabase
      .from("generations")
      .select("id, status, error_log, poll_count")
      .eq("id", trackId)
      .single();

    if (fetchError || !generation) {
      logger.warn('validation.generation_not_found', { metadata: { track_id: trackId } });
      return new Response(
        JSON.stringify({ error: "Generation not found", request_id: logger.getRequestId() }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    logger.setGenerationId(generation.id);

    if (generation.status === "completed" || generation.status === "failed") {
      logger.info('webhook.ignored_already_terminal', {
        metadata: { current_status: generation.status }
      });
      return new Response(
        JSON.stringify({
          message: "Generation already in terminal state",
          status: generation.status,
          request_id: logger.getRequestId()
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const currentErrorLog = Array.isArray(generation.error_log) ? generation.error_log : [];
    const outputUrl = extractOutputUrl(body);

    const updateData: Record<string, unknown> = {
      api_response: body,
      last_polled_at: new Date().toISOString(),
      error_log: [...currentErrorLog, ...logger.getLogs()],
    };

    if ((body.status === "success") && outputUrl) {
      updateData.status = "completed";
      updateData.output_video_url = outputUrl;
      logger.info('webhook.completed', { metadata: { output_url: outputUrl } });
    } else if (body.status === "failed" || body.status === "error") {
      updateData.status = "failed";
      updateData.error_message = (body.message as string) || "Generation failed";
      updateData.last_error_at = new Date().toISOString();
      logger.info('webhook.failed', { metadata: { message: body.message } });
    } else {
      logger.info('webhook.still_processing', {
        metadata: { status: body.status, eta: body.eta }
      });
    }

    const { error: updateError } = await supabase
      .from("generations")
      .update(updateData)
      .eq("id", generation.id);

    if (updateError) {
      logger.error('db.update_failed', updateError instanceof Error ? updateError : new Error(String(updateError)));
      return new Response(
        JSON.stringify({ error: "Failed to update generation", request_id: logger.getRequestId() }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    logger.info('webhook.processed', {
      metadata: { final_status: updateData.status || generation.status }
    });

    return new Response(
      JSON.stringify({
        received: true,
        status: updateData.status || generation.status,
        request_id: logger.getRequestId()
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    logger.error('webhook.unhandled_error', error instanceof Error ? error : new Error(String(error)));
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
        request_id: logger.getRequestId()
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
