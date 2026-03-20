import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { toClientSafeMessage } from "../_shared/client-safe-message.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { prompt, aspect_ratio = "9:16" } = await req.json();

    if (!prompt) {
      return new Response(JSON.stringify({ error: "Missing prompt" }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const grokApiKey = Deno.env.get("GROK_API_KEY");
    if (!grokApiKey) {
      return new Response(JSON.stringify({ error: toClientSafeMessage("GROK_API_KEY not configured") }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Call Grok Imagine Image API
    const res = await fetch("https://api.x.ai/v1/images/generations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${grokApiKey}`
      },
      body: JSON.stringify({
        model: "grok-imagine-image",
        prompt: prompt,
        n: 1,
        aspect_ratio: aspect_ratio,
        response_format: "url"
      })
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Grok API error: ${res.status} ${errText}`);
    }

    const data = await res.json();
    const imageUrl = data.data[0].url;

    // Download the image
    const imgRes = await fetch(imageUrl);
    if (!imgRes.ok) {
      throw new Error(`Failed to download image from Grok: ${imgRes.statusText}`);
    }
    const arrayBuffer = await imgRes.arrayBuffer();

    // Upload to Supabase Storage
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const filename = `previews/grok_${Date.now()}_${Math.random().toString(36).substring(7)}.jpg`;

    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('portraits')
      .upload(filename, arrayBuffer, {
        contentType: 'image/jpeg',
        upsert: true
      });

    if (uploadError) {
      throw new Error(`Failed to upload to Supabase: ${uploadError.message}`);
    }

    const { data: publicUrlData } = supabase.storage
      .from('portraits')
      .getPublicUrl(filename);

    return new Response(JSON.stringify({ success: true, url: publicUrlData.publicUrl }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error: unknown) {
    console.error("Error in generate-grok-image:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: toClientSafeMessage(msg) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
