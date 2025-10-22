# # Build DAR
echo "==> Building DAR..."
~/.daml/bin/daml build
~/.daml/bin/daml sandbox --json-api-port 7575