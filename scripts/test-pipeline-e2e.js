// test-pipeline-e2e.js
// Run this script using Node.js to simulate an iOS app request to the generate-video edge function.
// Usage: node test-pipeline-e2e.js <SUPABASE_URL> <SUPABASE_ANON_KEY> <EFFECT_ID>

const SUPABASE_URL = process.argv[2];
const SUPABASE_ANON_KEY = process.argv[3];
const EFFECT_ID = process.argv[4];

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !EFFECT_ID) {
  console.error("Usage: node test-pipeline-e2e.js <SUPABASE_URL> <SUPABASE_ANON_KEY> <EFFECT_ID>");
  console.error("Example: node test-pipeline-e2e.js https://xyz.supabase.co eyJhb... a1111111-1111-1111-1111-111111111111");
  process.exit(1);
}

const DEVICE_ID = "TEST_DEVICE_" + Date.now();
// A sample public image URL to use as input
const INPUT_IMAGE_URL = "https://images.unsplash.com/photo-1543852786-1cf6624b9987?q=80&w=1000&auto=format&fit=crop";
const USER_PROMPT = "Make it look like a cyberpunk movie";

async function runTest() {
  console.log(`\n🚀 Starting E2E Pipeline Test for Effect: ${EFFECT_ID}`);
  console.log(`📱 Simulating Device ID: ${DEVICE_ID}`);
  console.log(`🖼️  Input Image: ${INPUT_IMAGE_URL}`);
  console.log(`💬 User Prompt: "${USER_PROMPT}"\n`);

  try {
    // 1. Call generate-video edge function
    console.log("⏳ Calling generate-video edge function...");
    const generateRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-video`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${SUPABASE_ANON_KEY}`
      },
      body: JSON.stringify({
        device_id: DEVICE_ID,
        effect_id: EFFECT_ID,
        input_image_url: INPUT_IMAGE_URL,
        user_prompt: USER_PROMPT
      })
    });

    const generateData = await generateRes.json();
    
    if (!generateRes.ok) {
      console.error("❌ generate-video failed:", generateData);
      return;
    }

    console.log("✅ generate-video succeeded!");
    console.log("Response:", JSON.stringify(generateData, null, 2));

    const generationId = generateData.generation_id;
    const pipelineExecutionId = generateData.pipeline_execution_id;

    if (pipelineExecutionId) {
      console.log(`\n🔗 Pipeline Execution ID: ${pipelineExecutionId}`);
      console.log("The pipeline pre-processing steps have completed successfully.");
      console.log("The video generation has been queued with Grok.");
    } else {
      console.log("\n⚠️ No pipeline execution ID returned. This effect might not be linked to a pipeline, or it ran as a direct generation.");
    }

    console.log(`\n🔍 To monitor the progress, you can check the 'generations' and 'pipeline_executions' tables in your Supabase dashboard for generation_id: ${generationId}`);
    console.log("Or wait for the poll-pending-generations cron job to run.");

  } catch (err) {
    console.error("❌ Test failed with error:", err);
  }
}

runTest();
