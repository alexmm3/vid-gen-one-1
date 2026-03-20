# Subscription Overhaul Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Weekly+Yearly subscriptions with Weekly+Monthly, enforce strict paywall, add subscription-anchored generation counting, and show quota usage in ProfileView.

**Architecture:** Backend-first approach — Supabase migration and edge functions updated first to ensure backward compatibility with current iOS app. Then iOS client changes. All generation limits enforced server-side with client pre-flight as UX optimization.

**Tech Stack:** Swift/SwiftUI (iOS), TypeScript/Deno (Supabase Edge Functions), PostgreSQL (migrations)

**Spec:** `docs/superpowers/specs/2026-03-20-subscription-overhaul-design.md`

---

## Chunk 1: Backend — Migration & Edge Functions

### Task 1: Supabase Migration — Update subscription_plans and reserve_generation_slot

**Files:**
- Create: `supabase/migrations/00014_subscription_weekly_monthly_overhaul.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- =============================================================================
-- 00014_subscription_weekly_monthly_overhaul.sql
-- =============================================================================
-- Switches from Weekly+Yearly to Weekly+Monthly plans.
-- Switches from rolling-window to subscription-anchored generation counting.
-- Removes price_cents column (prices managed in App Store Connect only).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add unique constraint on name (needed for upserts)
-- ---------------------------------------------------------------------------

ALTER TABLE public.subscription_plans
  ADD CONSTRAINT subscription_plans_name_key UNIQUE (name);

-- ---------------------------------------------------------------------------
-- 2. Deactivate Yearly plan, update Weekly, insert Monthly
-- ---------------------------------------------------------------------------

-- Deactivate yearly (keep row for FK integrity with existing subscribers)
UPDATE public.subscription_plans
   SET is_active = false
 WHERE LOWER(name) = 'yearly';

-- Upsert Weekly plan: 10 generations / 7 days
INSERT INTO public.subscription_plans (name, generation_limit, period_days, is_active)
VALUES ('Weekly', 10, 7, true)
ON CONFLICT (name) DO UPDATE
   SET generation_limit = EXCLUDED.generation_limit,
       period_days      = EXCLUDED.period_days,
       is_active        = EXCLUDED.is_active;

-- Insert Monthly plan: 50 generations / 30 days
INSERT INTO public.subscription_plans (name, generation_limit, period_days, is_active)
VALUES ('Monthly', 50, 30, true)
ON CONFLICT (name) DO UPDATE
   SET generation_limit = EXCLUDED.generation_limit,
       period_days      = EXCLUDED.period_days,
       is_active        = EXCLUDED.is_active;

-- ---------------------------------------------------------------------------
-- 3. Drop price_cents column (prices live in App Store Connect only)
-- ---------------------------------------------------------------------------

ALTER TABLE public.subscription_plans
  DROP COLUMN IF EXISTS price_cents;

-- ---------------------------------------------------------------------------
-- 4. Create NEW reserve_generation_slot with anchored counting
-- ---------------------------------------------------------------------------
-- Key change: replaces p_period_days with p_period_start timestamptz.
-- Counts generations created since p_period_start instead of rolling window.
-- NOTE: PostgreSQL treats different parameter lists as different overloads.
-- The old function (with integer last param) is kept alive during transition.
-- Drop it in a follow-up migration AFTER edge functions are deployed.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reserve_generation_slot(
  p_device_id uuid,
  p_effect_id uuid,
  p_input_image_url text,
  p_secondary_image_url text,
  p_reference_video_url text,
  p_prompt text,
  p_provider text,
  p_request_id text,
  p_input_payload jsonb,
  p_character_orientation text,
  p_copy_audio boolean,
  p_error_log jsonb,
  p_enforce_limit boolean,
  p_generation_limit integer,
  p_period_start timestamptz
)
RETURNS TABLE (
  reserved boolean,
  generation_id uuid,
  status text,
  pipeline_execution_id uuid,
  generations_used integer,
  generations_remaining integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_used integer := 0;
  v_generation public.generations%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_device_id::text, 0));

  IF p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_start IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_used
      FROM public.generations
     WHERE device_id = p_device_id
       AND created_at >= p_period_start;

    IF v_used >= p_generation_limit THEN
      RETURN QUERY
      SELECT
        false,
        NULL::uuid,
        NULL::text,
        NULL::uuid,
        v_used,
        GREATEST(p_generation_limit - v_used, 0);
      RETURN;
    END IF;
  END IF;

  INSERT INTO public.generations (
    device_id, effect_id, input_image_url, secondary_image_url,
    reference_video_url, prompt, status, provider, request_id,
    input_payload, character_orientation, copy_audio, error_log
  )
  VALUES (
    p_device_id, p_effect_id, p_input_image_url, p_secondary_image_url,
    p_reference_video_url, p_prompt, 'pending', p_provider, p_request_id,
    COALESCE(p_input_payload, '{}'::jsonb),
    COALESCE(p_character_orientation, 'image'),
    COALESCE(p_copy_audio, false),
    COALESCE(p_error_log, '[]'::jsonb)
  )
  RETURNING *
    INTO v_generation;

  RETURN QUERY
  SELECT
    true,
    v_generation.id,
    v_generation.status,
    v_generation.pipeline_execution_id,
    CASE
      WHEN p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_start IS NOT NULL THEN v_used
      ELSE NULL
    END,
    CASE
      WHEN p_enforce_limit AND p_generation_limit IS NOT NULL AND p_period_start IS NOT NULL
        THEN GREATEST(p_generation_limit - v_used - 1, 0)
      ELSE -1
    END;
END;
$$;

-- Revoke/grant for new signature
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_generation_slot(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, jsonb, boolean, integer, timestamptz) TO service_role;
```

- [ ] **Step 2: Commit migration**

```bash
git add supabase/migrations/00014_subscription_weekly_monthly_overhaul.sql
git commit -m "feat: add migration for weekly+monthly plans and anchored generation counting"
```

---

### Task 2: Update subscription-check.ts — Anchored counting

**Files:**
- Modify: `supabase/functions/_shared/subscription-check.ts`

- [ ] **Step 1: Update SubscriptionCheckResult interface**

Add `periodStart` and `expiresAt` fields to the interface (line 12-21):

```typescript
export interface SubscriptionCheckResult {
  valid: boolean;
  planId?: string;
  generationLimit?: number;
  periodDays?: number | null;
  generationsUsed?: number;
  generationsRemaining?: number;
  periodStart?: string;   // NEW: ISO date string for billing period start
  expiresAt?: string;     // NEW: ISO date string for subscription expiry
  error?: string;
  errorCode?: "NO_SUBSCRIPTION" | "SUBSCRIPTION_EXPIRED" | "LIMIT_REACHED";
}
```

- [ ] **Step 2: Rewrite countGenerationsInPeriod to use periodStart**

Replace the function (lines 70-82) with:

```typescript
async function countGenerationsInPeriod(
  supabase: SupabaseClient,
  deviceUuid: string,
  periodStart: Date
): Promise<number> {
  const { count } = await supabase
    .from("generations")
    .select("*", { count: "exact", head: true })
    .eq("device_id", deviceUuid)
    .gte("created_at", periodStart.toISOString());
  return count || 0;
}
```

- [ ] **Step 3: Update getGenerationUsage to use periodStart**

Replace the function (lines 84-99) with:

```typescript
export async function getGenerationUsage(
  supabase: SupabaseClient,
  deviceUuid: string,
  generationLimit: number,
  periodDays: number | null,
  expiresAt: string | null
): Promise<{ used: number; remaining: number }> {
  if (periodDays === null || !expiresAt) {
    return { used: 0, remaining: -1 };
  }

  const expiresDate = new Date(expiresAt);
  const periodStart = new Date(expiresDate.getTime() - periodDays * 24 * 60 * 60 * 1000);
  const used = await countGenerationsInPeriod(supabase, deviceUuid, periodStart);
  return {
    used,
    remaining: Math.max(0, generationLimit - used),
  };
}
```

- [ ] **Step 4: Update validateGenerationLimits**

Replace the function (lines 101-146) — add `expiresAt` parameter and compute `periodStart`:

```typescript
async function validateGenerationLimits(
  supabase: SupabaseClient,
  deviceUuid: string,
  planId: string,
  generationLimit: number,
  periodDays: number | null,
  expiresAt: string | null
): Promise<SubscriptionCheckResult> {
  if (periodDays === null || !expiresAt) {
    return {
      valid: true,
      planId,
      generationLimit,
      periodDays: null,
      generationsRemaining: -1,
    };
  }

  const expiresDate = new Date(expiresAt);
  const periodStart = new Date(expiresDate.getTime() - periodDays * 24 * 60 * 60 * 1000);

  const { used, remaining } = await getGenerationUsage(
    supabase,
    deviceUuid,
    generationLimit,
    periodDays,
    expiresAt
  );

  if (remaining <= 0) {
    return {
      valid: false,
      planId,
      generationLimit,
      periodDays,
      generationsUsed: used,
      generationsRemaining: 0,
      periodStart: periodStart.toISOString(),
      expiresAt,
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
    periodStart: periodStart.toISOString(),
    expiresAt,
  };
}
```

- [ ] **Step 5: Update checkDeviceSubscriptionTable**

Modify to pass `expires_at` through (lines 148-180):

```typescript
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
    plan.period_days,
    subscription.expires_at
  );
}
```

- [ ] **Step 6: Update checkAppleReceipts to use anchored counting**

Modify to pass `expires_at` through (lines 182-218):

```typescript
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
    plan.period_days,
    receipt.expires_at
  );
}
```

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/subscription-check.ts
git commit -m "feat: switch subscription-check to anchored generation counting"
```

> **IMPORTANT: Atomic Deploy** — Tasks 2, 3, and 4 modify edge functions that share `_shared/subscription-check.ts`. ALL edge functions must be deployed simultaneously (single `supabase functions deploy`), not one at a time. The shared module signature changes in Task 2 would break callers if deployed independently.

---

### Task 3: Update validate-apple-subscription — Fix started_at and add generations_used

**Files:**
- Modify: `supabase/functions/validate-apple-subscription/index.ts`

- [ ] **Step 1: Fix started_at computation (line 137-139)**

Replace:
```typescript
const startedAt = verifiedTransaction.payload.originalPurchaseDate
  ? new Date(verifiedTransaction.payload.originalPurchaseDate).toISOString()
  : new Date().toISOString();
```

With:
```typescript
// Compute period start from expires_at - period_days
// This ensures counter resets on each renewal
const periodDays = plan.period_days ?? 7;
const startedAt = new Date(
  new Date(effectiveExpiresAt).getTime() - periodDays * 24 * 60 * 60 * 1000
).toISOString();
```

- [ ] **Step 2: Update Mode A response to include generations_used (lines 191-226)**

Replace the `getGenerationUsage` call and response:

```typescript
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
```

- [ ] **Step 3: Update Mode B response to include generations_used (lines 295-323)**

Replace the `getGenerationUsage` call and response:

```typescript
const { used: generationsUsed, remaining: generationsRemaining } = await getGenerationUsage(
  supabase,
  device.id,
  plan.generation_limit,
  plan.period_days,
  subscription.expires_at
);

console.log(`[validate-apple-subscription] Valid subscription. Plan: ${plan.name}, Used: ${generationsUsed}, Remaining: ${generationsRemaining}`);

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
```

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/validate-apple-subscription/index.ts
git commit -m "feat: fix started_at for renewals, add generations_used to response"
```

---

### Task 4: Update generate-video — Pass period_start to RPC

**Files:**
- Modify: `supabase/functions/generate-video/index.ts`

- [ ] **Step 1: Compute periodStart and update RPC call (lines 236-261)**

Replace:
```typescript
const shouldEnforceLimit =
  typeof subscriptionCheck.generationLimit === "number" &&
  typeof subscriptionCheck.periodDays === "number";

const { data: reservation, error: reservationError } = await supabase
  .rpc("reserve_generation_slot", {
    ...
    p_enforce_limit: shouldEnforceLimit,
    p_generation_limit: subscriptionCheck.generationLimit ?? null,
    p_period_days: subscriptionCheck.periodDays ?? null,
  })
```

With:
```typescript
const shouldEnforceLimit =
  typeof subscriptionCheck.generationLimit === "number" &&
  typeof subscriptionCheck.periodStart === "string";

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
    p_generation_limit: subscriptionCheck.generationLimit ?? null,
    p_period_start: subscriptionCheck.periodStart ?? null,
  })
  .single();
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/generate-video/index.ts
git commit -m "feat: pass period_start to reserve_generation_slot RPC"
```

---

## Chunk 2: iOS Client Changes

### Task 5: Update SubscriptionPlan enum — Weekly + Monthly

**Files:**
- Modify: `VideoApp/Services/Subscription/SubscriptionPlan.swift` (full rewrite)
- Modify: `VideoApp/App/BrandConfig.swift:31-36`
- Modify: `VideoApp/App/Secrets.swift:24-25`

- [ ] **Step 1: Update BrandConfig — replace yearlyProductId with monthlyProductId**

In `BrandConfig.swift` lines 31-36, replace:
```swift
static let weeklyProductId = ""
static let yearlyProductId = ""

static var allProductIds: [String] {
    [weeklyProductId, yearlyProductId]
}
```
With:
```swift
static let weeklyProductId = ""   // TODO: Set from App Store Connect
static let monthlyProductId = ""  // TODO: Set from App Store Connect

static var allProductIds: [String] {
    [weeklyProductId, monthlyProductId]
}
```

- [ ] **Step 2: Update Secrets.swift — mirror BrandConfig change**

In `Secrets.swift` lines 24-25, replace:
```swift
static let weeklyProductId = BrandConfig.weeklyProductId
static let yearlyProductId = BrandConfig.yearlyProductId
```
With:
```swift
static let weeklyProductId = BrandConfig.weeklyProductId
static let monthlyProductId = BrandConfig.monthlyProductId
```

- [ ] **Step 3: Rewrite SubscriptionPlan.swift**

Replace entire file:
```swift
//
//  SubscriptionPlan.swift
//
//  Subscription plan types — product IDs come from BrandConfig
//

import Foundation

enum SubscriptionPlan: String, CaseIterable {
    case weekly
    case monthly

    /// App Store Connect product ID — reads from BrandConfig
    var productId: String {
        switch self {
        case .weekly: return BrandConfig.weeklyProductId
        case .monthly: return BrandConfig.monthlyProductId
        }
    }

    /// Reverse lookup: find a plan by its product ID
    static func from(productId: String) -> SubscriptionPlan? {
        allCases.first { $0.productId == productId }
    }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// Default limit description when backend plan info is unavailable
    var defaultLimitDescription: String {
        switch self {
        case .weekly: return "10 videos"
        case .monthly: return "50 videos"
        }
    }

    /// Default generation limit
    var defaultGenerationLimit: Int {
        switch self {
        case .weekly: return 10
        case .monthly: return 50
        }
    }

    /// Default period in days
    var defaultPeriodDays: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add VideoApp/Services/Subscription/SubscriptionPlan.swift VideoApp/App/BrandConfig.swift VideoApp/App/Secrets.swift
git commit -m "feat: replace yearly plan with monthly in SubscriptionPlan and BrandConfig"
```

---

### Task 6: Update SubscriptionPlanService — Remove price_cents sort

**Files:**
- Modify: `VideoApp/Services/Supabase/SubscriptionPlanService.swift:35,90`

- [ ] **Step 1: Fix REST query sort order (line 35)**

Replace:
```swift
let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/subscription_plans?is_active=eq.true&order=price_cents.asc")!
```
With:
```swift
let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/subscription_plans?is_active=eq.true&order=period_days.asc")!
```

- [ ] **Step 2: Remove priceCents from model (line 90)**

Replace:
```swift
struct SubscriptionPlanInfo: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let generationLimit: Int
    let periodDays: Int?
    let appleProductId: String?
    let isActive: Bool
    let priceCents: Int?
    let description: String?
```
With:
```swift
struct SubscriptionPlanInfo: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let generationLimit: Int
    let periodDays: Int?
    let appleProductId: String?
    let isActive: Bool
    let description: String?
```

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Services/Supabase/SubscriptionPlanService.swift
git commit -m "feat: remove price_cents from plan service, sort by period_days"
```

---

### Task 7: Update ValidationResponse and AppState — Add generations_used and expiresAt

**Files:**
- Modify: `VideoApp/Services/Supabase/SubscriptionValidationService.swift`
- Modify: `VideoApp/Models/AppState.swift`
- Modify: `VideoApp/Services/Subscription/SubscriptionManager.swift`

- [ ] **Step 1: Add generationsUsed to ValidationResponse (line 122-138)**

In `SubscriptionInfo`, add `generationsUsed` field:
```swift
struct SubscriptionInfo: Decodable {
    let productId: String?
    let originalTransactionId: String?
    let expiresAt: String?
    let status: Int
    let environment: String
    let plan: PlanInfo?
    let generationsRemaining: Int?
    let generationsUsed: Int?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case expiresAt = "expires_at"
        case status, environment, plan
        case generationsRemaining = "generations_remaining"
        case generationsUsed = "generations_used"
    }
}
```

- [ ] **Step 2: Add generationsUsed and expiresAt to ValidationResult (lines 89-96)**

```swift
struct ValidationResult {
    let isValid: Bool
    let productId: String?
    let expiresAt: String?
    let generationsRemaining: Int?
    let generationsUsed: Int?
    let generationLimit: Int?
    let planName: String?
}
```

- [ ] **Step 3: Update validateSubscription to pass generationsUsed (lines 63-83)**

Update the success return:
```swift
if result.valid {
    print("✅ SubscriptionValidation: Valid subscription")
    return ValidationResult(
        isValid: true,
        productId: result.subscription?.productId,
        expiresAt: result.subscription?.expiresAt,
        generationsRemaining: result.subscription?.generationsRemaining,
        generationsUsed: result.subscription?.generationsUsed,
        generationLimit: result.subscription?.plan?.generationLimit,
        planName: result.subscription?.plan?.planName
    )
} else {
    print("⚠️ SubscriptionValidation: Invalid - \(result.error ?? "unknown")")
    return ValidationResult(
        isValid: false,
        productId: nil,
        expiresAt: nil,
        generationsRemaining: nil,
        generationsUsed: nil,
        generationLimit: nil,
        planName: nil
    )
}
```

- [ ] **Step 4: Add generationsUsed and subscriptionExpiresAt to AppState (after line 59)**

```swift
/// Generations used in current period (from backend)
@Published var generationsUsed: Int? = nil

/// Subscription expiry date — shown as "Resets on" in profile
@Published var subscriptionExpiresAt: Date? = nil
```

- [ ] **Step 5: Update setPremiumStatus in AppState (line 100-104)**

```swift
func setPremiumStatus(
    _ isPremium: Bool,
    generationsRemaining: Int? = nil,
    generationsUsed: Int? = nil,
    generationLimit: Int? = nil,
    expiresAt: String? = nil
) {
    self._isPremiumUser = isPremium
    self.generationsRemaining = generationsRemaining
    self.generationsUsed = generationsUsed
    self.generationLimit = generationLimit
    if let expiresAt = expiresAt {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.subscriptionExpiresAt = formatter.date(from: expiresAt)
            ?? ISO8601DateFormatter().date(from: expiresAt)
    } else if !isPremium {
        self.subscriptionExpiresAt = nil
    }
}
```

- [ ] **Step 6: Update SubscriptionManager.validateWithBackend (lines 296-334)**

Update the success branch to pass new fields:
```swift
if result.isValid {
    if let productId = result.productId {
        currentProductId = productId
    }
    AppState.shared.setPremiumStatus(
        true,
        generationsRemaining: result.generationsRemaining,
        generationsUsed: result.generationsUsed,
        generationLimit: result.generationLimit,
        expiresAt: result.expiresAt
    )
} else {
    currentProductId = nil
    lastTransactionId = nil
    AppState.shared.setPremiumStatus(false)
}
```

Also update the ProfileView paywall callback (line 48) — currently it calls `setPremiumStatus(true)` with no args, which is fine as a temporary state until backend validates.

- [ ] **Step 7: Commit**

```bash
git add VideoApp/Services/Supabase/SubscriptionValidationService.swift VideoApp/Models/AppState.swift VideoApp/Services/Subscription/SubscriptionManager.swift
git commit -m "feat: add generationsUsed and expiresAt to validation flow"
```

---

### Task 8: Update PaywallView — Monthly replaces Yearly

**Files:**
- Modify: `VideoApp/Features/Paywall/Views/PaywallView.swift`
- Modify: `VideoApp/Features/Paywall/ViewModels/PaywallViewModel.swift`

- [ ] **Step 1: Update PaywallViewModel — replace yearly with monthly**

In `PaywallViewModel.swift`:

Line 16 — change default selection:
```swift
@Published var selectedPlan: SubscriptionPlan = .monthly
```

Lines 33-35 — replace yearlyProduct:
```swift
var monthlyProduct: Product? {
    products.first { $0.id == SubscriptionPlan.monthly.productId }
}
```

Line 88 — fix analytics plan detection:
```swift
let plan: AnalyticsEvent.SubscriptionPlan = selectedPlan == .weekly ? .weekly : .monthly
```

- [ ] **Step 2: Update PaywallView — pricing card**

Line 196 — replace yearly reference:
```swift
let product = plan == .weekly ? viewModel.weeklyProduct : viewModel.monthlyProduct
```

Line 215 — fix price suffix:
```swift
Text(product.displayPrice + (plan == .monthly ? "/month" : "/week"))
```

Lines 248-261 — move Best Value badge to monthly with gold styling:
```swift
.overlay(alignment: .topTrailing) {
    if plan == .monthly {
        Text("Best Value")
            .font(.videoCaptionSmall)
            .fontWeight(.semibold)
            .foregroundColor(.videoBlack)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: "C8A96E"))
            .cornerRadius(4)
            .padding(.trailing, 12)
            .offset(y: -10)
    }
}
```

Line 148 — update benefits text to not hardcode yearly plan number:
```swift
benefitRow(
    icon: "video.badge.plus",
    title: viewModel.planInfo(for: .monthly)
        .map { "Up to \($0.generationLimit) Generations" } ?? "Up to 50 Generations",
    subtitle: "Available with the monthly plan"
)
```

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Features/Paywall/Views/PaywallView.swift VideoApp/Features/Paywall/ViewModels/PaywallViewModel.swift
git commit -m "feat: replace yearly with monthly plan in paywall UI"
```

---

### Task 9: Update Analytics — Add monthly case

**Files:**
- Modify: `VideoApp/Services/Analytics/AnalyticsEvent.swift:73-76`
- Modify: `VideoApp/Services/Subscription/SubscriptionManager.swift:145`

- [ ] **Step 1: Add monthly case to AnalyticsEvent.SubscriptionPlan**

Replace:
```swift
enum SubscriptionPlan: String {
    case weekly
    case yearly
}
```
With:
```swift
enum SubscriptionPlan: String {
    case weekly
    case monthly
}
```

- [ ] **Step 2: Fix plan detection in SubscriptionManager (line 145)**

Replace:
```swift
let plan: AnalyticsEvent.SubscriptionPlan = productId.contains("weekly") ? .weekly : .yearly
```
With:
```swift
let plan: AnalyticsEvent.SubscriptionPlan = productId.contains("weekly") ? .weekly : .monthly
```

- [ ] **Step 3: Commit**

```bash
git add VideoApp/Services/Analytics/AnalyticsEvent.swift VideoApp/Services/Subscription/SubscriptionManager.swift
git commit -m "feat: replace yearly with monthly in analytics"
```

---

### Task 10: Update GenerationViewModel — Pre-flight paywall check

**Files:**
- Modify: `VideoApp/Features/Create/ViewModels/GenerationViewModel.swift`

- [ ] **Step 1: Add subscription pre-flight check to all three generate methods**

In `generate()` (line 133), after `guard !isGenerating else { return }`, add:
```swift
guard AppState.shared.isPremiumUser else {
    showPaywall = true
    return
}
```

Same in `generateEffect()` (line 211), after `guard !isGenerating else { return }`.

Same in `generateWithCustomVideo()` (line 273), after `guard !isGenerating else { return }`.

- [ ] **Step 2: Commit**

```bash
git add VideoApp/Features/Create/ViewModels/GenerationViewModel.swift
git commit -m "feat: add pre-flight subscription check before generation"
```

---

### Task 11: Add quota usage display to ProfileView

**Files:**
- Modify: `VideoApp/Features/Profile/Views/ProfileView.swift`

- [ ] **Step 1: Add quota card for subscribers**

After the `upgradeCard` section (line 23-26), add an else branch for premium users showing the quota bar. Replace lines 22-26:

```swift
VStack(spacing: 0) {
    if appState.isPremiumUser, appState.generationLimit != nil {
        quotaCard
            .padding(.top, VideoSpacing.xl)
    } else if !appState.isPremiumUser {
        upgradeCard
            .padding(.top, VideoSpacing.xl)
    }
```

- [ ] **Step 2: Add quotaCard computed property**

Add after the `upgradeCard` section (after line 96):

```swift
// MARK: - Quota Card (Subscribers)

private var quotaCard: some View {
    let limit = appState.generationLimit ?? 0
    let used = appState.generationsUsed ?? 0
    let progress = limit > 0 ? Double(used) / Double(limit) : 0
    let isExhausted = used >= limit && limit > 0

    return VStack(spacing: VideoSpacing.md) {
        // Header
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(accent)

            Text(isExhausted ? "Generations used up" : "\(used) of \(limit) generations")
                .font(.videoSubheadline)
                .foregroundColor(.white)

            Spacer()
        }

        // Progress bar
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 8)

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.8), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(0, geometry.size.width * min(progress, 1.0)),
                        height: 8
                    )
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 8)

        // Reset date
        if let expiresAt = appState.subscriptionExpiresAt {
            HStack {
                Text("Resets on \(expiresAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.videoCaption)
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
            }
        }
    }
    .padding(VideoSpacing.xl)
    .background(
        RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
            .fill(Color.videoSurface)
    )
    .overlay(
        RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
            .stroke(accent.opacity(0.15), lineWidth: 1)
    )
    .padding(.horizontal, VideoSpacing.screenHorizontal)
}
```

- [ ] **Step 3: Update linksSection top padding to handle both states (line 29)**

Replace:
```swift
.padding(.top, appState.isPremiumUser ? VideoSpacing.lg : VideoSpacing.xxxl)
```
With:
```swift
.padding(.top, VideoSpacing.xxxl)
```

- [ ] **Step 4: Commit**

```bash
git add VideoApp/Features/Profile/Views/ProfileView.swift
git commit -m "feat: add quota usage bar to profile for subscribers"
```

---

### Task 12: Remove free tier references from ProfileView

**Files:**
- Modify: `VideoApp/Features/Profile/Views/ProfileView.swift:63`

- [ ] **Step 1: Update upgradeCard subtitle (line 63)**

Replace:
```swift
Text("HD video  ·  40 generations  ·  All effects")
```
With:
```swift
Text("HD video  ·  All effects  ·  Priority processing")
```

- [ ] **Step 2: Commit**

```bash
git add VideoApp/Features/Profile/Views/ProfileView.swift
git commit -m "fix: remove generation count reference from free user card"
```

---

## Summary

**Total tasks:** 12
**Backend tasks (Chunk 1):** 4 (Tasks 1-4) — deploy first
**iOS tasks (Chunk 2):** 8 (Tasks 5-12) — deploy after backend is live

**After implementation, Alex must:**
1. Apply migration to Supabase (Task 1)
2. Deploy updated edge functions (Tasks 2-4)
3. Create Weekly + Monthly products in App Store Connect
4. Insert `apple_product_mappings` rows for new product IDs
5. Fill in product IDs in `BrandConfig.swift` (Tasks 5)
6. Build and submit iOS app
