import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "../_shared/logger.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  const logger = new Logger('check-generation-status');

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

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

    if (error) {
      logger.warn('generation.not_found', { message: 'Generation not found' });
      return new Response(
        JSON.stringify({ error: "Generation not found", request_id: logger.getRequestId() }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
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
