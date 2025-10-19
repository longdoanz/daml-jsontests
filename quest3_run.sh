#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="../json-tests"
DAR_PATH="${PROJECT_NAME}/.daml/dist/json-tests-0.0.1.dar"
SANDBOX_PORT=6865
JSONAPI_PORT=7575
SECRET="sEcrEt"
DAML_BIN="$HOME/.daml/bin"
export ALICE_JWT='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJodHRwczovL2RhbWwuY29tL2xlZGdlci1hcGkiOnsibGVkZ2VySWQiOiJzYW5kYm94IiwiYXBwbGljYXRpb25JZCI6IkhUVFAtSlNPTi1BUEktR2F0ZXdheSIsImFjdEFzIjpbIkFsaWNlIl19fQ.FIjS4ao9yu1XYnv1ZL3t7ooPNIyQYAHY3pmzej4EMCM'


echo "🚀 Quest3 auto-run bắt đầu..."

echo "🛑 Dừng tất cả tiến trình daml cũ..."
pkill -f daml || true

# Kiểm tra xem project directory có tồn tại không trước khi dùng DAR_PATH
if [ ! -d "${PROJECT_NAME}" ]; then
  echo "❌ Project directory '${PROJECT_NAME}' không tồn tại. PROJECT_NAME."
  $DAML_BIN/daml new $PROJECT_NAME
else
  echo "✅ Project directory '${PROJECT_NAME}' đã tồn tại."
  cp -r json-tests/* $PROJECT_NAME/
fi

# Đảm bảo DAR tồn tại
if [ ! -f "${DAR_PATH}" ]; then
  echo "🔨 Build lại project vì chưa có DAR..."
  cd "${PROJECT_NAME}"
  $DAML_BIN/daml build
fi

# 2.3 Start Canton Sandbox
if ! pgrep -f "$DAML_BIN/daml sandbox.*${DAR_PATH}" >/dev/null; then
  echo "🟢 Khởi chạy Canton sandbox..."
  nohup $DAML_BIN/daml sandbox --wall-clock-time --dar "${DAR_PATH}" \
    > sandbox.log 2>&1 &
  sleep 5
fi

# 2.4 Start JSON API
cat > $PROJECT_NAME/json-api-app.conf <<EOF
{
  server {
    address = "localhost"
    port = ${JSONAPI_PORT}
  }
  ledger-api {
    address = "localhost"
    port = ${SANDBOX_PORT}
  }
}
EOF

if ! pgrep -f "$DAML_BIN/daml json-api.*json-api-app.conf" >/dev/null; then
  echo "🟢 Khởi chạy JSON API..."
  nohup $DAML_BIN/daml json-api --config $PROJECT_NAME/json-api-app.conf \
    > jsonapi.log 2>&1 &
  sleep 5
fi

# 2.5 Export JWT cho Alice (actAs: "Alice")

# 2.6 Verify readiness
echo "🔎 Kiểm tra readiness..."
sleep 30
curl -s -X GET localhost:${JSONAPI_PORT}/readyz || true

# Step 3: Allocate party Alice (hoặc lấy lại nếu đã tồn tại)
echo "👤 Allocate party Alice..."
ALLOCATE=$(curl -s \
  -d '{"identifierHint":"Alice"}' \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ALICE_JWT" \
  -X POST localhost:${JSONAPI_PORT}/v1/parties/allocate)

echo $ALLOCATE
if echo "$ALLOCATE" | grep -q "Party already exists"; then
  echo "⚠️ Alice đã tồn tại, lấy lại party ID..."
  # Gọi API lấy danh sách parties
  PARTIES_JSON=$(curl -s \
    -H "Authorization: Bearer $ALICE_JWT" \
    localhost:${JSONAPI_PORT}/v1/parties)

  echo "Query: $PARTIES_JSON"

  # Lọc ra Alice::... và gán vào biến
  ALICE_PARTY_ID=$(echo "$PARTIES_JSON" | jq -r '.result[].identifier' | grep '^Alice::' | head -n1)
else
  ALICE_PARTY_ID=$(echo "$ALLOCATE" | jq -r '.result.identifier')
fi

echo "✅ Alice full party ID: $ALICE_PARTY_ID"

echo "STEP inspect package id"
PACKAGE_ID=$($DAML_BIN/daml damlc inspect-dar "${DAR_PATH}" --json | jq -r '.main_package_id')
echo "📦 PackageId: $PACKAGE_ID"

# Sinh JWT mới cho full party ID
HEADER='{"alg":"HS256","typ":"JWT"}'
PAYLOAD=$(cat <<EOF
{
  "https://daml.com/ledger-api": {
    "ledgerId": "sandbox",
    "applicationId": "HTTP-JSON-API-Gateway",
    "actAs": ["${ALICE_PARTY_ID}"]
  }
}
EOF
)

b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
HEADER_B64=$(echo -n "$HEADER" | b64url)
PAYLOAD_B64=$(echo -n "$PAYLOAD" | b64url)
SIGN_INPUT="${HEADER_B64}.${PAYLOAD_B64}"
SIGNATURE=$(echo -n "$SIGN_INPUT" | openssl dgst -binary -sha256 -hmac "$SECRET" | b64url)
ALICE_JWT="${SIGN_INPUT}.${SIGNATURE}"
export ALICE_JWT
echo "✅ JWT mới cho Alice: $ALICE_JWT"

# Tạo create.json
cat > $PROJECT_NAME/create.json <<EOF
{
  "templateId": "${PACKAGE_ID}:Main:Asset",
  "payload": {
    "issuer": "${ALICE_PARTY_ID}",
    "owner": "${ALICE_PARTY_ID}",
    "name": "Example Asset Name"
  }
}
EOF

# Submit contract creation
echo "📤 Submit contract creation..."
curl -s \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ALICE_JWT" \
  -d @$PROJECT_NAME/create.json \
  -X POST localhost:${JSONAPI_PORT}/v1/create | jq '.'

# Step 5: Query ledger
cat > $PROJECT_NAME/query.json <<EOF
{
  "templateIds": [
    "${PACKAGE_ID}:Main:Asset"
  ]
}
EOF

echo "🔎 Query ledger..."
curl -s \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ALICE_JWT" \
  -d @$PROJECT_NAME/query.json \
  -X POST localhost:${JSONAPI_PORT}/v1/query | jq '.'

echo "-----------------------------------------------------------------------"
echo "COPY CAU LENH SAU DE CHAY TREN TERMINAL MOI DE CHUP MAN HINH:"
echo "-----------------------------------------------------------------------"
echo 'cd /workspace/json-tests'
echo "ALICE_JWT='${ALICE_JWT}'"
echo "curl -s -H \"Content-Type: application/json\" -H \"Authorization: Bearer \$ALICE_JWT\" -d @query.json -X POST localhost:${JSONAPI_PORT}/v1/query | jq"

sleep 60