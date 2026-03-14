import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ValidationRequest {
  device_id: string;
  original_transaction_id: string;
  product_id?: string;
  expires_date?: string; // ISO 8601
  use_sandbox?: boolean;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const body: ValidationRequest = await req.json();
    const { device_id, original_transaction_id, product_id, expires_date, use_sandbox = false } = body;

    console.log(`[validate-apple-subscription] device_id=${device_id}, product_id=${product_id || 'N/A'}, expires_date=${expires_date || 'N/A'}, txn=${original_transaction_id}`);

    // Validate required fields
    if (!device_id || !original_transaction_id) {
      return new Response(
        JSON.stringify({ valid: false, error: "Missing required fields: device_id, original_transaction_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Get or create device record ──────────────────────────────────
    let { data: device } = await supabase
      .from("devices")
      .select("id")
      .eq("device_id", device_id)
      .single();

    if (!device) {
      const { data: newDevice, error: insertError } = await supabase
        .from("devices")
        .insert({ device_id })
        .select("id")
        .single();
      if (insertError) {
        console.error("[validate-apple-subscription] Failed to create device:", insertError);
        return new Response(
          JSON.stringify({ valid: false, error: "Failed to create device record" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      device = newDevice;
    }

    // ── MODE A: Register / update subscription (client sent product details) ──
    if (product_id && expires_date) {
      console.log(`[validate-apple-subscription] Registering subscription: product=${product_id}, expires=${expires_date}`);

      // Look up the plan for this Apple product
      const { data: productMapping, error: mappingError } = await supabase
        .from("apple_product_mappings")
        .select("plan_id, subscription_plans(id, name, generation_limit, period_days)")
        .eq("apple_product_id", product_id)
        .single();

      if (mappingError || !productMapping) {
        console.error("[validate-apple-subscription] No plan mapping for product:", product_id, mappingError);
        return new Response(
          JSON.stringify({ valid: false, error: `No plan mapping found for product: ${product_id}` }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const plan = productMapping.subscription_plans as unknown as {
        id: string;
        name: string;
        generation_limit: number;
        period_days: number | null;
      };

      const expiresAt = new Date(expires_date);

      // Upsert device_subscriptions — one row per device
      const { error: upsertError } = await supabase
        .from("device_subscriptions")
        .upsert({
          device_id: device.id,
          plan_id: productMapping.plan_id,
          expires_at: expiresAt.toISOString(),
          started_at: new Date().toISOString(),
          original_transaction_id: original_transaction_id,
        }, {
          onConflict: "device_id",
        });

      if (upsertError) {
        console.error("[validate-apple-subscription] Upsert failed:", upsertError);
        return new Response(
          JSON.stringify({ valid: false, error: "Failed to store subscription" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      console.log(`[validate-apple-subscription] Subscription stored successfully. Plan: ${plan.name}, Expires: ${expiresAt.toISOString()}`);

      // Calculate generations remaining
      let generationsRemaining: number | null = null;
      if (plan.period_days !== null) {
        const periodStart = new Date(Date.now() - (plan.period_days * 24 * 60 * 60 * 1000));
        const { count } = await supabase
          .from("generations")
          .select("*", { count: "exact", head: true })
          .eq("device_id", device.id)
          .gte("created_at", periodStart.toISOString());
        generationsRemaining = Math.max(0, plan.generation_limit - (count || 0));
      } else {
        generationsRemaining = -1; // Unlimited
      }

      return new Response(
        JSON.stringify({
          valid: true,
          subscription: {
            product_id,
            original_transaction_id,
            expires_at: expiresAt.toISOString(),
            status: 1, // Active
            environment: use_sandbox ? "Sandbox" : "Production",
            plan: {
              plan_id: productMapping.plan_id,
              plan_name: plan.name,
              generation_limit: plan.generation_limit,
              period_days: plan.period_days,
            },
            generations_remaining: generationsRemaining,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── MODE B: Check-only (no product details — verify stored subscription) ──
    console.log(`[validate-apple-subscription] Check-only mode for device ${device_id}`);

    const now = new Date().toISOString();
    const { data: subscription } = await supabase
      .from("device_subscriptions")
      .select("plan_id, expires_at, subscription_plans(name, generation_limit, period_days)")
      .eq("device_id", device.id)
      .maybeSingle();

    if (!subscription) {
      console.log(`[validate-apple-subscription] No subscription found for device ${device_id}`);
      return new Response(
        JSON.stringify({ valid: false, error: "No subscription found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Check expiration (null expires_at = never expires, e.g. admin/unlimited)
    if (subscription.expires_at && new Date(subscription.expires_at) < new Date()) {
      console.log(`[validate-apple-subscription] Subscription expired at ${subscription.expires_at}`);
      return new Response(
        JSON.stringify({ valid: false, error: "Subscription expired" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const plan = subscription.subscription_plans as unknown as {
      name: string;
      generation_limit: number;
      period_days: number | null;
    };

    // Calculate generations remaining
    let generationsRemaining: number | null = null;
    if (plan.period_days !== null) {
      const periodStart = new Date(Date.now() - (plan.period_days * 24 * 60 * 60 * 1000));
      const { count } = await supabase
        .from("generations")
        .select("*", { count: "exact", head: true })
        .eq("device_id", device.id)
        .gte("created_at", periodStart.toISOString());
      generationsRemaining = Math.max(0, plan.generation_limit - (count || 0));
    } else {
      generationsRemaining = -1;
    }

    console.log(`[validate-apple-subscription] Valid subscription. Plan: ${plan.name}, Remaining: ${generationsRemaining}`);

    return new Response(
      JSON.stringify({
        valid: true,
        subscription: {
          product_id: null,
          original_transaction_id,
          expires_at: subscription.expires_at,
          status: 1,
          environment: use_sandbox ? "Sandbox" : "Production",
          plan: {
            plan_id: subscription.plan_id,
            plan_name: plan.name,
            generation_limit: plan.generation_limit,
            period_days: plan.period_days,
          },
          generations_remaining: generationsRemaining,
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[validate-apple-subscription] Unhandled error:", error);
    return new Response(
      JSON.stringify({ valid: false, error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
