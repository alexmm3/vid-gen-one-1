#!/usr/bin/env node
/**
 * Run each Famous Directors effect once with a suitable (but not too literal) test image.
 * Prerequisites:
 *   1. Apply migration: supabase db push  OR  run supabase/migrations/00006_famous_directors_effects.sql
 *   2. Set SUPABASE_URL and SUPABASE_ANON_KEY (or they default to the project in repo)
 *
 * Usage: node scripts/run-famous-directors-pipelines.js
 * Output: logs each effect, then prints summary with output_video_url or error.
 */

const SUPABASE_URL = process.env.SUPABASE_URL || "https://oquhbidxsntfrqsloocc.supabase.co";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9xdWhiaWR4c250ZnJxc2xvb2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNzQ2NjQsImV4cCI6MjA4ODc1MDY2NH0.yasTip_i88__3Aba0ED1iwO1tjmu7HP9dGDWN9MAaqc";

const EFFECTS = [
  {
    id: "fd200001-0001-4000-8000-000000000001",
    name: "Perspective Warp",
    image: "https://images.unsplash.com/photo-1524758631624-e2822e304c36?w=800&q=80",
    user_prompt: "",
  },
  {
    id: "fd200002-0002-4000-8000-000000000002",
    name: "Room Breathing",
    image: "https://images.unsplash.com/photo-1527482797697-8795b05a13fe?w=800&q=80",
    user_prompt: "",
  },
  {
    id: "fd200003-0003-4000-8000-000000000003",
    name: "Selective Time Aging",
    image: "https://images.unsplash.com/photo-1513694203232-719a280e022f?w=800&q=80",
    user_prompt: "",
  },
  {
    id: "fd200004-0004-4000-8000-000000000004",
    name: "Slow Reality",
    image: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80",
    user_prompt: "",
  },
  {
    id: "fd200005-0005-4000-8000-000000000005",
    name: "Emotional Environment",
    image: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=800&q=80",
    user_prompt: "",
  },
  {
    id: "fd200006-0006-4000-8000-000000000006",
    name: "Nanite Disassembly",
    image: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&q=80",
    user_prompt: "",
  },
];

const POLL_INTERVAL_MS = 8000;
const MAX_POLL_ATTEMPTS = 50; // ~6.5 min per effect

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runEffect(effect) {
  const deviceId = `fd-test-${effect.id.slice(0, 8)}-${Date.now()}`;

  const startRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-video`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "x-region": "us-east-1",
    },
    body: JSON.stringify({
      device_id: deviceId,
      effect_id: effect.id,
      input_image_url: effect.image,
      user_prompt: effect.user_prompt || "",
    }),
  });

  const startData = await startRes.json();

  if (!startRes.ok) {
    return {
      name: effect.name,
      effect_id: effect.id,
      success: false,
      error: startData.error || startData,
      generation_id: null,
      output_video_url: null,
    };
  }

  if (!startData.generation_id) {
    return {
      name: effect.name,
      effect_id: effect.id,
      success: false,
      error: "No generation_id in response: " + JSON.stringify(startData),
      generation_id: null,
      output_video_url: null,
    };
  }

  const genId = startData.generation_id;
  let attempts = 0;

  while (attempts < MAX_POLL_ATTEMPTS) {
    await sleep(POLL_INTERVAL_MS);
    attempts++;

    const statusRes = await fetch(
      `${SUPABASE_URL}/functions/v1/check-generation-status?generation_id=${genId}`,
      { headers: { Authorization: `Bearer ${SUPABASE_ANON_KEY}` } }
    );

    if (!statusRes.ok) {
      console.log(`   [${effect.name}] Poll ${attempts} HTTP ${statusRes.status}`);
      continue;
    }

    const statusData = await statusRes.json();

    if (statusData.status === "completed") {
      return {
        name: effect.name,
        effect_id: effect.id,
        success: true,
        generation_id: genId,
        output_video_url: statusData.output_video_url || null,
        error: null,
      };
    }

    if (statusData.status === "failed") {
      return {
        name: effect.name,
        effect_id: effect.id,
        success: false,
        generation_id: genId,
        output_video_url: null,
        error: statusData.error_message || "Unknown failure",
        error_log: statusData.error_log,
      };
    }

    process.stdout.write(`   [${effect.name}] ${statusData.status} (${attempts}/${MAX_POLL_ATTEMPTS})\r`);
  }

  return {
    name: effect.name,
    effect_id: effect.id,
    success: false,
    generation_id: genId,
    output_video_url: null,
    error: "Timeout waiting for video",
  };
}

async function main() {
  console.log("\nFamous Directors — run each pipeline once\n");
  console.log("Supabase:", SUPABASE_URL);
  console.log("Effects:", EFFECTS.length);
  console.log("");

  const results = [];

  for (const effect of EFFECTS) {
    console.log(`\n--- ${effect.name} (${effect.id}) ---`);
    console.log("Image:", effect.image.slice(0, 60) + "...");
    const r = await runEffect(effect);
    results.push(r);
    if (r.success) {
      console.log(`\n   Done. Video: ${r.output_video_url || "N/A"}`);
    } else {
      console.log(`\n   Failed: ${r.error}`);
      if (r.error_log && r.error_log.length) {
        console.log("   Error log (last 3):");
        r.error_log.slice(-3).forEach((e) => console.log("     ", JSON.stringify(e)));
      }
    }
  }

  console.log("\n" + "=".repeat(70));
  console.log("SUMMARY — Famous Directors pipelines");
  console.log("=".repeat(70));

  for (const r of results) {
    console.log(`\n${r.name}:`);
    console.log(`  Effect ID: ${r.effect_id}`);
    if (r.success) {
      console.log(`  Output video: ${r.output_video_url || "N/A"}`);
    } else {
      console.log(`  Error: ${r.error}`);
    }
  }

  console.log("\n");
  const succeeded = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);
  console.log(`Completed: ${succeeded.length}/${results.length}`);
  if (failed.length) {
    console.log(`Failed: ${failed.map((r) => r.name).join(", ")}`);
  }
  process.exit(failed.length ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
