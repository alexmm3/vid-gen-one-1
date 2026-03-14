import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function sanitizeFileName(fileName: string): string {
  const lastDot = fileName.lastIndexOf('.');
  const name = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
  const ext = lastDot > 0 ? fileName.substring(lastDot) : '';

  const sanitized = name
    .trim()
    .replace(/\s+/g, '-')
    .replace(/[^a-zA-Z0-9_.-]/g, '-')
    .replace(/-{2,}/g, '-')
    .replace(/^-+|-+$/g, '');

  return (sanitized || 'unnamed') + ext.toLowerCase();
}

function verifySessionToken(token: string, password: string): boolean {
  try {
    const [encodedPayload, signature] = token.split(":");
    if (!encodedPayload || !signature) return false;

    const payload = atob(encodedPayload);
    const [prefix, expiresAtStr] = payload.split(":");

    if (prefix !== "admin") return false;

    const expiresAt = parseInt(expiresAtStr, 10);
    if (isNaN(expiresAt) || Date.now() > expiresAt) return false;

    const hmac = createHmac("sha256", password);
    hmac.update(payload);
    const expectedSignature = hmac.digest("hex");

    return signature === expectedSignature;
  } catch {
    return false;
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const token = authHeader.replace('Bearer ', '');
    const adminSecret = Deno.env.get('ADMIN');

    if (!adminSecret) {
      console.error('ADMIN secret not configured');
      return new Response(JSON.stringify({ error: 'Server configuration error' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const isValid = verifySessionToken(token, adminSecret);

    if (!isValid) {
      return new Response(JSON.stringify({ error: 'Invalid or expired token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const url = new URL(req.url);
    const action = url.searchParams.get('action');

    if (req.method === 'GET') {
      const { data, error } = await supabase
        .from('reference_videos')
        .select('*')
        .order('sort_order', { ascending: true });

      if (error) throw error;

      return new Response(JSON.stringify({ success: true, templates: data }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (req.method === 'POST') {
      const contentType = req.headers.get('content-type') || '';

      if (action === 'create') {
        const body = await req.json();
        const { name, description, video_url, thumbnail_url, preview_url, duration_seconds, is_active, sort_order } = body;

        const { data, error } = await supabase
          .from('reference_videos')
          .insert({
            name,
            description,
            video_url,
            thumbnail_url,
            preview_url: preview_url || null,
            duration_seconds,
            is_active: is_active ?? true,
            sort_order: sort_order ?? 0,
          })
          .select()
          .single();

        if (error) throw error;

        return new Response(JSON.stringify({ success: true, template: data }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (action === 'update') {
        const body = await req.json();
        const { id, ...updates } = body;

        const { data, error } = await supabase
          .from('reference_videos')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

        if (error) throw error;

        return new Response(JSON.stringify({ success: true, template: data }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (action === 'delete') {
        const body = await req.json();
        const { id } = body;

        const { error } = await supabase
          .from('reference_videos')
          .delete()
          .eq('id', id);

        if (error) throw error;

        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (action === 'upload') {
        const bucket = 'reference-videos';
        let fileBody: ArrayBuffer;
        let rawFileName: string;
        let fileContentType: string;
        let folder = 'templates';

        if (contentType.includes('application/json')) {
          const body = await req.json();
          rawFileName = body.fileName;
          fileContentType = body.contentType || 'video/mp4';
          folder = body.folder || folder;

          if (!rawFileName) {
            return new Response(JSON.stringify({ error: 'fileName is required' }), {
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          }

          if (body.fileData) {
            const binaryString = atob(body.fileData);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
              bytes[i] = binaryString.charCodeAt(i);
            }
            fileBody = bytes.buffer;
          } else {
            return new Response(JSON.stringify({ error: 'fileData (base64) is required for JSON upload' }), {
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          }
        } else {
          rawFileName = url.searchParams.get('fileName') || '';
          fileContentType = url.searchParams.get('contentType') || 'video/mp4';
          const folderParam = url.searchParams.get('folder');
          if (folderParam) folder = folderParam;

          if (!rawFileName) {
            return new Response(JSON.stringify({ error: 'fileName query parameter required' }), {
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          }

          fileBody = await req.arrayBuffer();
        }

        const fileName = sanitizeFileName(rawFileName);
        const filePath = `${folder}/${Date.now()}_${fileName}`;

        const { data: uploadData, error: uploadError } = await supabase.storage
          .from(bucket)
          .upload(filePath, fileBody, {
            contentType: fileContentType,
            upsert: false,
          });

        if (uploadError || !uploadData) {
          console.error('Supabase Storage upload failed:', uploadError ?? 'no data returned');
          return new Response(JSON.stringify({ error: `Upload failed: ${uploadError?.message ?? 'unknown'}` }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const { data: urlData } = supabase.storage.from(bucket).getPublicUrl(uploadData.path);
        const publicUrl = urlData.publicUrl;

        return new Response(JSON.stringify({
          success: true,
          publicUrl,
          filePath: uploadData.path,
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response(JSON.stringify({ error: 'Invalid action' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error: unknown) {
    console.error('Admin templates error:', error);
    const message = error instanceof Error ? error.message : 'Unknown error';
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
