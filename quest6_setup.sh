#!/usr/bin/env bash
set -euo pipefail

# Cấu hình
SDK_VERSION="3.3.0-snapshot.20250930.0"
PROJECT_DIR="capstone"
JSON_DIR="json"
SANDBOX_PORT=7575
SANDBOX_HOST="http://localhost:${SANDBOX_PORT}"

# Cài Daml SDK (nếu cần)
echo "==> Installing Daml SDK ${SDK_VERSION}..."
curl -sSL https://get.daml.com/ | sh -s "${SDK_VERSION}"

~/.daml/bin/daml new $PROJECT_DIR --template quickstart-java

# # # Vào thư mục dự án
# cd "$PROJECT_DIR"

# # Build DAR
# echo "==> Building DAR..."
# ~/.daml/bin/daml build
# ~/.daml/bin/daml sandbox --json-api-port 7575
