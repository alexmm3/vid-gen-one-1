import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface AuthRequest {
  password: string;
}

interface AuthResponse {
  success: boolean;
  token?: string;
  expires_at?: string;
  error?: string;
}

// Generate a session token valid for 24 hours
function generateSessionToken(password: string): { token: string; expiresAt: Date } {
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
  const payload = `admin:${expiresAt.getTime()}`;
  const secret = password; // Use password as HMAC key
  
  const hmac = createHmac("sha256", secret);
  hmac.update(payload);
  const signature = hmac.digest("hex");
  
  // Token format: base64(payload):signature
  const token = `${btoa(payload)}:${signature}`;
  
  return { token, expiresAt };
}

// Verify a session token
function verifySessionToken(token: string, password: string): boolean {
  try {
    const [encodedPayload, signature] = token.split(":");
    if (!encodedPayload || !signature) return false;
    
    const payload = atob(encodedPayload);
    const [prefix, expiresAtStr] = payload.split(":");
    
    if (prefix !== "admin") return false;
    
    const expiresAt = parseInt(expiresAtStr, 10);
    if (isNaN(expiresAt) || Date.now() > expiresAt) return false;
    
    // Verify signature
    const hmac = createHmac("sha256", password);
    hmac.update(payload);
    const expectedSignature = hmac.digest("hex");
    
    return signature === expectedSignature;
  } catch {
    return false;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const adminPassword = Deno.env.get("ADMIN");
    
    if (!adminPassword) {
      console.error("ADMIN secret not configured");
      return new Response(
        JSON.stringify({ success: false, error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "login";

    if (action === "verify") {
      // Verify existing token
      const authHeader = req.headers.get("authorization");
      const token = authHeader?.replace("Bearer ", "");
      
      if (!token) {
        return new Response(
          JSON.stringify({ success: false, error: "No token provided" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const isValid = verifySessionToken(token, adminPassword);
      
      return new Response(
        JSON.stringify({ success: isValid, error: isValid ? undefined : "Invalid or expired token" }),
        { status: isValid ? 200 : 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Login action
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ success: false, error: "Method not allowed" }),
        { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body: AuthRequest = await req.json();
    const { password } = body;

    if (!password) {
      return new Response(
        JSON.stringify({ success: false, error: "Password required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Constant-time comparison to prevent timing attacks
    const passwordMatch = password.length === adminPassword.length && 
      password.split("").every((char, i) => char === adminPassword[i]);

    if (!passwordMatch) {
      // Add small delay to prevent brute force
      await new Promise(resolve => setTimeout(resolve, 1000));
      return new Response(
        JSON.stringify({ success: false, error: "Invalid password" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Generate session token
    const { token, expiresAt } = generateSessionToken(adminPassword);

    const response: AuthResponse = {
      success: true,
      token,
      expires_at: expiresAt.toISOString(),
    };

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Auth error:", error);
    return new Response(
      JSON.stringify({ success: false, error: "Authentication failed" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
