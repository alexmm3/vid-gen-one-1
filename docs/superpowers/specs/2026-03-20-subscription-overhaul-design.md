# Subscription Overhaul: Weekly + Monthly Plans

## Overview

Replace the current Weekly + Yearly subscription model with Weekly + Monthly. Enforce strict paywall — no free generations. Add quota usage display in ProfileView. Make generation limits configurable via Supabase `subscription_plans` table.

## Plans

| Plan | Generations | Period | Price (App Store) |
|------|------------|--------|-------------------|
| Weekly | 10 | 7 days | $9.99 |
| Monthly | 50 | 30 days | $39.99 |

Prices are managed exclusively in App Store Connect. StoreKit 2 `product.displayPrice` renders them on the client. No price storage in Supabase.

## Exceptions (bypass subscription check)

1. **Admin device** — `ADMIN_DEVICE_ID` env var on backend. Unlimited generations.
2. **Debug simulate premium** — `DEBUG_PREMIUM_DEVICE_PREFIX` env var on backend + `debugSimulatePremium` toggle in iOS (DEBUG builds only).
3. **Kill switch** — `system_config.subscription_check_enabled = false` disables all checks globally.

---

## Backend Changes

### 1. subscription_plans table

- Update/replace existing rows:
  - Weekly: `generation_limit=10`, `period_days=7`, `apple_product_id=TBD`
  - Monthly: `generation_limit=50`, `period_days=30`, `apple_product_id=TBD`
- Deactivate the Yearly plan (`is_active=false`). Do NOT delete — existing `device_subscriptions` rows may reference it via FK. Yearly subscribers retain access until their subscription expires naturally.
- Remove `price_cents` column (prices live in App Store Connect only).
- Update `SubscriptionPlanService.swift` sort order: replace `order=price_cents.asc` with `order=period_days.asc`.

### 2. Subscription-anchored generation counting

**Current:** `WHERE created_at >= (now() - make_interval(days => period_days))` — rolling window from current moment.

**New:** Use Apple's `expiresDate` as the period boundary. The current billing period start is computed as `expires_at - period_days`. This is more reliable than `originalPurchaseDate` (which never changes across renewals).

**Period start formula:**
```
period_start = device_subscriptions.expires_at - make_interval(days => subscription_plans.period_days)
```

This naturally resets the counter when Apple renews (new `expires_at` → new `period_start`).

**reserve_generation_slot RPC changes:**
- Add parameter `p_period_start timestamptz` (passed by the edge function)
- Replace `created_at >= (now() - make_interval(days => p_period_days))` with `created_at >= p_period_start`

**countGenerationsInPeriod in subscription-check.ts changes:**
- Change signature: accept `periodStart: Date` instead of `periodDays: number`
- Query: `WHERE device_id = $1 AND created_at >= $2`
- Caller (`checkDeviceSubscriptionTable`) must query `device_subscriptions.expires_at` and compute period start

**apple_receipts fallback path:**
- The fallback in `checkDeviceSubscription` that checks `apple_receipts` table must also use subscription-anchored counting with the same logic. Use `apple_receipts.expires_at` to compute period start.

**Note on 30-day period vs calendar months:** Apple bills monthly on the same calendar day (e.g., Mar 20 → Apr 20 = 31 days). Using `expires_at` from Apple as the period boundary avoids this mismatch entirely — we always count from `expires_at - period_days` to `expires_at`, and Apple controls when the next period starts.

**Failed generations:** The count query includes all generation statuses (including failed). A failed generation consumes quota. This is intentional — prevents abuse via intentional failures.

### 3. validate-apple-subscription updates

When processing a receipt:
- Use `expiresDate` from Apple's `JWSTransactionDecodedPayload` to set `device_subscriptions.expires_at`
- The `started_at` field should be set to `expiresDate - period_days` (computed from the plan's `period_days`)
- On renewal: Apple sends a new `expiresDate`, which updates both `expires_at` and `started_at` → counter resets automatically

### 4. Strict paywall enforcement

In `subscription-check.ts`: if no valid subscription exists and the device is not admin/debug — return 403 immediately. Remove any fallback logic that allows free generations.

### 5. Response shape updates

`validate-apple-subscription` must return `expires_at` (already exists in current response) and `generations_used`. The iOS client will use `expires_at` as "Resets on" date.

Updated response shape:
```json
{
  "valid": true,
  "subscription": {
    "product_id": "...",
    "original_transaction_id": "...",
    "expires_at": "2026-04-19T00:00:00Z",
    "status": 1,
    "environment": "Production",
    "plan": {
      "plan_id": "uuid",
      "plan_name": "Monthly",
      "generation_limit": 50,
      "period_days": 30
    },
    "generations_remaining": 42,
    "generations_used": 8
  }
}
```

Note: reuse existing `expires_at` field (already decoded by iOS) instead of introducing a new `period_ends_at` field. Add `generations_used` to both backend response and iOS `ValidationResponse` decoder.

---

## iOS Changes

### 1. BrandConfig.swift

- Replace `yearlyProductId` with `monthlyProductId`
- Fill in actual Apple product IDs (TBD from App Store Connect)

### 2. SubscriptionManager

- Update product ID references: weekly + monthly instead of weekly + yearly
- Update `loadContent()` to fetch the two new product IDs

### 3. PaywallView

- Replace Yearly card with Monthly card
- Monthly card gets "Best Value" badge in brand gold color
- Benefits text pulls generation limits from `SubscriptionPlanService` (backend), not hardcoded
- All text in English

### 4. GenerationViewModel — pre-flight paywall

- Before sending generation request to backend, check `AppState.isPremiumUser`
- If false → present paywall immediately, do not call backend
- Backend enforcement remains the authoritative check (defense in depth) — the pre-flight is UX optimization only

### 5. ProfileView — quota usage display

**For subscribers:**
- Replace "Get More from Your Videos" banner with a quota usage block
- Horizontal progress bar in brand gold gradient, fills left-to-right as generations are used
- Text: "{used} of {limit} generations" (e.g., "7 of 10 generations")
- Subtext: "Resets on {date}" using `expires_at` from validation response
- When quota exhausted: bar is full, text shows "Generations used up · Resets on {date}"

**For non-subscribers:**
- Keep existing "Get More from Your Videos" card → taps to paywall

**Data source:**
- `AppState.generationsRemaining`, `AppState.generationLimit` (already exist)
- Add `AppState.generationsUsed: Int?` — computed from validation response
- `AppState.subscriptionExpiresAt: Date?` — from `expires_at` in validation response (may already exist, wire to UI)

### 6. Remove free tier references

- Remove any UI text about "limited generations" or "standard quality" for free users
- Remove any client-side free generation counting logic

### 7. Analytics update

- Add `.monthly` case to `AnalyticsEvent.SubscriptionPlan` enum
- Fix `SubscriptionManager` plan detection logic: currently uses `productId.contains("weekly") ? .weekly : .yearly` — update to handle monthly correctly

### 8. ValidationResponse model update

- Add `generationsUsed: Int?` field to iOS `ValidationResponse` decoder
- Ensure `expiresAt` is properly decoded and stored in AppState for profile display

---

## What stays unchanged

- Apple receipt cryptographic verification (`@apple/app-store-server-library`)
- Atomic `reserve_generation_slot` with PostgreSQL advisory lock (logic changes, mechanism stays)
- RLS policies — all subscription tables service_role only
- Apple sandbox detection for testing
- `apple_product_mappings` table structure
- `apple_receipts` audit trail
- Transaction listener in SubscriptionManager

---

## Deployment order

Order matters for backward compatibility:

1. **Supabase migration** — update `subscription_plans`, modify `reserve_generation_slot` RPC, deactivate yearly plan. The updated RPC must handle both old (rolling) and new (anchored) calls during transition.
2. **Edge functions** — deploy updated `subscription-check.ts`, `validate-apple-subscription`, `generate-video`. Old iOS app continues to work (response is a superset of old shape).
3. **App Store Connect** — create Weekly and Monthly subscription products (manual, by Alex).
4. **apple_product_mappings** — insert new mappings in Supabase for the new product IDs.
5. **iOS app update** — submit new build with all client changes. Only after steps 1-4 are live.

## Existing yearly subscribers

- Yearly plan row stays in DB (`is_active=false`) — FK references preserved
- Yearly subscribers keep access until Apple expiry date
- No new yearly subscriptions possible (product removed from paywall)
- When their subscription expires, they see the new paywall with Weekly/Monthly options
