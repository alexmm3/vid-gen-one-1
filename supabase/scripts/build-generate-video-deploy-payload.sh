#!/usr/bin/env bash
# Builds MCP deploy payloads for generate-video (single-file min bundle + optional b64 chunks).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_SINGLE="$ROOT/supabase/.deploy-generate-video.payload.json"
OUT_B64="$ROOT/supabase/.b64-deploy-generate-video.payload.json"
ENTRY="$ROOT/supabase/functions/generate-video/index.ts"
TMP_MIN="$(mktemp)"

npx --yes esbuild "$ENTRY" \
  --bundle \
  --platform=neutral \
  --format=esm \
  --minify \
  --legal-comments=none \
  --outfile="$TMP_MIN"

jq -n \
  --rawfile c "$TMP_MIN" \
  '{name:"generate-video",entrypoint_path:"index.ts",verify_jwt:false,files:[{name:"index.ts",content:$c}]}' \
  >"$OUT_SINGLE"

OUT_SINGLE="$OUT_SINGLE" OUT_B64="$OUT_B64" python3 <<'PY'
import json, base64, os
from pathlib import Path
out_path = Path(os.environ["OUT_B64"])
payload = json.loads(Path(os.environ["OUT_SINGLE"]).read_text())
raw = payload["files"][0]["content"].encode("utf-8")
b64 = base64.b64encode(raw).decode("ascii")
chunk_size = 20000
chunks = [b64[i : i + chunk_size] for i in range(0, len(b64), chunk_size)]
n = len(chunks)
index_ts = 'import { decode } from "https://deno.land/std@0.168.0/encoding/base64.ts";\n\nconst parts: string[] = [];\n'
for i in range(n):
    index_ts += f'parts.push(await Deno.readTextFile(new URL("./b{i}.txt", import.meta.url)));\n'
index_ts += "\nconst b64Payload = parts.join('').replace(/\\s/g, '');\n"
index_ts += "const bundled = new TextDecoder().decode(decode(b64Payload));\n"
index_ts += "await import(`data:application/javascript;charset=utf-8,${encodeURIComponent(bundled)}`);\n"
files = [{"name": "index.ts", "content": index_ts}]
for i, ch in enumerate(chunks):
    files.append({"name": f"b{i}.txt", "content": ch})
obj = {"name": "generate-video", "entrypoint_path": "index.ts", "verify_jwt": False, "files": files}
out_path.write_text(json.dumps(obj, ensure_ascii=False))
print("Wrote", out_path, "chunks", n, "bytes", out_path.stat().st_size)
PY

rm -f "$TMP_MIN"
echo "OK: $OUT_SINGLE ($(wc -c <"$OUT_SINGLE") bytes) | $OUT_B64 ($(wc -c <"$OUT_B64") bytes)"
