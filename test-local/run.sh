#!/bin/bash
# Test the GitHub Action locally using 'act'
# Prerequisites: act, docker, .env file with credentials
#
# Usage:
#   cd cli/
#   ./integrations/github-action/test-local/run.sh
#
# Required env vars (in cli/.env or passed via env):
#   PURPLEMET_API_TOKEN   — API token
#   PURPLEMET_TARGET_URL  — URL to analyze (e.g. https://your-app.example.com)
#   PURPLEMET_BASE_URL    — API base URL (e.g. https://api.dev.purplemet.com)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

cd "${CLI_DIR}"

echo "==> Building purplemet-cli for linux/amd64 (act runs in Docker)..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-s -w" -o purplemet-cli .
echo "    Binary built: $(file purplemet-cli)"

# Load .env if exists
if [ -f .env ]; then
  echo "==> Loading .env"
  set -a
  source .env
  set +a
fi

# Validate required vars
for var in PURPLEMET_API_TOKEN PURPLEMET_TARGET_URL; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: ${var} is not set. Add it to cli/.env or export it."
    exit 1
  fi
done

echo "==> Running GitHub Action locally with act..."
echo "    Target: ${PURPLEMET_TARGET_URL}"
echo "    Base URL: ${PURPLEMET_BASE_URL:-https://api.dev.purplemet.com}"
echo ""

act push \
  -W integrations/github-action/test-local/workflow.yml \
  -s PURPLEMET_API_TOKEN="${PURPLEMET_API_TOKEN}" \
  -s PURPLEMET_TARGET_URL="${PURPLEMET_TARGET_URL}" \
  -s PURPLEMET_BASE_URL="${PURPLEMET_BASE_URL:-https://api.dev.purplemet.com}" \
  --bind \
  -v

EXIT_CODE=$?

# Cleanup linux binary
rm -f purplemet-cli

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "==> Test PASSED"
else
  echo "==> Test finished with exit code ${EXIT_CODE}"
fi

exit $EXIT_CODE
