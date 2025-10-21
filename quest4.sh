#!/bin/bash
# Quest 4 automation script: Your First Smart Contract on Canton

set -e

# 1. Khởi tạo project mới
PROJECT_NAME="../intro1"
if [ -d "$PROJECT_NAME" ]; then
  echo "Thư mục $PROJECT_NAME đã tồn tại, bỏ qua bước khởi tạo."
else
  daml new $PROJECT_NAME --template daml-intro-1
fi

cd $PROJECT_NAME

# 2. Ghi đè file Token.daml với nội dung yêu cầu
cat > daml/Token.daml <<'EOF'
module Token where

import Daml.Script

template Token
  with
    owner : Party
  where
    signatory owner

token_test_1 = script do
  alice <- allocateParty "Alice"
  submit alice do
    createCmd Token with owner = alice

token_test_2 = script do
  alice <- allocateParty "Alice"
  bob   <- allocateParty "Bob"

  submitMustFail alice do
    createCmd Token with owner = bob
  submitMustFail bob   do
    createCmd Token with owner = alice

  submit alice do
    createCmd Token with owner = alice
  submit bob   do
    createCmd Token with owner = bob

token_archive_exercise = script do
  alice <- allocateParty "Alice"
  alice_token_cid <- submit alice do
    createCmd Token with owner = alice
  submit alice do
    archiveCmd alice_token_cid
EOF

# 3. Thêm dependency daml-script vào daml.yaml nếu chưa có
if ! grep -q "daml-script" daml.yaml; then
  echo "  - daml-script" >> daml.yaml
fi

# 4. Build project
daml build

# 5. Chạy test
daml test --files daml/Token.daml
