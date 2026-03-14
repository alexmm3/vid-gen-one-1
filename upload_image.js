const fs = require('fs');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = "https://oquhbidxsntfrqsloocc.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9xdWhiaWR4c250ZnJxc2xvb2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNzQ2NjQsImV4cCI6MjA4ODc1MDY2NH0.yasTip_i88__3Aba0ED1iwO1tjmu7HP9dGDWN9MAaqc";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function run() {
  const fileBuffer = fs.readFileSync('image_user.png');
  const fileName = `test_user_${Date.now()}.png`;

  const { data, error } = await supabase.storage
    .from('portraits')
    .upload(fileName, fileBuffer, {
      contentType: 'image/png',
      upsert: true
    });

  if (error) {
    console.error("Upload error:", error);
    return;
  }

  const { data: { publicUrl } } = supabase.storage
    .from('portraits')
    .getPublicUrl(fileName);

  console.log("Uploaded URL:", publicUrl);
}

run();
