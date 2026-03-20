#!/bin/bash
# App Store Connect API helper
# Usage: ./scripts/asc-api.sh <endpoint> [method] [body]
# Example: ./scripts/asc-api.sh /v1/apps GET
#          ./scripts/asc-api.sh /v1/apps/APP_ID/appStoreVersions GET

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load env
if [ -f "$PROJECT_DIR/.keys/appstore.env" ]; then
  set -a
  source "$PROJECT_DIR/.keys/appstore.env"
  set +a
fi

KEY_ID="${APP_STORE_CONNECT_KEY_ID:?Missing KEY_ID}"
ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:?Missing ISSUER_ID}"
KEY_PATH="${PROJECT_DIR}/${APP_STORE_CONNECT_KEY_PATH:?Missing KEY_PATH}"

# Generate JWT
JWT_TOKEN=$(ruby -rjwt -ropenssl -e "
key = OpenSSL::PKey::EC.new(File.read('${KEY_PATH}'))
token = JWT.encode({iss: '${ISSUER_ID}', exp: Time.now.to_i + 1200, aud: 'appstoreconnect-v1'}, key, 'ES256', {kid: '${KEY_ID}'})
print token
")

ENDPOINT="${1:?Usage: asc-api.sh <endpoint> [GET|POST|PATCH|DELETE] [json-body]}"
METHOD="${2:-GET}"
BODY="${3:-}"

if [ -n "$BODY" ]; then
  curl -s -X "$METHOD" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "https://api.appstoreconnect.apple.com${ENDPOINT}" | python3 -m json.tool
else
  curl -s -X "$METHOD" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    "https://api.appstoreconnect.apple.com${ENDPOINT}" | python3 -m json.tool
fi
