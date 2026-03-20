/**
 * Subscription validation module.
 *
 * Primary check: device_subscriptions table (populated by validate-apple-subscription).
 * Every generation request checks expires_at in real time.
 *
 * Fallback: apple_receipts table (forward compatibility for Apple Server API).
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface SubscriptionCheckResult {
  valid: boolean;
  planId?: string;
  generationLimit?: number;
  periodDays?: number | null;
  generationsUsed?: number;
  generationsRemaining?: number;
  error?: string;
  errorCode?: "NO_SUBSCRIPTION" | "SUBSCRIPTION_EXPIRED" | "LIMIT_REACHED";
}

function getAdminDeviceId(): string | null {
  return Deno.env.get("ADMIN_DEVICE_ID") || null;
}

function getDebugPremiumDevicePrefix(): string | null {
  const raw = Deno.env.get("DEBUG_PREMIUM_DEVICE_PREFIX")?.trim();
  return raw ? raw : null;
}

export interface SubscriptionAccessOverride {
  reason: "admin_device" | "debug_premium_device" | "subscription_checks_disabled";
}

async function isSubscriptionCheckEnabled(supabase: SupabaseClient): Promise<boolean> {
  const { data } = await supabase
    .from("system_config")
    .select("value")
    .eq("key", "subscription_check_enabled")
    .maybeSingle();

  if (!data) return true;

  return data.value === true || data.value === "true";
}

export async function getSubscriptionAccessOverride(
  supabase: SupabaseClient,
  deviceId: string
): Promise<SubscriptionAccessOverride | null> {
  const adminDeviceId = getAdminDeviceId();
  if (adminDeviceId && deviceId === adminDeviceId) {
    return { reason: "admin_device" };
  }

  const debugPremiumPrefix = getDebugPremiumDevicePrefix();
  if (debugPremiumPrefix && deviceId.startsWith(debugPremiumPrefix)) {
    return { reason: "debug_premium_device" };
  }

  const checkEnabled = await isSubscriptionCheckEnabled(supabase);
  if (!checkEnabled) {
    return { reason: "subscription_checks_disabled" };
  }

  return null;
}

async function countGenerationsInPeriod(
  supabase: SupabaseClient,
  deviceUuid: string,
  periodDays: number
): Promise<number> {
  const periodStart = new Date(Date.now() - (periodDays * 24 * 60 * 60 * 1000));
  const { count } = await supabase
    .from("generations")
    .select("*", { count: "exact", head: true })
    .eq("device_id", deviceUuid)
    .gte("created_at", periodStart.toISOString());
  return count || 0;
}

export async function getGenerationUsage(
  supabase: SupabaseClient,
  deviceUuid: string,
  generationLimit: number,
  periodDays: number | null
): Promise<{ used: number; remaining: number }> {
  if (periodDays === null) {
    return { used: 0, remaining: -1 };
  }

  const used = await countGenerationsInPeriod(supabase, deviceUuid, periodDays);
  return {
    used,
    remaining: Math.max(0, generationLimit - used),
  };
}

async function validateGenerationLimits(
  supabase: SupabaseClient,
  deviceUuid: string,
  planId: string,
  generationLimit: number,
  periodDays: number | null
): Promise<SubscriptionCheckResult> {
  if (periodDays === null) {
    return {
      valid: true,
      planId,
      generationLimit,
      periodDays: null,
      generationsRemaining: -1,
    };
  }

  const { used, remaining } = await getGenerationUsage(
    supabase,
    deviceUuid,
    generationLimit,
    periodDays
  );

  if (remaining <= 0) {
    return {
      valid: false,
      planId,
      generationLimit,
      periodDays,
      generationsUsed: used,
      generationsRemaining: 0,
      error: `Generation limit reached (${generationLimit} per ${periodDays} days)`,
      errorCode: "LIMIT_REACHED",
    };
  }

  return {
    valid: true,
    planId,
    generationLimit,
    periodDays,
    generationsUsed: used,
    generationsRemaining: remaining,
  };
}

async function checkDeviceSubscriptionTable(
  supabase: SupabaseClient,
  deviceUuid: string
): Promise<SubscriptionCheckResult | null> {
  const { data: subscription } = await supabase
    .from("device_subscriptions")
    .select("plan_id, expires_at, subscription_plans(generation_limit, period_days)")
    .eq("device_id", deviceUuid)
    .maybeSingle();

  if (!subscription) return null;

  const plan = subscription.subscription_plans as unknown as {
    generation_limit: number;
    period_days: number | null;
  };

  if (subscription.expires_at && new Date(subscription.expires_at) < new Date()) {
    return {
      valid: false,
      error: "Subscription expired. Please renew to continue.",
      errorCode: "SUBSCRIPTION_EXPIRED",
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

async function checkAppleReceipts(
  supabase: SupabaseClient,
  deviceUuid: string
): Promise<SubscriptionCheckResult | null> {
  const now = new Date().toISOString();
  const { data: receipt } = await supabase
    .from("apple_receipts")
    .select("id, product_id, expires_at")
    .eq("device_id", deviceUuid)
    .gt("expires_at", now)
    .order("expires_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!receipt) return null;

  const { data: productMapping } = await supabase
    .from("apple_product_mappings")
    .select("plan_id, subscription_plans(generation_limit, period_days)")
    .eq("apple_product_id", receipt.product_id)
    .maybeSingle();

  if (!productMapping) return null;

  const plan = productMapping.subscription_plans as unknown as {
    generation_limit: number;
    period_days: number | null;
  };

  return validateGenerationLimits(
    supabase,
    deviceUuid,
    productMapping.plan_id,
    plan.generation_limit,
    plan.period_days
  );
}

/**
 * Check if a device has a valid subscription and can generate.
 *
 * Order:
 *  1. Admin bypass (via ADMIN_DEVICE_ID env var)
 *  2. System config kill switch
 *  3. device_subscriptions (primary)
 *  4. apple_receipts (fallback)
 *  5. No subscription found → reject
 */
export async function checkDeviceSubscription(
  supabase: SupabaseClient,
  deviceUuid: string,
  deviceId: string
): Promise<SubscriptionCheckResult> {
  const accessOverride = await getSubscriptionAccessOverride(supabase, deviceId);
  if (accessOverride) {
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
    errorCode: "NO_SUBSCRIPTION",
  };
}
