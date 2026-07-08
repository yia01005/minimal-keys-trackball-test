#!/bin/bash
# Download latest firmware from GitHub Actions
# Usage: ./download.sh [repo]
#   repo: GitHub repository (default: hyhy-masa/minimal-keys-farmware)
#   Example: ./download.sh hyhy-masa/minimal-keys-farmware

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${1:-hyhy-masa/minimal-keys-farmware}"
DEFAULT_REPO="hyhy-masa/minimal-keys-farmware"

if [ "$REPO" = "$DEFAULT_REPO" ]; then
    FW_DIR="$SCRIPT_DIR/firmware"
else
    REPO_NAME="${REPO#*/}"
    FW_DIR="$SCRIPT_DIR/firmware_download/$REPO_NAME/firmware"
    mkdir -p "$FW_DIR"
fi

echo "Fetching latest successful build from $REPO..."

# Get latest successful run ID
RUN_ID=$(gh run list --repo "$REPO" --status success --limit 1 --json databaseId --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
    echo "ERROR: No successful builds found"
    exit 1
fi

echo "Run ID: $RUN_ID"

# Clean and download
rm -rf "$FW_DIR/tmp_download"
gh run download "$RUN_ID" --repo "$REPO" --dir "$FW_DIR/tmp_download"

# Move uf2 files to firmware/ with standardized names
rm -f "$FW_DIR"/*.uf2

for f in "$FW_DIR"/tmp_download/firmware/*.uf2; do
    mv "$f" "$FW_DIR/"
done

rm -rf "$FW_DIR/tmp_download"

echo ""
echo "Downloaded to $FW_DIR/:"
ls -1 "$FW_DIR"/*.uf2
echo ""
if [ "$REPO" = "$DEFAULT_REPO" ]; then
    echo "Ready to flash: ./scripts/flash.sh"
else
    echo "Ready to flash: ./scripts/flash.sh --dir $FW_DIR"
fi
