#!/bin/bash
# Quest 6 full automation script

set -e
PROJECT_NAME="capstone"

# 1. Tạo project nếu chưa có
if [ ! -d "$PROJECT_NAME" ]; then
  daml new $PROJECT_NAME --template quickstart-java
fi
cd $PROJECT_NAME

# 2. Build DAR
daml build
DAR_FILE=$(ls .daml/dist/*.dar | head -n1)

# 3. Upload DAR
curl -s -X POST 'http://localhost:7575/v2/packages' \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$DAR_FILE" | jq .

# 4. Allocate parties
PARTY_FILE="party_ids.json"
echo "{}" > $PARTY_FILE
for PARTY in Alice Bob USD_Bank EUR_Bank; do
  RESP=$(curl -s -d "{\"partyIdHint\":\"$PARTY\", \"identityProviderId\": \"\"}" \
    -H "Content-Type: application/json" \
    -X POST localhost:7575/v2/parties)
  PARTY_ID=$(echo $RESP | jq -r '.partyDetails.party')
  jq --arg k "$PARTY" --arg v "$PARTY_ID" '. + {($k): $v}' $PARTY_FILE > tmp.$$.json && mv tmp.$$.json $PARTY_FILE
done

# 5. Lấy Package ID
ALICE_ID=$(jq -r '.Alice' $PARTY_FILE)
PACKAGE_ID=$(curl -s -X GET "http://localhost:7575/v2/interactive-submission/preferred-package-version?package-name=quickstart&parties=$ALICE_ID" | jq -r '.packageId')
jq --arg pkg "$PACKAGE_ID" '. + {"PACKAGE_ID": $pkg}' $PARTY_FILE > tmp.$$.json && mv tmp.$$.json $PARTY_FILE

# 6. Issue EUR IOU cho Alice
EUR_BANK=$(jq -r '.EUR_Bank' $PARTY_FILE)
ISSUE_EUR=$(jq -n --arg pkg "$PACKAGE_ID" --arg bank "$EUR_BANK" --arg alice "$ALICE_ID" '{
  commands:{commands:[{CreateAndExerciseCommand:{
    templateId:($pkg+":Iou:Iou"),
    createArguments:{issuer:$bank, owner:$bank, currency:"EUR", amount:"100.0", observers:[]},
    choice:"Iou_Transfer", choiceArgument:{newOwner:$alice}}}],
    userId:"eur-bank-user", commandId:"issue-eur", actAs:[$bank]}}')
EUR_RESP=$(echo $ISSUE_EUR | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)
ALICE_TRF_CID=$(echo $EUR_RESP | jq -r '.transaction.events[0].created.contractId')

# 7. Issue USD IOU cho Bob
BOB_ID=$(jq -r '.Bob' $PARTY_FILE)
USD_BANK=$(jq -r '.USD_Bank' $PARTY_FILE)
ISSUE_USD=$(jq -n --arg pkg "$PACKAGE_ID" --arg bank "$USD_BANK" --arg bob "$BOB_ID" '{
  commands:{commands:[{CreateAndExerciseCommand:{
    templateId:($pkg+":Iou:Iou"),
    createArguments:{issuer:$bank, owner:$bank, currency:"USD", amount:"110.0", observers:[]},
    choice:"Iou_Transfer", choiceArgument:{newOwner:$bob}}}],
    userId:"usd-bank-user", commandId:"issue-usd", actAs:[$bank]}}')
USD_RESP=$(echo $ISSUE_USD | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)
BOB_TRF_CID=$(echo $USD_RESP | jq -r '.transaction.events[0].created.contractId')

# 8. Alice accept transfer
ACCEPT_ALICE=$(jq -n --arg pkg "$PACKAGE_ID" --arg cid "$ALICE_TRF_CID" --arg alice "$ALICE_ID" '{
  commands:{commands:[{ExerciseCommand:{
    templateId:($pkg+":Iou:IouTransfer"), contractId:$cid,
    choice:"IouTransfer_Accept", choiceArgument:{}}}],
    userId:"alice-user", commandId:"alice-accept", actAs:[$alice]}}')
ALICE_RESP=$(echo $ACCEPT_ALICE | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)
ALICE_IOU=$(echo $ALICE_RESP | jq -r '.transaction.events[] | select(.created).created.contractId')

# 9. Bob accept transfer
ACCEPT_BOB=$(jq -n --arg pkg "$PACKAGE_ID" --arg cid "$BOB_TRF_CID" --arg bob "$BOB_ID" '{
  commands:{commands:[{ExerciseCommand:{
    templateId:($pkg+":Iou:IouTransfer"), contractId:$cid,
    choice:"IouTransfer_Accept", choiceArgument:{}}}],
    userId:"bob-user", commandId:"bob-accept", actAs:[$bob]}}')
BOB_RESP=$(echo $ACCEPT_BOB | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)
BOB_IOU=$(echo $BOB_RESP | jq -r '.transaction.events[] | select(.created).created.contractId')

# 10. Alice add Bob observer
ADD_OBS=$(jq -n --arg pkg "$PACKAGE_ID" --arg cid "$ALICE_IOU" --arg alice "$ALICE_ID" --arg bob "$BOB_ID" '{
  commands:{commands:[{ExerciseCommand:{
    templateId:($pkg+":Iou:Iou"), contractId:$cid,
    choice:"Iou_AddObserver", choiceArgument:{newObserver:$bob}}}],
    userId:"alice-user", commandId:"add-obs", actAs:[$alice]}}')
OBS_RESP=$(echo $ADD_OBS | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)
NEW_IOU=$(echo $OBS_RESP | jq -r '.transaction.events[] | select(.created).created.contractId')

# 11. Alice propose trade
PROPOSE=$(jq -n --arg pkg "$PACKAGE_ID" --arg alice "$ALICE_ID" --arg bob "$BOB_ID" --arg newiou "$NEW_IOU" --arg eur "$EUR_BANK" --arg usd "$USD_BANK" '{
  commands:{commands:[{CreateCommand:{
    templateId:($pkg+":IouTrade:IouTrade"),
    createArguments:{buyer:$alice, seller:$bob, baseIouCid:$newiou,
      baseIssuer:$eur, baseCurrency:"EUR", baseAmount:"100.0",
      quoteIssuer:$usd, quoteCurrency:"USD", quoteAmount:"110.0"}}}],
    userId:"alice-user", commandId:"propose-trade", actAs:[$alice]}}')
PROP_RESP=$(echo $PROPOSE | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)
TRADE_CID=$(echo $PROP_RESP | jq -r '.transaction.events[] | select(.created).created.contractId')

# 12. Bob accept trade
ACCEPT_TRADE=$(jq -n --arg pkg "$PACKAGE_ID" --arg cid "$TRADE_CID" --arg bob "$BOB_ID" --arg bobiou "$BOB_IOU" '{
  commands:{commands:[{ExerciseCommand:{
    templateId:($pkg+":IouTrade:IouTrade"), contractId:$cid,
    choice:"IouTrade_Accept", choiceArgument:{quoteIouCid:$bobiou}}}],
    userId:"bob-user", commandId:"accept-trade", actAs:[$bob]}}')
FINAL=$(echo $ACCEPT_TRADE | curl -s -X POST 'http://localhost:7575/v2/commands/submit-and-wait-for-transaction' -H "Content-Type: application/json" -d @-)

echo "=== Quest 6 completed successfully ==="
echo "===== FINAL TRADE RESULT ====="
echo $FINAL | jq .
