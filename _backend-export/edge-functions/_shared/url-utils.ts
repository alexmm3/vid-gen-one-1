/**
 * Validate that a URL is a publicly accessible HTTP(S) URL.
 * Rejects file://, local paths, and other non-HTTP schemes.
 */
export function isValidPublicUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

/**
 * Ensure a URL is properly encoded for use in external API calls.
 * Handles URLs that may contain spaces or other unencoded characters.
 * Uses encodeURI which encodes spaces but preserves URL structure (://?&#=).
 */
export function ensureEncodedUrl(url: string): string {
  try {
    // If the URL already contains encoded characters (%20, etc.), decode first to avoid double-encoding
    const decoded = decodeURI(url);
    return encodeURI(decoded);
  } catch {
    // If decoding fails (malformed), just encode as-is
    return encodeURI(url);
  }
}
