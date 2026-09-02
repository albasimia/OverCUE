#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/OverCUE.app"
APP_BIN="$APP/Contents/MacOS/OverCUE"
CLI="$APP/Contents/Helpers/overcue-cli"
CONFIG="$HOME/Library/Application Support/OverCUE/config.json"
LOG_DIR="$ROOT/.build/input-diagnostics"
MODE="${1:-side}"
GROUP="${2:-1}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/${MODE}-${STAMP}.log"

mkdir -p "$LOG_DIR"

usage() {
    cat <<'EOF'
Usage:
  bash Scripts/diagnose-input-runtime.sh side
  bash Scripts/diagnose-input-runtime.sh ack05 [preset-number]
  bash Scripts/diagnose-input-runtime.sh config

side:
  Launches OverCUE.app from the terminal with Generic HID runtime and native-event
  suppression diagnostics enabled. Rebind the SIDE-KEYBOARD in the app, bring
  rekordbox to the front, then press one SIDE input. Quit OverCUE to finish.

ack05:
  Runs the bundled ACK05 helper directly with stdout visible. Bind/Rebind the
  ACK05 in OverCUE first, quit OverCUE, then run this mode and press one ACK05
  input while rekordbox is frontmost. Control-C to finish.

config:
  Prints the current Physical Device bindings, Logical Devices, and Group Presets.
EOF
}

print_config_section() {
    local key="$1"
    echo
    echo "=== config.${key} ==="
    if [[ ! -f "$CONFIG" ]]; then
        echo "Config not found: $CONFIG"
        return
    fi

    if /usr/bin/plutil -extract "$key" json -o - "$CONFIG" >/dev/null 2>&1; then
        /usr/bin/plutil -extract "$key" json -o - "$CONFIG"
    else
        echo "plutil could not extract '$key'; full config follows:"
        cat "$CONFIG"
    fi
}

print_binding_snapshot() {
    echo "=== OverCUE input diagnostic snapshot ==="
    echo "repo:   $ROOT"
    echo "config: $CONFIG"
    if command -v git >/dev/null 2>&1; then
        echo "branch: $(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
        echo "head:   $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)"
    fi
    print_config_section physicalDeviceBindings
    print_config_section logicalDevices
    print_config_section groupPresets
}

require_build() {
    if [[ ! -x "$APP_BIN" || ! -x "$CLI" ]]; then
        echo "Built app not found. Run ./Scripts/build-app.sh first." >&2
        exit 1
    fi
}

case "$MODE" in
    config)
        print_binding_snapshot
        ;;

    side)
        require_build
        print_binding_snapshot | tee "$LOG"
        echo | tee -a "$LOG"
        echo "=== SIDE runtime diagnostic ===" | tee -a "$LOG"
        echo "1. Ensure Controller Input is ON." | tee -a "$LOG"
        echo "2. Rebind the SIDE-KEYBOARD in Devices." | tee -a "$LOG"
        echo "3. Bring rekordbox to the front." | tee -a "$LOG"
        echo "4. Press exactly one SIDE input." | tee -a "$LOG"
        echo "5. Quit OverCUE when done." | tee -a "$LOG"
        echo "log: $LOG" | tee -a "$LOG"
        echo | tee -a "$LOG"

        OVERCUE_GENERIC_HID_DIAGNOSTICS=1 \
        OVERCUE_HID_SUPPRESSION_DIAGNOSTICS=1 \
        "$APP_BIN" 2>&1 | tee -a "$LOG"
        ;;

    ack05)
        require_build
        print_binding_snapshot | tee "$LOG"
        echo | tee -a "$LOG"
        echo "=== ACK05 runtime diagnostic ===" | tee -a "$LOG"
        echo "Bind/Rebind the ACK05 in OverCUE first, then quit OverCUE." | tee -a "$LOG"
        echo "Bring rekordbox to the front and press exactly one ACK05 input." | tee -a "$LOG"
        echo "Control-C when done." | tee -a "$LOG"
        echo "preset-number: $GROUP" | tee -a "$LOG"
        echo "log: $LOG" | tee -a "$LOG"
        echo | tee -a "$LOG"

        "$CLI" \
            --output mouse \
            --rekordbox-mode performance \
            --group "$GROUP" \
            --no-accessibility-prompt \
            2>&1 | tee -a "$LOG"
        ;;

    -h|--help|help)
        usage
        ;;

    *)
        echo "Unknown mode: $MODE" >&2
        usage >&2
        exit 2
        ;;
esac
