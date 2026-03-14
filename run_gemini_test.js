const SUPABASE_URL = "https://oquhbidxsntfrqsloocc.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9xdWhiaWR4c250ZnJxc2xvb2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNzQ2NjQsImV4cCI6MjA4ODc1MDY2NH0.yasTip_i88__3Aba0ED1iwO1tjmu7HP9dGDWN9MAaqc";

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function run() {
  console.log("Triggering pipeline...");
  const startRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-video`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${SUPABASE_ANON_KEY}`
    },
    body: JSON.stringify({
      device_id: "test-device-123",
      effect_id: "c3333333-3333-3333-3333-333333333333",
      input_image_url: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&q=80",
      user_prompt: "Make it look like a vibrant sunset."
    })
  });

  const startData = await startRes.json();
  console.log("Start response:", startData);
}

run();
