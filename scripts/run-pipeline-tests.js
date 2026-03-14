#!/usr/bin/env node
/**
 * Run pipeline tests for both short (2-step) and full (4-step) pipelines.
 * Usage: node scripts/run-pipeline-tests.js [SHORT|FULL|BOTH]
 *
 * Requires: SUPABASE_URL and SUPABASE_ANON_KEY env vars, or uses defaults from run_pipeline.js
 */

const SUPABASE_URL = process.env.SUPABASE_URL || "https://oquhbidxsntfrqsloocc.supabase.co";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9xdWhiaWR4c250ZnJxc2xvb2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNzQ2NjQsImV4cCI6MjA4ODc1MDY2NH0.yasTip_i88__3Aba0ED1iwO1tjmu7HP9dGDWN9MAaqc";

const EFFECTS = {
  SHORT: {
    id: "a1111111-1111-1111-1111-111111111111",
    name: "Cinematic Magic (Pipeline A)",
    steps: 2,
    image: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&q=80",
    prompt: "Add some sparkle",
  },
  FULL: {
    id: "c3333333-3333-3333-3333-333333333333",
    name: "Full Pipeline Adventure",
    steps: 4,
    image: "https://images.unsplash.com/photo-1543852786-1cf6624b9987?q=80&w=1000&auto=format&fit=crop",
    prompt: "Make it epic",
  },
  VISION_ONLY: {
    id: "b2222222-2222-2222-2222-222222222222",
    name: "Personalized Adventure (Pipeline B)",
    steps: 3,
    image: "https://images.unsplash.com/photo-1543852786-1cf6624b9987?q=80&w=1000&auto=format&fit=crop",
    prompt: "Cyberpunk vibes",
  },
};

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runPipeline(effectKey) {
  const effect = EFFECTS[effectKey];
  if (!effect) {
    console.error(`Unknown effect: ${effectKey}. Use SHORT, FULL, or VISION_ONLY`);
    process.exit(1);
  }

  console.log(`\n${"=".repeat(60)}`);
  console.log(`🚀 Testing: ${effect.name} (${effect.steps} steps)`);
  console.log(`   Effect ID: ${effect.id}`);
  console.log(`   Image: ${effect.image.substring(0, 50)}...`);
  console.log(`   Prompt: "${effect.prompt}"`);
  console.log(`${"=".repeat(60)}\n`);

  const deviceId = `test-pipeline-${effectKey}-${Date.now()}`;

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
      user_prompt: effect.prompt,
    }),
  });

  const startData = await startRes.json();

  if (!startRes.ok) {
    console.error("❌ Failed to start generation:", startData);
    return { success: false, error: startData };
  }

  if (!startData.generation_id) {
    console.error("❌ No generation_id in response:", startData);
    return { success: false, error: startData };
  }

  const genId = startData.generation_id;
  const pipelineExecId = startData.pipeline_execution_id;

  console.log(`✅ Generation started: ${genId}`);
  if (pipelineExecId) {
    console.log(`   Pipeline execution: ${pipelineExecId}`);
  }
  console.log(`   Status: ${startData.status}`);

  // Poll for completion
  let attempts = 0;
  const maxAttempts = 60; // 5 min at 5s intervals

  while (attempts < maxAttempts) {
    await sleep(5000);
    attempts++;

    const statusRes = await fetch(
      `${SUPABASE_URL}/functions/v1/check-generation-status?generation_id=${genId}`,
      { headers: { Authorization: `Bearer ${SUPABASE_ANON_KEY}` } }
    );

    if (!statusRes.ok) {
      console.error(`   Poll ${attempts}: HTTP ${statusRes.status}`);
      continue;
    }

    const statusData = await statusRes.json();
    console.log(`   [${new Date().toISOString()}] Status: ${statusData.status}`);

    if (statusData.status === "completed") {
      console.log(`\n✅ Pipeline completed successfully!`);
      console.log(`   Output video: ${statusData.output_video_url || "N/A"}`);
      return { success: true, generation_id: genId, output_video_url: statusData.output_video_url };
    }

    if (statusData.status === "failed") {
      console.error(`\n❌ Pipeline failed: ${statusData.error_message || "Unknown error"}`);
      return { success: false, generation_id: genId, error: statusData.error_message };
    }
  }

  console.error(`\n⏱️ Timeout after ${maxAttempts} polls`);
  return { success: false, generation_id: genId, error: "Timeout" };
}

async function main() {
  const mode = (process.argv[2] || "BOTH").toUpperCase();

  console.log("\n📋 Pipeline Test Runner");
  console.log(`   Mode: ${mode}`);
  console.log(`   Supabase: ${SUPABASE_URL}\n`);

  const results = [];

  if (mode === "SHORT" || mode === "BOTH") {
    results.push({ name: "Short (2-step)", ...(await runPipeline("SHORT")) });
  }
  if (mode === "FULL" || mode === "BOTH") {
    results.push({ name: "Full (4-step)", ...(await runPipeline("FULL")) });
  }
  if (mode === "VISION_ONLY") {
    results.push({ name: "Vision (3-step)", ...(await runPipeline("VISION_ONLY")) });
  }

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("SUMMARY");
  console.log("=".repeat(60));
  for (const r of results) {
    console.log(`  ${r.name}: ${r.success ? "✅ PASS" : "❌ FAIL"}`);
  }
  console.log("");

  const allPassed = results.every((r) => r.success);
  process.exit(allPassed ? 0 : 1);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
