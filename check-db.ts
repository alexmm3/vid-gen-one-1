import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = "https://dreyqidpesyeiuqfxdis.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRyZXlxaWRwZXN5ZWl1cWZ4ZGlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDQyMzcsImV4cCI6MjA4Nzc4MDIzN30.CI8lHkvGvvPnx335E_LSoh5BTKWBgArgd6sT8xSX4co";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function check() {
  const { data, error } = await supabase.from("pipeline_templates").select("*").limit(1);
  console.log("Pipeline templates:", data, error);
}

check();
