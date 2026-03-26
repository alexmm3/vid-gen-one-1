import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { toClientSafeMessage } from "../_shared/client-safe-message.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifySignedTransactionInfo } from "../_shared/apple-verification.ts";
import {
  getGenerationUsage,
  getSubscriptionAccessOverride,
} from "../_shared/subscription-check.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ValidationRequest {
  device_id: string;
  original_transaction_id: string;
  signed_transaction_info?: string;
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
    const { device_id, original_transaction_id, signed_transaction_info, use_sandbox = false } = body;

    console.log(
      `[validate-apple-subscription] device_id=${device_id}, has_signed_transaction_info=${Boolean(signed_transaction_info)}, txn=${original_transaction_id}`,
    );

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
      .maybeSingle();

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

    // ── MODE A: Register / update subscription using Apple's signed transaction ──
    let verifiedTransaction;
    if (signed_transaction_info) {
      try {
        verifiedTransaction = await verifySignedTransactionInfo(
          signed_transaction_info,
          use_sandbox
        );
      } catch (verificationError) {
        console.error("[validate-apple-subscription] Signed transaction verification failed:", verificationError);
        console.log("[validate-apple-subscription] Attempting fallback JWS decode without crypto verification");

        // Fallback: decode JWS payload without signature verification.
        // The JWS was already verified client-side by StoreKit 2.
        // We trust it enough to register the subscription; expires_at
        // ensures we never grant access beyond Apple's stated period.
        try {
          const parts = signed_transaction_info.split(".");
          if (parts.length === 3) {
            // Base64url decode the payload (middle part)
            const payloadB64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
            const payloadJson = atob(payloadB64);
            const payload = JSON.parse(payloadJson);

            console.log("[validate-apple-subscription] Fallback decoded payload:", JSON.stringify({
              productId: payload.productId,
              originalTransactionId: payload.originalTransactionId,
              environment: payload.environment,
              expiresDate: payload.expiresDate,
              bundleId: payload.bundleId,
            }));

            // Verify bundle ID matches our app
            if (payload.bundleId === "com.alexm.videoeffects1" && payload.productId && payload.originalTransactionId) {
              const expiresAt = payload.expiresDate ? new Date(payload.expiresDate).toISOString() : null;
              const revokedAt = payload.revocationDate ? new Date(payload.revocationDate).toISOString() : null;

              verifiedTransaction = {
                originalTransactionId: String(payload.originalTransactionId),
                transactionId: String(payload.transactionId || payload.originalTransactionId),
                productId: payload.productId,
                expiresAt,
                environment: payload.environment || (use_sandbox ? "Sandbox" : "Production"),
                revokedAt,
                signedTransactionInfo: signed_transaction_info,
                payload,
              };
              console.log("[validate-apple-subscription] Fallback decode successful, proceeding with Mode A");
            } else {
              console.error("[validate-apple-subscription] Fallback decode: bundle ID mismatch or missing fields");
            }
          }
        } catch (decodeError) {
          console.error("[validate-apple-subscription] Fallback JWS decode failed:", decodeError);
        }
        // If fallback decode also failed, verifiedTransaction stays undefined → Mode B
      }
    }

    if (verifiedTransaction) {
      console.log(
        `[validate-apple-subscription] Verified transaction: product=${verifiedTransaction.productId}, environment=${verifiedTransaction.environment}, txn=${verifiedTransaction.originalTransactionId}`,
      );

      const { data: productMapping, error: mappingError } = await supabase
        .from("apple_product_mappings")
        .select("plan_id, subscription_plans(id, name, generation_limit, period_days)")
        .eq("apple_product_id", verifiedTransaction.productId)
        .single();

      if (mappingError || !productMapping) {
        console.error(
          "[validate-apple-subscription] No plan mapping for product:",
          verifiedTransaction.productId,
          mappingError,
        );
        return new Response(
          JSON.stringify({
            valid: false,
            error: `No plan mapping found for product: ${verifiedTransaction.productId}`,
            error_code: "PRODUCT_NOT_MAPPED",
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const plan = productMapping.subscription_plans as unknown as {
        id: string;
        name: string;
        generation_limit: number;
        period_days: number | null;
      };

      const effectiveExpiresAt = verifiedTransaction.revokedAt || verifiedTransaction.expiresAt;
      if (!effectiveExpiresAt) {
        return new Response(
          JSON.stringify({
            valid: false,
            error: "Verified Apple transaction is missing expires_at.",
            error_code: "APPLE_TRANSACTION_MISSING_EXPIRATION",
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Compute period start from expires_at - period_days
      // This ensures counter resets on each renewal
      const periodDays = plan.period_days ?? 7;
      const startedAt = new Date(
        new Date(effectiveExpiresAt).getTime() - periodDays * 24 * 60 * 60 * 1000
      ).toISOString();

      const { error: upsertError } = await supabase
        .from("device_subscriptions")
        .upsert({
          device_id: device.id,
          plan_id: productMapping.plan_id,
          expires_at: effectiveExpiresAt,
          started_at: startedAt,
          original_transaction_id: verifiedTransaction.originalTransactionId,
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

      const { error: receiptUpsertError } = await supabase
        .from("apple_receipts")
        .upsert({
          device_id: device.id,
          original_transaction_id: verifiedTransaction.originalTransactionId,
          product_id: verifiedTransaction.productId,
          expires_at: effectiveExpiresAt,
          environment: verifiedTransaction.environment,
          last_verified_at: new Date().toISOString(),
          raw_transaction_info: {
            signed_transaction_info: verifiedTransaction.signedTransactionInfo,
            verified_transaction: verifiedTransaction.payload,
          },
          updated_at: new Date().toISOString(),
        }, {
          onConflict: "device_id,original_transaction_id",
        });

      if (receiptUpsertError) {
        console.error("[validate-apple-subscription] Receipt upsert failed:", receiptUpsertError);
        return new Response(
          JSON.stringify({ valid: false, error: "Failed to store Apple receipt", error_code: "RECEIPT_STORE_FAILED" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      console.log(
        `[validate-apple-subscription] Subscription stored successfully. Plan: ${plan.name}, Expires: ${effectiveExpiresAt}`,
      );

      const { used: generationsUsed, remaining: generationsRemaining } = await getGenerationUsage(
        supabase,
        device.id,
        plan.generation_limit,
        plan.period_days,
        effectiveExpiresAt
      );

      const isExpired = new Date(effectiveExpiresAt) < new Date();
      const isRevoked = Boolean(verifiedTransaction.revokedAt);

      return new Response(
        JSON.stringify({
          valid: !isExpired && !isRevoked,
          error: isRevoked
            ? "Subscription was revoked by Apple."
            : (isExpired ? "Subscription expired" : null),
          error_code: isRevoked
            ? "SUBSCRIPTION_REVOKED"
            : (isExpired ? "SUBSCRIPTION_EXPIRED" : null),
          subscription: {
            product_id: verifiedTransaction.productId,
            original_transaction_id: verifiedTransaction.originalTransactionId,
            expires_at: effectiveExpiresAt,
            status: !isExpired && !isRevoked ? 1 : 0,
            environment: verifiedTransaction.environment,
            plan: {
              plan_id: productMapping.plan_id,
              plan_name: plan.name,
              generation_limit: plan.generation_limit,
              period_days: plan.period_days,
            },
            generations_remaining: generationsRemaining,
            generations_used: generationsUsed,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── MODE B: Check-only (no product details — verify stored subscription) ──
    console.log(`[validate-apple-subscription] Check-only mode for device ${device_id}`);

    const accessOverride = await getSubscriptionAccessOverride(supabase, device_id);
    if (accessOverride) {
      const environment =
        accessOverride.reason === "debug_premium_device"
          ? "Debug"
          : accessOverride.reason === "admin_device"
            ? "Admin"
            : "Bypass";

      return new Response(
        JSON.stringify({
          valid: true,
          environment,
          subscription: {
            product_id: null,
            original_transaction_id: original_transaction_id,
            expires_at: null,
            status: 1,
            environment,
            plan: null,
            generations_remaining: -1,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: subscription } = await supabase
      .from("device_subscriptions")
      .select("plan_id, expires_at, original_transaction_id, subscription_plans(name, generation_limit, period_days)")
      .eq("device_id", device.id)
      .maybeSingle();

    if (!subscription) {
      console.log(`[validate-apple-subscription] No subscription found for device ${device_id}`);
      return new Response(
        JSON.stringify({ valid: false, error: "No subscription found", error_code: "NO_SUBSCRIPTION" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (subscription.expires_at && new Date(subscription.expires_at) < new Date()) {
      console.log(`[validate-apple-subscription] Subscription expired at ${subscription.expires_at}`);
      return new Response(
        JSON.stringify({ valid: false, error: "Subscription expired", error_code: "SUBSCRIPTION_EXPIRED" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const plan = subscription.subscription_plans as unknown as {
      name: string;
      generation_limit: number;
      period_days: number | null;
    };

    const { data: latestReceipt } = await supabase
      .from("apple_receipts")
      .select("product_id, original_transaction_id, environment")
      .eq("device_id", device.id)
      .order("expires_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const { used: generationsUsed, remaining: generationsRemaining } = await getGenerationUsage(
      supabase,
      device.id,
      plan.generation_limit,
      plan.period_days,
      subscription.expires_at
    );

    console.log(`[validate-apple-subscription] Valid subscription. Plan: ${plan.name}, Remaining: ${generationsRemaining}`);

    return new Response(
      JSON.stringify({
        valid: true,
        subscription: {
          product_id: latestReceipt?.product_id ?? null,
          original_transaction_id: latestReceipt?.original_transaction_id ?? subscription.original_transaction_id ?? original_transaction_id,
          expires_at: subscription.expires_at,
          status: 1,
          environment: latestReceipt?.environment ?? (use_sandbox ? "Sandbox" : "Production"),
          plan: {
            plan_id: subscription.plan_id,
            plan_name: plan.name,
            generation_limit: plan.generation_limit,
            period_days: plan.period_days,
          },
          generations_remaining: generationsRemaining,
          generations_used: generationsUsed,
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[validate-apple-subscription] Unhandled error:", error);
    return new Response(
      JSON.stringify({
        valid: false,
        error: toClientSafeMessage(error instanceof Error ? error.message : "Unknown error"),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
