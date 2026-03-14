import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = "https://oquhbidxsntfrqsloocc.supabase.co";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function test() {
  console.log("Fetching effects from URL:", SUPABASE_URL);
  const { data, error } = await supabase.from('effects').select('id, name');
  console.log("Data:", data);
  console.log("Error:", error);
}

test();
