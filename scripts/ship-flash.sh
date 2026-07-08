#!/bin/bash
# Ship-flash: flash shipping keyboards with the latest minimal-keys-farmware build.
#
# What it does:
#   1. Downloads the latest successful build from hyhy-masa/minimal-keys-farmware
#      into firmware_download/minimal-keys-farmware/firmware/.
#      -> firmware/ (the minimal-keys-farmware firmware) is NEVER touched.
#   2. Flashes each unit in "settings clear + firmware" mode for a clean ship state:
#      R clear -> R firmware -> L clear -> L firmware.
#   3. Loops over multiple units: after each keyboard it asks whether to flash the next.
#
# This is a thin wrapper around the proven download.sh / flash.sh; it does not
# modify either of them.
#
# Usage:
#   ./scripts/ship-flash.sh                 # download latest build, then flash units in a loop
#   ./scripts/ship-flash.sh --skip-download # flash the already-downloaded firmware (no gh fetch)
#   ./scripts/ship-flash.sh --help

set -euo pipefail

REPO="hyhy-masa/minimal-keys-farmware"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/firmware_download/minimal-keys-farmware/firmware"

DOWNLOAD=1
for arg in "$@"; do
    case "$arg" in
        --skip-download) DOWNLOAD=0 ;;
        --help|-h)
            echo "Usage: $0 [--skip-download]"
            echo "  Downloads the latest build from $REPO and flashes shipping units"
            echo "  in settings-clear mode (R clear -> R -> L clear -> L), looping over units."
            echo "  firmware/ (minimal-keys-farmware) is never modified."
            echo ""
            echo "  --skip-download : skip the gh download and flash already-downloaded firmware"
            exit 0
            ;;
        *) echo "Unknown argument: $arg (try --help)"; exit 1 ;;
    esac
done

echo "================================================================"
echo " minimal-keys 出荷書き込み  (settings clear + firmware)"
echo "   取得元 : $REPO"
echo "   FWパス : $FW_DIR"
echo "   ※ firmware/ (minimal-keys-farmware) は変更しません"
echo "================================================================"

# --- Step 1: download the latest build (optional) -------------------------
if [ "$DOWNLOAD" -eq 1 ]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo ""
        echo "ERROR: gh CLI が未認証です。先にログインしてください:"
        echo "    gh auth login -h github.com"
        echo "  （ダウンロード済みファームをそのまま焼く場合は --skip-download）"
        exit 1
    fi
    echo ""
    echo "[1/2] 最新ビルドを取得中..."
    "$SCRIPT_DIR/download.sh" "$REPO"
else
    echo ""
    echo "[1/2] ダウンロードをスキップ（既存ファームを使用）"
fi

# --- Verify the three required firmware files exist -----------------------
find_fw() { find "$FW_DIR" -maxdepth 1 -name "$1" -type f | head -1; }
R_FW=$(find_fw "minimal-keys_R *-seeeduino_xiao_ble-zmk.uf2")
L_FW=$(find_fw "minimal-keys_L *-seeeduino_xiao_ble-zmk.uf2")
SETTINGS_RESET=$(find_fw "settings_reset-seeeduino_xiao_ble-zmk.uf2")

missing=0
[ -z "$R_FW" ]          && { echo "ERROR: R firmware が見つかりません ($FW_DIR)"; missing=1; }
[ -z "$L_FW" ]          && { echo "ERROR: L firmware が見つかりません ($FW_DIR)"; missing=1; }
[ -z "$SETTINGS_RESET" ] && { echo "ERROR: settings_reset が見つかりません ($FW_DIR)"; missing=1; }
if [ "$missing" -eq 1 ]; then
    echo "  --skip-download を外して先にビルドを取得してください。"
    exit 1
fi

# --- Show provenance and confirm ------------------------------------------
echo ""
echo "書き込むファーム（取得日時）:"
for f in "$R_FW" "$L_FW" "$SETTINGS_RESET"; do
    printf "   %-58s  %s\n" "$(basename "$f")" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
done
echo ""
read -r -p "この内容で出荷書き込みを開始しますか？ (y/n) " -n 1 REPLY; echo ""
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "中止しました。"; exit 0; }

# --- Step 2: flash loop (one keyboard per iteration) ----------------------
# Each flash.sh "normal" run performs the full 4-step clean flash for ONE keyboard:
#   R clear -> R firmware -> L clear -> L firmware.
count=0
while true; do
    count=$((count + 1))
    echo ""
    echo "================================================================"
    echo " [$count 台目] ブートローダー待機 → R clear → R → L clear → L"
    echo "   ※ 各ステップでボードをブートローダーに（Layer3+Q または リセット2回）"
    echo "================================================================"

    "$SCRIPT_DIR/flash.sh" --dir "$FW_DIR" normal

    echo ""
    echo "✅ $count 台目 完了。バッテリー表示は約5分後に出ます。"
    echo ""
    read -r -p "次の台を焼きますか？ (y/n) " -n 1 REPLY; echo ""
    [[ ! $REPLY =~ ^[Yy]$ ]] && break
done

echo ""
echo "出荷書き込み終了。合計 $count 台。"
