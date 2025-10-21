#!/usr/bin/env bash
set -euo pipefail

# Thư mục làm việc (giả định đã `daml new capstone --template quickstart-java` trước đó)
PROJECT_DIR="./capstone"
cd "$PROJECT_DIR"

echo "==> Nhắc lại: hãy chạy 'daml sandbox --json-api-port 7575' ở terminal khác trước khi tiếp tục."

# 0. Build DAR (tham chiếu hướng dẫn Step 2)
echo "==> Building DAR..."
daml build

daml sandbox --json-api-port 7575 &
SANDBOX_PID=$!

# 2. Wait until sandbox is ready
echo "==> Starting sandbox (PID=$SANDBOX_PID)..."
until curl -s localhost:7575/docs/openapi > /dev/null; do
  echo "Waiting for sandbox to be ready..."
  sleep 2
done
echo "Sandbox is up!"

# 1. Upload DAR (Step 5.2)
DAR_PATH=$(ls .daml/dist/*.dar | head -n1)
echo "==> Upload DAR: $DAR_PATH"
curl -v -X POST 'http://localhost:7575/v2/packages' \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$DAR_PATH"

# 2. Allocate parties (Step 5.3)
echo "==> Allocating parties..."
mkdir -p json
PARTIES_OUT="json/parties.out.txt"

echo "Alice:"
curl -s -d '{"partyIdHint":"Alice","identityProviderId":""}' \
  -H "Content-Type: application/json" -X POST localhost:7575/v2/parties | tee "json/alice.out.json"
ALICE_ID=$(jq -r '.partyDetails.party' json/alice.out.json)
echo "ALICE_ID=$ALICE_ID" | tee -a "$PARTIES_OUT"

echo "Bob:"
curl -s -d '{"partyIdHint":"Bob","identityProviderId":""}' \
  -H "Content-Type: application/json" -X POST localhost:7575/v2/parties | tee "json/bob.out.json"
BOB_ID=$(jq -r '.partyDetails.party' json/bob.out.json)
echo "BOB_ID=$BOB_ID" | tee -a "$PARTIES_OUT"

echo "USD_Bank:"
curl -s -d '{"partyIdHint":"USD_Bank","identityProviderId":""}' \
  -H "Content-Type: application/json" -X POST localhost:7575/v2/parties | tee "json/usd_bank.out.json"
USD_BANK_ID=$(jq -r '.partyDetails.party' json/usd_bank.out.json)
echo "USD_BANK_ID=$USD_BANK_ID" | tee -a "$PARTIES_OUT"

echo "EUR_Bank:"
curl -s -d '{"partyIdHint":"EUR_Bank","identityProviderId":""}' \
  -H "Content-Type: application/json" -X POST localhost:7575/v2/parties | tee "json/eur_bank.out.json"
EUR_BANK_ID=$(jq -r '.partyDetails.party' json/eur_bank.out.json)
echo "EUR_BANK_ID=$EUR_BANK_ID" | tee -a "$PARTIES_OUT"

echo "==> Parties saved to $PARTIES_OUT"

# 3. Lấy PACKAGE_ID (Step 5.4)
echo "==> Getting PACKAGE_ID (using ALICE_ID)..."
curl -s -X GET "http://localhost:7575/v2/interactive-submission/preferred-package-version?package-name=quickstart&parties=${ALICE_ID}" \
  | tee "json/pkg.out.json" | jq .
PACKAGE_ID=$(jq -r '.packageId' json/pkg.out.json)
echo "PACKAGE_ID=$PACKAGE_ID" | tee -a "$PARTIES_OUT"

# 4. Tạo các file JSON theo Step 6 và Step 7

# 4.1 issue_eur.json (Step 6.1)
cat > json/issue_eur.json <<EOF
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

# 4.2 issue_usd.json (Step 6.2)
cat > json/issue_usd.json <<EOF
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

# 4.3 alice_trf.json (Step 6.3) - cần ALICE_TRANSFER_CID sau khi chạy issue_eur
# placeholder tạm, sẽ thay bằng jq sau khi submit
cat > json/alice_trf.json <<'EOF'
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "<PACKAGE_ID>:Iou:IouTransfer",
          "contractId": "<ALICE_TRANSFER_CID>",
          "choice": "IouTransfer_Accept",
          "choiceArgument": { }
        }
      }
    ],
    "userId": "alice-user",
    "commandId": "alice-accept-eur-transfer",
    "actAs": [ "<ALICE_ID>" ]
  }
}
EOF

# 4.4 bob_trf.json (Step 6.4) - cần BOB_TRANSFER_CID sau khi chạy issue_usd
cat > json/bob_trf.json <<'EOF'
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "<PACKAGE_ID>:Iou:IouTransfer",
          "contractId": "<BOB_TRANSFER_CID>",
          "choice": "IouTransfer_Accept",
          "choiceArgument": { }
        }
      }
    ],
    "userId": "bob-user",
    "commandId": "bob-accept-usd-transfer",
    "actAs": [ "<BOB_ID>" ]
  }
}
EOF

# 4.5 acs.json (Step 7.1) - cần LATEST_OFFSET từ bước 6.4
cat > json/acs.json <<'EOF'
{
  "filter": {
    "filtersByParty": {
      "<ALICE_ID>": {
        "cumulative": [
          {
            "identifierFilter": {
              "TemplateFilter": {
                "value": {
                  "templateId": "<PACKAGE_ID>:Iou:Iou",
                  "includeCreatedEventBlob": true
                }
              }
            }
          }
        ]
      },
      "<BOB_ID>": {
        "cumulative": [
          {
            "identifierFilter": {
              "TemplateFilter": {
                "value": {
                  "templateId": "<PACKAGE_ID>:Iou:Iou",
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
  "activeAtOffset": "<LATEST_OFFSET>"
}
EOF

# 4.6 add_observer.json (Step 7.2) - cần ALICE_ACCEPT_EUR sau bước 6.3
cat > json/add_observer.json <<'EOF'
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "<PACKAGE_ID>:Iou:Iou",
          "contractId": "<ALICE_ACCEPT_EUR>",
          "choice": "Iou_AddObserver",
          "choiceArgument": { "newObserver": "<BOB_ID>" }
        }
      }
    ],
    "userId": "alice-user",
    "commandId": "iou-disclosure-split-1",
    "actAs": [ "<ALICE_ID>" ]
  }
}
EOF

# 4.7 propose_trade.json (Step 7.3) - cần NEW_IOU từ bước 7.2
cat > json/propose_trade.json <<'EOF'
{
  "commands": {
    "commands": [
      {
        "CreateCommand": {
          "templateId": "<PACKAGE_ID>:IouTrade:IouTrade",
          "createArguments": {
            "buyer": "<ALICE_ID>",
            "seller": "<BOB_ID>",
            "baseIouCid": "<NEW_IOU>",
            "baseIssuer": "<EUR_BANK_ID>",
            "baseCurrency": "EUR",
            "baseAmount": "100.0",
            "quoteIssuer": "<USD_BANK_ID>",
            "quoteCurrency": "USD",
            "quoteAmount": "110.0"
          }
        }
      }
    ],
    "userId": "alice-user",
    "commandId": "trade-proposal-1",
    "actAs": [ "<ALICE_ID>" ]
  }
}
EOF

# 4.8 accept_trade.json (Step 7.4) - cần TRADE_PROPOSAL_CID & BOB_ACCEPT_USD
cat > json/accept_trade.json <<'EOF'
{
  "commands": {
    "commands": [
      {
        "ExerciseCommand": {
          "templateId": "<PACKAGE_ID>:IouTrade:IouTrade",
          "contractId": "<TRADE_PROPOSAL_CID>",
          "choice": "IouTrade_Accept",
          "choiceArgument": { "quoteIouCid": "<BOB_ACCEPT_USD>" }
        }
      }
    ],
    "userId": "bob-user",
    "commandId": "trade-acceptance-1",
    "actAs": [ "<BOB_ID>" ]
  }
}
EOF

echo "==> Các file JSON đã tạo trong thư mục ./capstone/json"
echo "==> Tiếp tục chạy các lệnh curl theo thứ tự ở dưới để lấy các CID & offset và thay thế placeholders."


sleep 10
# 7. Shutdown sandbox at the end
echo "==> Stopping sandbox..."
kill $SANDBOX_PID
wait $SANDBOX_PID 2>/dev/null || true
echo "Sandbox stopped."