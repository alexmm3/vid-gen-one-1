# Admin Panel for AI Video Effects App

## Context

I have an iOS app that lets users generate AI videos using "effects." Each effect is a creative template: it has a preview video, a system prompt, and configuration that determines what the user needs to provide (one photo or two). The user picks an effect, uploads their photo(s), optionally writes a short text prompt, and the backend generates an AI video.

All effect data lives in Supabase. I need a web-based admin panel where I can manage these effects: create new ones, edit existing ones, delete them, organize them into categories. I am the only user of this panel.

---

## Authentication

No user accounts, no complex auth. Keep it simple:

There is a secret called `ADMIN_PASSWORD` stored in Supabase Edge Functions Secrets (also accessible as a regular environment variable). On the login screen, show a single password field. If the entered password matches `ADMIN_PASSWORD`, the user is authenticated and has full access to everything. Store the session in the browser (localStorage or cookie) so I don't have to re-enter it on every page load. A logout button should clear the session.

To verify the password, you can either call a small Edge Function that checks it, or compare against a value stored in the `system_config` table (key: `admin_password`). Whichever approach is simpler.

---

## Database Tables

The Supabase project already has some tables. Below I describe which ones the admin panel should work with. Some tables need to be created first (marked as NEW).

### Table: `effects` (NEW — must be created)

This is the main table. Each row is one effect visible to users in the mobile app.

```sql
CREATE TABLE public.effects (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  name                     text        NOT NULL,
  description              text,
  preview_video_url        text,
  thumbnail_url            text,
  category_id              uuid        REFERENCES public.effect_categories(id),
  is_active                boolean     NOT NULL DEFAULT true,
  is_premium               boolean     NOT NULL DEFAULT false,
  sort_order               integer     NOT NULL DEFAULT 0,
  requires_secondary_photo boolean     NOT NULL DEFAULT false,
  system_prompt_template   text        NOT NULL,
  provider                 text        NOT NULL DEFAULT 'kling',
  generation_params        jsonb       NOT NULL DEFAULT '{}',
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT effects_pkey PRIMARY KEY (id)
);

ALTER TABLE public.effects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read effects" ON public.effects FOR SELECT TO public USING (true);
CREATE POLICY "Full access for service role" ON public.effects FOR ALL TO service_role USING (true) WITH CHECK (true);
```

Column descriptions:
- `name` — display name shown to users (e.g. "Romantic Kiss", "Anime Transform")
- `description` — short description shown under the name in the app
- `preview_video_url` — URL to a short looping video that previews what this effect does. Stored in Supabase Storage bucket `reference-videos` or an external URL
- `thumbnail_url` — thumbnail image for the effect card in the catalog
- `category_id` — which category this effect belongs to
- `is_active` — only active effects are shown in the app. This is how I publish/unpublish
- `is_premium` — whether the effect requires a paid subscription
- `sort_order` — controls display order within a category (lower = first)
- `requires_secondary_photo` — if `true`, the app shows a second photo picker. Used for effects involving two people (e.g. two people kissing, hugging, etc.)
- `system_prompt_template` — the AI prompt used to generate the video. Supports a `{{user_prompt}}` placeholder that gets replaced with the user's optional text input. This is the creative core of each effect
- `provider` — which AI video generation API to use. Currently either `"kling"` or `"grok"`. Just a free-text string
- `generation_params` — JSON object with provider-specific parameters like `{"duration": 5, "aspect_ratio": "9:16"}`. The admin panel should show this as an editable JSON field or as simple key-value pairs

### Table: `effect_categories` (NEW — must be created)

```sql
CREATE TABLE public.effect_categories (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  name         text        NOT NULL UNIQUE,
  display_name text        NOT NULL,
  sort_order   integer     NOT NULL DEFAULT 0,
  icon         text,
  is_active    boolean     NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT effect_categories_pkey PRIMARY KEY (id)
);

ALTER TABLE public.effect_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read categories" ON public.effect_categories FOR SELECT TO public USING (true);
CREATE POLICY "Full access for service role" ON public.effect_categories FOR ALL TO service_role USING (true) WITH CHECK (true);
```

Column descriptions:
- `name` — internal slug (e.g. `"romantic"`, `"funny"`, `"artistic"`)
- `display_name` — human-readable name shown in the app (e.g. "Romantic", "Funny", "Artistic")
- `sort_order` — display order of categories in the app
- `icon` — optional emoji or SF Symbol name (just a text string)
- `is_active` — inactive categories are hidden from the app

### Table: `generations` (ALREADY EXISTS — read-only for the admin panel)

This table stores every video generation job. The admin panel should display this data for monitoring purposes but never modify it.

Key columns:
- `id` (uuid) — generation ID
- `device_id` (uuid) — which device initiated it
- `status` (text) — `"pending"`, `"processing"`, `"completed"`, or `"failed"`
- `input_image_url` (text) — user's uploaded photo
- `output_video_url` (text) — resulting video (when completed)
- `prompt` (text) — the final prompt that was sent to the AI
- `error_message` (text) — error details if failed
- `created_at` (timestamptz) — when it was initiated
- `updated_at` (timestamptz) — last status change

After we integrate effects, there will also be an `effect_id` column linking to the effects table, but it may not exist yet when you build the panel. Handle it gracefully (show it if present, skip if not).

---

## What the Admin Panel Should Do

### 1. Effects Management (the primary purpose)

**Effects list page:**
- Show all effects in a table or card grid
- Each effect shows: thumbnail (if available), name, category, active/inactive badge, premium badge, provider, sort order
- Quick toggle for `is_active` directly in the list (switch/checkbox, no need to open the editor)
- Button to create a new effect
- Click on an effect to open the editor
- Ability to delete an effect (with confirmation dialog)
- Filtering by category and by active/inactive status
- If possible, drag-and-drop to reorder (updating `sort_order`), but simple manual number input is also fine

**Effect editor page (create & edit use the same form):**

The form should have clearly labeled fields for everything in the `effects` table:

- **Name** — text input, required
- **Description** — text area, optional
- **Category** — dropdown populated from `effect_categories` table, optional
- **Preview Video URL** — text input for URL. Ideally also a file upload that uploads to Supabase Storage bucket `reference-videos` and fills in the URL automatically. Show a video preview player if a URL is set
- **Thumbnail URL** — same as above but for images, uploading to the same bucket. Show image preview if set
- **Active** — toggle switch
- **Premium** — toggle switch
- **Sort Order** — number input
- **Requires Secondary Photo** — toggle switch. Show a helpful note: "Enable this for effects that involve two people (e.g. couple scenes). The app will ask the user to upload a second photo."
- **Provider** — text input with suggestions/autocomplete showing known values: `"kling"`, `"grok"`. Free text so new providers can be typed in
- **Generation Params** — either a JSON editor or a simple set of key-value pair inputs. Default value: `{"duration": 5, "aspect_ratio": "9:16"}`
- **System Prompt Template** — large text area, the most important field. Show a note above it: "This is the AI prompt. Use `{{user_prompt}}` where you want the user's text to be inserted." Show a character count

The form should have:
- "Save" button (creates or updates)
- "Duplicate" action — creates a copy of this effect with "(Copy)" appended to the name
- Visual indication of required fields
- Confirmation before navigating away with unsaved changes

### 2. Categories Management

A simpler secondary page:
- List all categories with display name, slug, icon, sort order, active status
- Inline editing or a simple modal form for create/edit
- Delete with confirmation (warn if effects are using this category)
- Reorder capability

### 3. Generations Monitor

A read-only page for monitoring:
- Table of recent generations (most recent first), paginated
- Columns: status (with color-coded badge), created time, device ID (truncated), prompt (truncated), effect name (if `effect_id` exists)
- Click to expand and see full details: full prompt, error message, input/output URLs (with clickable links to view images/videos), timestamps
- Filter by status (pending / processing / completed / failed)
- Auto-refresh every 30 seconds or a manual refresh button
- Summary stats at the top: total today, completed today, failed today, currently processing

### 4. Dashboard (Home Page)

A simple overview page shown after login:
- Total effects (active / inactive)
- Total categories
- Generations summary: today, this week, all time
- Recent generations (last 10, compact list)
- Quick links to "Create New Effect" and "View All Effects"

---

## UX Expectations

- **Clean and minimal.** This is an internal tool for one person. No need for flashy design, but it should feel professional and pleasant to use. Good spacing, clear typography.
- **Fast.** List pages should load quickly. The effect editor should be a single page (not a multi-step wizard).
- **Responsive-ish.** I'll mostly use it on desktop, but it should be usable on a tablet too.
- **Confirmations for destructive actions.** Always confirm before deleting. Show success/error toasts after save operations.
- **Don't lose my work.** Warn before navigating away from an unsaved form.

---

## Supabase Connection

The app connects to my Supabase project. You will have access to Supabase via the integration. Use the Supabase client library to read and write data. Use the `service_role` key for all operations since this is an admin-only tool.

The storage buckets already exist:
- `reference-videos` — for effect preview videos and thumbnails
- `portraits` — user photos (read-only for admin)
- `generated-videos` — output videos (read-only for admin)

When uploading files (preview videos, thumbnails), upload them to the `reference-videos` bucket and use the resulting public URL.

---

## Summary

The core job: let me create and manage AI video effects from a web interface instead of editing Supabase rows directly. Full CRUD on effects and categories, plus a read-only generations monitor. Simple password auth. That's it.
