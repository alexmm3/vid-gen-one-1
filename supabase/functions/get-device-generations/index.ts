import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/**
 * Returns completed generations for a device.
 *
 * The iOS app stores generation history locally in UserDefaults. If that data
 * is lost (reinstall, decode bug, etc.), this endpoint lets the client
 * rebuild its history from the server — the source of truth.
 *
 * GET /functions/v1/get-device-generations?device_id=device_xxx_timestamp
 *
 * Response: { generations: [...], count: N }
 */
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const url = new URL(req.url);
    const deviceId = url.searchParams.get("device_id");

    if (!deviceId) {
      return new Response(
        JSON.stringify({ error: "Missing device_id parameter" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Look up the device by its string ID to get the internal UUID
    const { data: device, error: deviceError } = await supabase
      .from("devices")
      .select("id")
      .eq("device_id", deviceId)
      .single();

    if (deviceError || !device) {
      // Device not found — not an error, just no history yet
      return new Response(
        JSON.stringify({ generations: [], count: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch completed generations for this device, newest first.
    // Include effect_id and effect name (from effects table) for effect-based generations.
    const { data: rows, error: genError } = await supabase
      .from("generations")
      .select("id, status, output_video_url, input_image_url, reference_video_url, effect_id, created_at, effects(name)")
      .eq("device_id", device.id)
      .eq("status", "completed")
      .not("output_video_url", "is", null)
      .order("created_at", { ascending: false })
      .limit(50);

    if (genError) {
      console.error("Query error:", genError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch generations" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Flatten for iOS: effect_name from joined effects table
    const generations = (rows || []).map((row: Record<string, unknown>) => {
      const { effects, ...rest } = row;
      const effect = effects as { name?: string } | null;
      return {
        ...rest,
        effect_id: row.effect_id ?? null,
        effect_name: effect?.name ?? null,
      };
    });

    return new Response(
      JSON.stringify({
        generations,
        count: generations.length,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Unhandled error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
