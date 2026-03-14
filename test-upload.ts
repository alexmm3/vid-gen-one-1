import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = "https://dreyqidpesyeiuqfxdis.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRyZXlxaWRwZXN5ZWl1cWZ4ZGlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDQyMzcsImV4cCI6MjA4Nzc4MDIzN30.CI8lHkvGvvPnx335E_LSoh5BTKWBgArgd6sT8xSX4co";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function upload() {
  const imagePath = "/Users/alexm/.cursor/projects/Users-alexm-Documents-video-app-ios-effects/assets/cyberpunk_source.png";
  const imageBytes = await Deno.readFile(imagePath);
  
  const { data, error } = await supabase.storage
    .from("portraits")
    .upload(`test-${Date.now()}.png`, imageBytes, { contentType: "image/png" });
    
  console.log("Upload result:", data, error);
  
  if (data) {
    const { data: urlData } = supabase.storage.from("portraits").getPublicUrl(data.path);
    console.log("Public URL:", urlData.publicUrl);
  }
}

upload();
