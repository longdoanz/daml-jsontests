# # Build DAR
cd capstone
echo "==> Building DAR..."
~/.daml/bin/daml build

echo "🛑 Dừng tất cả tiến trình daml cũ..."
pkill -f daml || true
~/.daml/bin/daml sandbox --json-api-port 7575
