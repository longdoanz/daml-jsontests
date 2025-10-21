#!/usr/bin/env bash
set -euo pipefail

# Cấu hình
SDK_VERSION="3.3.0-snapshot.20250930.0"
PROJECT_DIR="capstone"
JSON_DIR="json"
SANDBOX_PORT=7575
SANDBOX_HOST="http://localhost:${SANDBOX_PORT}"


# # Start sandbox (nếu chưa có sandbox chạy)
# if ! curl -s "${SANDBOX_HOST}/docs/openapi" >/dev/null 2>&1; then
#   echo "==> Starting sandbox on port ${SANDBOX_PORT}..."
#   daml sandbox --json-api-port "${SANDBOX_PORT}" &
#   SANDBOX_PID=$!
#   trap 'echo "==> Stopping sandbox..."; kill ${SANDBOX_PID} 2>/dev/null || true; wait ${SANDBOX_PID} 2>/dev/null || true' EXIT
#   # Wait for sandbox ready
#   until curl -s "${SANDBOX_HOST}/docs/openapi" >/dev/null; do
#     echo "Waiting for sandbox to be ready..."
#     sleep 1
#   done
#   echo "Sandbox is up (PID=${SANDBOX_PID})!"
# else
#   echo "==> Sandbox already running."
#   SANDBOX_PID=""
# fi

cd "$PROJECT_DIR"
# Tạo thư mục json
mkdir -p $JSON_DIR

# Upload DAR
DAR_PATH=$(ls .daml/dist/*.dar | head -n1)
echo "==> Upload DAR: $DAR_PATH"
curl -v -X POST 'http://localhost:7575/v2/packages' \
  -H "Content-Type: application/octet-stream" \
  --data-binary @.daml/dist/quickstart-0.0.1.dar

sleep 5
# Allocate parties
echo "==> Allocating parties..."
PARTIES_OUT="${JSON_DIR}/parties.out.txt"
: > "$PARTIES_OUT"

allocate_party() {
  local hint="$1"
  local out="$2"
  # Gọi API, lưu response vào biến
  local resp
  resp=$(curl -s -d "{\"partyIdHint\":\"${hint}\",\"identityProviderId\":\"\"}" \
    -H "Content-Type: application/json" -X POST "${SANDBOX_HOST}/v2/parties")

  # Ghi response ra file và stdout
  printf '%s\n' "$resp" | tee "$out" >/dev/null

  # Extract party id một cách an toàn
  local party
  party=$(printf '%s\n' "$resp" | jq -r '.partyDetails.party // empty')

  if [ -z "$party" ]; then
    echo "ERROR: không lấy được party từ response. Response was:" >&2
    printf '%s\n' "$resp" >&2
    return 1
  fi

  printf '%s\n' "$party"
}

ALICE_JSON="${JSON_DIR}/alice.out.json"
BOB_JSON="${JSON_DIR}/bob.out.json"
USD_JSON="${JSON_DIR}/usd_bank.out.json"
EUR_JSON="${JSON_DIR}/eur_bank.out.json"

ALICE_ID=$(allocate_party "Alice5" "$ALICE_JSON")
echo "ALICE_ID=$ALICE_ID" | tee -a "$PARTIES_OUT"

BOB_ID=$(allocate_party "Bob5" "$BOB_JSON")
echo "BOB_ID=$BOB_ID" | tee -a "$PARTIES_OUT"

USD_BANK_ID=$(allocate_party "USD_Bank4" "$USD_JSON")
echo "USD_BANK_ID=$USD_BANK_ID" | tee -a "$PARTIES_OUT"

EUR_BANK_ID=$(allocate_party "EUR_Bank4" "$EUR_JSON")
echo "EUR_BANK_ID=$EUR_BANK_ID" | tee -a "$PARTIES_OUT"

# Get PACKAGE_ID using ALICE_ID
echo "==> Getting PACKAGE_ID..."
echo "ALICE_ID for package query: $ALICE_ID"
curl -s -X GET "${SANDBOX_HOST}/v2/interactive-submission/preferred-package-version?package-name=quickstart&parties=${ALICE_ID}" \
  | tee "${JSON_DIR}/pkg.out.json" | jq .
PACKAGE_ID=$(jq -r '.packagePreference.packageReference.packageId // .packageId // empty' "${JSON_DIR}/pkg.out.json")
if [ -z "$PACKAGE_ID" ]; then
  echo "ERROR: PACKAGE_ID not found in ${JSON_DIR}/pkg.out.json" >&2
  jq . "${JSON_DIR}/pkg.out.json" >&2
  exit 1
fi


# Build JSON payloads that don't require runtime values
cat > "${JSON_DIR}/issue_eur.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "CreateAndExerciseCommand": {
          "templateId": "${PACKAGE_ID}:Iou:Iou",
          "createArguments": {
            "issuer": "${EUR_BANK_ID}",
            "owner": "${EUR_BANK_ID}",
            "currency": "EUR",
            "amount": "100.0",
            "observers": []
          },
          "choice": "Iou_Transfer",
          "choiceArgument": { "newOwner": "${ALICE_ID}" }
        }
      }
    ],
    "userId": "eur-bank-user",
    "commandId": "issue-eur-to-alice-1",
    "actAs": [ "${EUR_BANK_ID}" ]
  }
}
EOF

cat > "${JSON_DIR}/issue_usd.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "CreateAndExerciseCommand": {
          "templateId": "${PACKAGE_ID}:Iou:Iou",
          "createArguments": {
            "issuer": "${USD_BANK_ID}",
            "owner": "${USD_BANK_ID}",
            "currency": "USD",
            "amount": "110.0",
            "observers": []
          },
          "choice": "Iou_Transfer",
          "choiceArgument": { "newOwner": "${BOB_ID}" }
        }
      }
    ],
    "userId": "usd-bank-user",
    "commandId": "issue-usd-to-bob-1",
    "actAs": [ "${USD_BANK_ID}" ]
  }
}
EOF

# Submit issue_eur and extract ALICE_TRANSFER_CID
echo "==> Submitting issue_eur.json..."
RESP_EUR=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" \
  -d @"${JSON_DIR}/issue_eur.json")

# Lưu response để debug
printf '%s\n' "$RESP_EUR" | jq . > "${JSON_DIR}/issue_eur.resp.json"

# Thử nhiều đường dẫn để tìm các events
ALICE_TRANSFER_CID=$(
  jq -r '
    # unify possible roots: .result.transaction or .transaction
    ( .result.transaction // .transaction ) as $tx
    | ($tx.events // [])[]
    # support both CreatedEvent and created lower-case shapes
    | ( .CreatedEvent? // .created? ) as $c
    | select($c != null)
    # prefer templateId that contains "Iou" (string), otherwise pass through
    | select(($c.templateId // "") | tostring | contains("Iou"))? 
    | $c.contractId
  ' "${JSON_DIR}/issue_eur.resp.json" | head -n1
)

# Fallback: nếu chưa có, lấy first created.contractId bất kể template
if [ -z "$ALICE_TRANSFER_CID" ]; then
  ALICE_TRANSFER_CID=$(
    jq -r '
      ( .result.transaction // .transaction ) as $tx
      | ($tx.events // [])[]
      | ( .CreatedEvent? // .created? ) as $c
      | select($c != null)
      | $c.contractId
    ' "${JSON_DIR}/issue_eur.resp.json" | head -n1
  )
fi

if [ -z "$ALICE_TRANSFER_CID" ]; then
  echo "ERROR: ALICE_TRANSFER_CID not found in ${JSON_DIR}/issue_eur.resp.json; inspect the file to see the exact event shape" >&2
  jq . "${JSON_DIR}/issue_eur.resp.json" >&2
  exit 1
fi

echo "ALICE_TRANSFER_CID=$ALICE_TRANSFER_CID" | tee -a "$PARTIES_OUT"


# Submit issue_usd and extract BOB_TRANSFER_CID
echo "==> Submitting issue_usd.json..."
RESP_USD=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" \
  -d @"${JSON_DIR}/issue_usd.json")

# Lưu response để debug
printf '%s\n' "$RESP_USD" | jq . > "${JSON_DIR}/issue_usd.resp.json"

# Thử nhiều đường dẫn, ưu tiên templateId chứa "Iou"
BOB_TRANSFER_CID=$(
  jq -r '
    ( .result.transaction // .transaction ) as $tx
    | ($tx.events // [])[]
    | ( .CreatedEvent? // .created? ) as $c
    | select($c != null)
    | select(($c.templateId // "") | tostring | contains("Iou"))?
    | $c.contractId
  ' "${JSON_DIR}/issue_usd.resp.json" | head -n1
)

# Fallback: lấy contractId đầu tiên của created events nếu chưa có
if [ -z "$BOB_TRANSFER_CID" ]; then
  BOB_TRANSFER_CID=$(
    jq -r '
      ( .result.transaction // .transaction ) as $tx
      | ($tx.events // [])[]
      | ( .CreatedEvent? // .created? ) as $c
      | select($c != null)
      | $c.contractId
    ' "${JSON_DIR}/issue_usd.resp.json" | head -n1
  )
fi

if [ -z "$BOB_TRANSFER_CID" ]; then
  echo "ERROR: BOB_TRANSFER_CID not found in ${JSON_DIR}/issue_usd.resp.json; saved response for inspection" >&2
  jq . "${JSON_DIR}/issue_usd.resp.json" >&2
  exit 1
fi

echo "BOB_TRANSFER_CID=$BOB_TRANSFER_CID" | tee -a "$PARTIES_OUT"

# Create alice_trf.json and bob_trf.json using extracted transfer CIDs
cat > "${JSON_DIR}/alice_trf.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "${PACKAGE_ID}:Iou:IouTransfer",
          "contractId": "${ALICE_TRANSFER_CID}",
          "choice": "IouTransfer_Accept",
          "choiceArgument": { }
        }
      }
    ],
    "userId": "alice-user",
    "commandId": "alice-accept-eur-transfer",
    "actAs": [ "${ALICE_ID}" ]
  }
}
EOF

cat > "${JSON_DIR}/bob_trf.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "${PACKAGE_ID}:Iou:IouTransfer",
          "contractId": "${BOB_TRANSFER_CID}",
          "choice": "IouTransfer_Accept",
          "choiceArgument": { }
        }
      }
    ],
    "userId": "bob-user",
    "commandId": "bob-accept-usd-transfer",
    "actAs": [ "${BOB_ID}" ]
  }
}
EOF

# Alice accepts and extract ALICE_ACCEPT_EUR
# Alice accepts and extract ALICE_ACCEPT_EUR
echo "==> Alice accepts EUR transfer..."
RESP_ALICE_ACCEPT=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" \
  -d @"${JSON_DIR}/alice_trf.json")
printf '%s\n' "$RESP_ALICE_ACCEPT" | jq . > "${JSON_DIR}/alice_accept.resp.json"

ALICE_ACCEPT_EUR=$(
  jq -r '
    ( .result.transaction // .transaction ) as $tx
    | ($tx.events // [])[]
    | ( .CreatedEvent? // .created? ) as $c
    | select($c != null)
    | select(($c.templateId // "") | tostring | contains("Iou"))?
    | $c.contractId
  ' "${JSON_DIR}/alice_accept.resp.json" | head -n1
)

if [ -z "$ALICE_ACCEPT_EUR" ]; then
  ALICE_ACCEPT_EUR=$(
    jq -r '
      ( .result.transaction // .transaction ) as $tx
      | ($tx.events // [])[]
      | ( .CreatedEvent? // .created? ) as $c
      | select($c != null)
      | $c.contractId
    ' "${JSON_DIR}/alice_accept.resp.json" | head -n1
  )
fi

if [ -z "$ALICE_ACCEPT_EUR" ]; then
  echo "ERROR: ALICE_ACCEPT_EUR not found in ${JSON_DIR}/alice_accept.resp.json; inspect the file" >&2
  jq . "${JSON_DIR}/alice_accept.resp.json" >&2
  exit 1
fi
echo "ALICE_ACCEPT_EUR=$ALICE_ACCEPT_EUR" | tee -a "$PARTIES_OUT"

# Bob accepts and extract BOB_ACCEPT_USD and LATEST_OFFSET
echo "==> Bob accepts USD transfer..."
RESP_BOB_ACCEPT=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" \
  -d @"${JSON_DIR}/bob_trf.json")
printf '%s\n' "$RESP_BOB_ACCEPT" | jq . > "${JSON_DIR}/bob_accept.resp.json"

BOB_ACCEPT_USD=$(
  jq -r '
    ( .result.transaction // .transaction ) as $tx
    | ($tx.events // [])[]
    | ( .CreatedEvent? // .created? ) as $c
    | select($c != null)
    | select(($c.templateId // "") | tostring | contains("Iou"))?
    | $c.contractId
  ' "${JSON_DIR}/bob_accept.resp.json" | head -n1
)

if [ -z "$BOB_ACCEPT_USD" ]; then
  BOB_ACCEPT_USD=$(
    jq -r '
      ( .result.transaction // .transaction ) as $tx
      | ($tx.events // [])[]
      | ( .CreatedEvent? // .created? ) as $c
      | select($c != null)
      | $c.contractId
    ' "${JSON_DIR}/bob_accept.resp.json" | head -n1
  )
fi

LATEST_OFFSET=$(jq -r '(.result.transaction.offset // .transaction.offset) // empty' "${JSON_DIR}/bob_accept.resp.json")

if [ -z "$BOB_ACCEPT_USD" ] || [ -z "$LATEST_OFFSET" ]; then
  echo "ERROR: BOB_ACCEPT_USD or LATEST_OFFSET not found in ${JSON_DIR}/bob_accept.resp.json; inspect the file" >&2
  jq . "${JSON_DIR}/bob_accept.resp.json" >&2
  exit 1
fi

echo "BOB_ACCEPT_USD=$BOB_ACCEPT_USD" | tee -a "$PARTIES_OUT"
echo "LATEST_OFFSET=$LATEST_OFFSET" | tee -a "$PARTIES_OUT"


# Build acs.json using LATEST_OFFSET
cat > "${JSON_DIR}/acs.json" <<EOF
{
  "filter": {
    "filtersByParty": {
      "${ALICE_ID}": {
        "cumulative": [
          {
            "identifierFilter": {
              "TemplateFilter": {
                "value": {
                  "templateId": "${PACKAGE_ID}:Iou:Iou",
                  "includeCreatedEventBlob": true
                }
              }
            }
          }
        ]
      },
      "${BOB_ID}": {
        "cumulative": [
          {
            "identifierFilter": {
              "TemplateFilter": {
                "value": {
                  "templateId": "${PACKAGE_ID}:Iou:Iou",
                  "includeCreatedEventBlob": true
                }
              }
            }
          }
        ]
      }
    }
  },
  "verbose": true,
  "activeAtOffset": "${LATEST_OFFSET}"
}
EOF

echo "==> Querying ACS (active contracts) at offset ${LATEST_OFFSET}..."
curl -s -X POST "${SANDBOX_HOST}/v2/state/active-contracts" \
  -H "Content-Type: application/json" -d @"${JSON_DIR}/acs.json" | jq . > "${JSON_DIR}/acs.resp.json"

# Robust extraction: search anywhere for contract.contractId whose signatories contain EUR_BANK_ID or ALICE_ID
# Robust extraction for array-of-entries shape
NEW_IOU=$(
  jq -r '
    # handle top-level array of entries
    .[]?
    # find createdEvent under possible shapes and return contractId
    | ( .contractEntry?.JsActiveContract?.createdEvent
        // .contractEntry?.createdEvent
        // .contractEntry?.contract?.createdEvent
        // .createdEvent
        // .CreatedEvent
      ) as $c
    | select($c != null)
    | $c.contractId
  ' "${JSON_DIR}/acs.resp.json" \
  | head -n1
)

# Fallbacks for other common shapes
if [ -z "$NEW_IOU" ]; then
  NEW_IOU=$(
    jq -r '
      # try .contractEntries[].contract.contractId or other common shapes
      (.contractEntries?[]?.contract?.contractId
       // .contracts?[]?.contractId
       // (.. | objects | .createdEvent? // .CreatedEvent? | .contractId)
      ) as $x
      | select($x != null)
      | $x
    ' "${JSON_DIR}/acs.resp.json" \
    | head -n1
  )
fi

if [ -z "$NEW_IOU" ]; then
  echo "ERROR: NEW_IOU not found in ACS response; inspect ${JSON_DIR}/acs.resp.json" >&2
  jq . "${JSON_DIR}/acs.resp.json" >&2
  exit 1
fi

echo "NEW_IOU=$NEW_IOU" | tee -a "$PARTIES_OUT"

# add_observer.json (Alice adds Bob as observer on her EUR IOU)
cat > "${JSON_DIR}/add_observer.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "${PACKAGE_ID}:Iou:Iou",
          "contractId": "${ALICE_ACCEPT_EUR}",
          "choice": "Iou_AddObserver",
          "choiceArgument": { "newObserver": "${BOB_ID}" }
        }
      }
    ],
    "userId": "alice-user",
    "commandId": "iou-disclosure-split-1",
    "actAs": [ "${ALICE_ID}" ]
  }
}
EOF

echo "==> Submitting add_observer..."
RESP_ADD_OBS=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" -d @"${JSON_DIR}/add_observer.json")
echo "$RESP_ADD_OBS" | jq . > "${JSON_DIR}/add_observer.resp.json"
# Thử nhiều đường dẫn: .result.transaction hoặc .transaction; hỗ trợ CreatedEvent (PascalCase) và created (camelCase)
NEW_IOU_FROM_ADD=$(
  jq -r '
    ( .result.transaction // .transaction ) as $tx
    | ($tx.events // [])[]
    | ( .CreatedEvent? // .created? ) as $c
    | select($c != null)
    | select( (($c.templateId // "") | tostring | contains("Iou")) or ($c.packageName? != null) )?
    | $c.contractId
  ' "${JSON_DIR}/add_observer.resp.json" | head -n1
)

# Fallback: nếu không có created event, thử lấy contractId từ exercises hoặc từ các field archive/consumed nếu cần
if [ -z "$NEW_IOU_FROM_ADD" ]; then
  NEW_IOU_FROM_ADD=$(
    jq -r '
      ( .result.transaction // .transaction ) as $tx
      | ($tx.events // [])[]
      | ( .CreatedEvent? // .created? // .exercised? // .archived? ) as $e
      | select($e != null)
      | ($e.contractId // $e.contract?.contractId // empty)
    ' "${JSON_DIR}/add_observer.resp.json" | head -n1
  )
fi

if [ -z "$NEW_IOU_FROM_ADD" ]; then
  echo "ERROR: NEW_IOU_FROM_ADD not found in ${JSON_DIR}/add_observer.resp.json; inspect the file for actual event shape" >&2
  jq . "${JSON_DIR}/add_observer.resp.json" >&2
  exit 1
fi

echo "NEW_IOU=$NEW_IOU_FROM_ADD" | tee -a "$PARTIES_OUT"

# propose_trade.json (Alice proposes trade)
cat > "${JSON_DIR}/propose_trade.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "CreateCommand": {
          "templateId": "${PACKAGE_ID}:IouTrade:IouTrade",
          "createArguments": {
            "buyer": "${ALICE_ID}",
            "seller": "${BOB_ID}",
            "baseIouCid": "${NEW_IOU_FROM_ADD}",
            "baseIssuer": "${EUR_BANK_ID}",
            "baseCurrency": "EUR",
            "baseAmount": "100.0",
            "quoteIssuer": "${USD_BANK_ID}",
            "quoteCurrency": "USD",
            "quoteAmount": "110.0"
          }
        }
      }
    ],
    "userId": "alice-user",
    "commandId": "trade-proposal-1",
    "actAs": [ "${ALICE_ID}" ]
  }
}
EOF

echo "==> Submitting trade proposal..."
RESP_PROPOSE=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" -d @"${JSON_DIR}/propose_trade.json")
echo "$RESP_PROPOSE" | jq . > "${JSON_DIR}/propose_trade.resp.json"
# Thử nhiều đường dẫn: .result.transaction hoặc .transaction; CreatedEvent (PascalCase) hoặc created (camelCase)
TRADE_PROPOSAL_CID=$(
  jq -r '
    ( .result.transaction // .transaction ) as $tx
    | ($tx.events // [])[]
    | ( .CreatedEvent? // .created? ) as $c
    | select($c != null)
    | select( (($c.templateId // "") | tostring | contains("IouTrade")) or (($c.packageName // "") | tostring | contains("quickstart")) )?
    | $c.contractId
  ' "${JSON_DIR}/propose_trade.resp.json" | head -n1
)

# Fallback: lấy bất kỳ created contractId đầu tiên
if [ -z "$TRADE_PROPOSAL_CID" ]; then
  TRADE_PROPOSAL_CID=$(
    jq -r '
      ( .result.transaction // .transaction ) as $tx
      | ($tx.events // [])[]
      | ( .CreatedEvent? // .created? ) as $c
      | select($c != null)
      | $c.contractId
    ' "${JSON_DIR}/propose_trade.resp.json" | head -n1
  )
fi

# Nếu vẫn rỗng, in ra thông tin hữu ích để debug
if [ -z "$TRADE_PROPOSAL_CID" ]; then
  echo "ERROR: TRADE_PROPOSAL_CID not found; inspect ${JSON_DIR}/propose_trade.resp.json" >&2
  echo "---- Full response ----" >&2
  jq . "${JSON_DIR}/propose_trade.resp.json" >&2
  echo "---- Events summary (types and contractIds) ----" >&2
  jq -r '(.result.transaction // .transaction) as $tx | ($tx.events // [])[] | keys[] as $k | "\($k): \((.[$k].contractId // .[$k].created?.contractId // .[$k].createdEvent?.contractId) // \"(no id)\")"' "${JSON_DIR}/propose_trade.resp.json" >&2 || true
  echo "Check: - ensure propose_trade.json is a CreateCommand for IouTrade; - ensure commandId is unique; - inspect whether API returned warnings/errors." >&2
  exit 1
fi

echo "TRADE_PROPOSAL_CID=$TRADE_PROPOSAL_CID" | tee -a "$PARTIES_OUT"

# accept_trade.json (Bob accepts proposal)
cat > "${JSON_DIR}/accept_trade.json" <<EOF
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "${PACKAGE_ID}:IouTrade:IouTrade",
          "contractId": "${TRADE_PROPOSAL_CID}",
          "choice": "IouTrade_Accept",
          "choiceArgument": { "quoteIouCid": "${BOB_ACCEPT_USD}" }
        }
      }
    ],
    "userId": "bob-user",
    "commandId": "trade-acceptance-1",
    "actAs": [ "${BOB_ID}" ]
  }
}
EOF

echo "==> Bob accepting trade (this will perform the atomic swap)..."
RESP_ACCEPT_TRADE=$(curl -s -X POST "${SANDBOX_HOST}/v2/commands/submit-and-wait-for-transaction" \
  -H "Content-Type: application/json" -d @"${JSON_DIR}/accept_trade.json")
echo "$RESP_ACCEPT_TRADE" | jq . > "${JSON_DIR}/accept_trade.resp.json"

echo "==> Trade response saved to ${JSON_DIR}/accept_trade.resp.json"
echo "==> Các giá trị chính đã được lưu vào ${PARTIES_OUT}:"
cat "$PARTIES_OUT"

# Nếu script tự start sandbox thì trap sẽ tắt nó khi kết thúc
if [ -n "${SANDBOX_PID:-}" ]; then
  echo "==> Kết thúc: sandbox sẽ được tắt nhờ trap khi script exit."
else
  echo "==> Lưu ý: sandbox không do script khởi động, không tắt tự động."
fi

# Kết thúc thành công
echo "==> Hoàn tất kịch bản tự động hóa các bước của hướng dẫn."
