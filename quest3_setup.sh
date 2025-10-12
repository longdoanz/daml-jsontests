#!/usr/bin/env bash
set -euo pipefail

# ================
# Config cơ bản
# ================
DAML_VERSION="2.10.2"
PROJECT_NAME="json-tests"
SANDBOX_PORT=6865
JSONAPI_PORT=7575
NAVIGATOR_PORT=7500
DAML_BIN="$HOME/.daml/bin"

echo "🚀 Bắt đầu thiết lập Quest 3 trong GitHub Codespaces..."

# ================
# Bước 1: Cài đặt Daml SDK và tool thiết yếu
# ================
# Theo hướng dẫn: cài Daml SDK 2.10.2 và thêm PATH; cài OpenJDK, jq
if ! command -v $DAML_BIN/daml >/dev/null 2>&1; then
  echo "📦 Cài đặt Daml SDK ${DAML_VERSION}..."
  curl -sSL https://get.daml.com/ | bash -s -- $DAML_VERSION
  # Thêm PATH (Codespaces user thường là /home/codespace)
  if ! grep -q "$DAML_BIN" "$HOME/.bashrc"; then
    echo "export PATH=\"$DAML_BIN:\$PATH\"" >> "$HOME/.bashrc"
  fi
  # Áp dụng ngay
  source "$HOME/.bashrc"
else
  echo "✅ Daml SDK đã có sẵn."
fi

echo "🧪 Kiểm tra phiên bản Daml..."
$DAML_BIN/daml version

# Kiểm tra jq
if ! command -v jq >/dev/null 2>&1; then
  echo "📦 Cài đặt jq..."
  sudo apt-get install -y jq
else
  echo "✅ jq đã có sẵn."
fi

echo "📦 Cài đặt Azul Zulu JDK và jq..."

# Kiểm tra Java (Zulu JDK)
if ! java -version >/dev/null 2>&1; then
  echo "📦 Chưa có Java, tiến hành cài Azul Zulu JDK..."

  # Import key của Azul (chỉ import nếu chưa có file key)
  if [ ! -f /usr/share/keyrings/azul.gpg ]; then
    curl -s https://repos.azul.com/azul-repo.key | sudo gpg --dearmor -o /usr/share/keyrings/azul.gpg
  fi

  # Thêm repo Azul (chỉ thêm nếu chưa tồn tại)
  if [ ! -f /etc/apt/sources.list.d/zulu.list ]; then
    echo "deb [signed-by=/usr/share/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" \
      | sudo tee /etc/apt/sources.list.d/zulu.list
  fi

  # Update lại danh sách package
  sudo apt-get update -y

  # Cài đặt Zulu JDK (ví dụ JDK 21, bạn có thể đổi sang 17 hoặc 11 nếu muốn)
  sudo apt-get install -y zulu21-ca-jdk

  echo "✅ Đã cài đặt Azul Zulu JDK."
else
  echo "✅ Java (Zulu JDK) đã có sẵn."
fi

# Kiểm tra cài đặt
java -version


# ================
# Bước 2: Tạo model, build, khởi chạy Sandbox + JSON API
# ================
if [ ! -d "${PROJECT_NAME}" ]; then
  echo "📂 Tạo project Daml mẫu: ${PROJECT_NAME}..."
  $DAML_BIN/daml new "${PROJECT_NAME}"   # theo step 2.1
fi

cd "${PROJECT_NAME}"

echo "🔨 Build Daml model..."
$DAML_BIN/daml build                      # theo step 2.2

DAR_PATH="./.daml/dist/${PROJECT_NAME}-0.0.1.dar"
if [ ! -f "${DAR_PATH}" ]; then
  echo "❌ Không tìm thấy DAR tại ${DAR_PATH}"
  exit 1
fi

# Tạo config JSON API theo step 2.4
cat > json-api-app.conf <<EOF
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