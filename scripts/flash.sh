#!/bin/bash
# Auto-flash minimal-keys firmware
# Automatically detects GATT changes from git log and chooses the right mode.
#
# Usage:
#   ./flash.sh                    # Auto-detect: normal or GATT reset
#   ./flash.sh R                  # Flash R only (no reset)
#   ./flash.sh L                  # Flash L only (no reset)
#   ./flash.sh R --reset          # Flash R with settings_reset
#   ./flash.sh L --reset          # Flash L with settings_reset
#   ./flash.sh --dir /path/to/fw  # Use firmware from specified directory

set -euo pipefail

VOLUME="/Volumes/XIAO-SENSE"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FW_DIR="${FW_DIR:-$REPO_DIR/firmware}"

# Parse --dir option
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            FW_DIR="$2"
            shift 2
            ;;
        --dir=*)
            FW_DIR="${1#--dir=}"
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Find uf2 files by pattern (names may vary across builds)
find_fw() {
    local pattern="$1"
    local found
    found=$(find "$FW_DIR" -maxdepth 1 -name "$pattern" -type f | head -1)
    echo "$found"
}

R_FW=$(find_fw "minimal-keys_R *-seeeduino_xiao_ble-zmk.uf2")
L_FW=$(find_fw "minimal-keys_L *-seeeduino_xiao_ble-zmk.uf2")
SETTINGS_RESET=$(find_fw "settings_reset-seeeduino_xiao_ble-zmk.uf2")

if [ -z "$R_FW" ] || [ -z "$L_FW" ]; then
    echo "ERROR: Firmware files not found in $FW_DIR"
    echo "Expected: minimal-keys_R *-seeeduino_xiao_ble-zmk.uf2"
    echo "          minimal-keys_L *-seeeduino_xiao_ble-zmk.uf2"
    exit 1
fi

echo "Firmware dir: $FW_DIR"

# Detect if GATT reset is needed from git log
needs_gatt_reset() {
    cd "$REPO_DIR"
    if git log --oneline -5 | grep -q "\[GATT-RESET\]"; then
        return 0
    fi
    return 1
}

flash_one() {
    local label="$1"
    local fw_file="$2"

    if [ ! -f "$fw_file" ]; then
        echo "ERROR: $fw_file not found"
        echo "Run ./scripts/download.sh first"
        exit 1
    fi

    echo ""
    echo "=== $label ==="

    echo "Waiting for bootloader... (press Layer3 + Q, or double-tap reset)"
    while [ ! -d "$VOLUME" ]; do
        sleep 0.5
    done
    echo "Detected $VOLUME"
    sleep 3

    # Verify volume is still mounted and writable
    if [ ! -d "$VOLUME" ]; then
        echo "Volume disappeared. Waiting again..."
        while [ ! -d "$VOLUME" ]; do
            sleep 0.5
        done
        echo "Re-detected $VOLUME"
        sleep 3
    fi

    local fname
    fname="$(basename "$fw_file")"
    echo "Copying $fname..."
    if ! dd if="$fw_file" of="$VOLUME/$fname" bs=4096 2>/dev/null; then
        echo "WARNING: First copy attempt failed. Waiting for volume..."
        sleep 3
        while [ ! -d "$VOLUME" ]; do
            sleep 0.5
        done
        sleep 3
        if ! dd if="$fw_file" of="$VOLUME/$fname" bs=4096 2>/dev/null; then
            echo "ERROR: Copy failed after retry!"
            exit 1
        fi
    fi

    # Wait for unmount (board reboots after receiving uf2)
    while [ -d "$VOLUME" ]; do
        sleep 0.5
    done

    echo "Done! $label flashed successfully."
    sleep 1
}

HALF="${1:-normal}"
RESET_FLAG="${2:-}"

case "$HALF" in
    R|r)
        if [ "$RESET_FLAG" = "--reset" ]; then
            if [ -z "$SETTINGS_RESET" ]; then
                echo "ERROR: settings_reset UF2 not found in $FW_DIR"
                exit 1
            fi
            flash_one "R (settings clear)" "$SETTINGS_RESET"
            echo "settings_reset done. Wait ~5 seconds..."
            sleep 5
        fi
        flash_one "R (Central)" "$R_FW"
        ;;
    L|l)
        if [ "$RESET_FLAG" = "--reset" ]; then
            if [ -z "$SETTINGS_RESET" ]; then
                echo "ERROR: settings_reset UF2 not found in $FW_DIR"
                exit 1
            fi
            flash_one "L (settings clear)" "$SETTINGS_RESET"
            echo "settings_reset done. Wait ~5 seconds..."
            sleep 5
        fi
        flash_one "L (Peripheral)" "$L_FW"
        ;;
    fw-only)
        echo "=== FW only (R → L, no settings clear) ==="
        flash_one "R (Central)" "$R_FW"
        flash_one "L (Peripheral)" "$L_FW"
        echo ""
        echo "All done!"
        ;;
    normal|"")
        echo "=== Settings clear + flash (4 flashes) ==="
        echo "Order: R clear → R firmware → L clear → L firmware"
        flash_one "R (settings clear)" "$SETTINGS_RESET"
        flash_one "R (Central)" "$R_FW"
        flash_one "L (settings clear)" "$SETTINGS_RESET"
        flash_one "L (Peripheral)" "$L_FW"
        echo ""
        echo "All done! Wait 5 min for battery display."
        ;;
    *)
        echo "Usage: $0 [--dir /path/to/fw] [R|L|normal|fw-only] [--reset]"
        echo "  --dir     = specify firmware directory (default: ./firmware)"
        echo "  R|L       = flash one side only (add --reset for settings clear)"
        echo "  (no args) = settings clear + flash (4 flashes)"
        echo "  fw-only   = flash only, no settings clear (2 flashes)"
        exit 1
        ;;
esac
