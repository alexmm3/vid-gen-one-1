import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = "https://dreyqidpesyeiuqfxdis.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRyZXlxaWRwZXN5ZWl1cWZ4ZGlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDQyMzcsImV4cCI6MjA4Nzc4MDIzN30.CI8lHkvGvvPnx335E_LSoh5BTKWBgArgd6sT8xSX4co";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function test() {
  const { data: effect, error } = await supabase
    .from('effects')
    .select('*')
    .eq('id', 'a1111111-1111-1111-1111-111111111111');

  console.log("Effects:", effect);
  console.log("Error:", error);
}

test();
