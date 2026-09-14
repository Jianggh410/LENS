#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"
source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

label="com.lens.literature-followup"
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
action="${1:-status}"

case "$action" in
  install)
    mkdir -p "$(dirname "$plist")" "$FOLLOWUP_LOG_DIR"
    python3 - "$plist" "$label" "$RUNNER_DIR/run_followup.sh" "$SYSTEM_DIR" "$FOLLOWUP_LOG_DIR" <<'PY'
import plistlib
import sys
from pathlib import Path

path, label, runner, workdir, logdir = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", runner],
    "WorkingDirectory": workdir,
    "StartCalendarInterval": {"Weekday": 2, "Hour": 8, "Minute": 0},
    "StandardOutPath": str(Path(logdir) / "launchd.stdout.log"),
    "StandardErrorPath": str(Path(logdir) / "launchd.stderr.log"),
}
with open(path, "wb") as handle:
    plistlib.dump(payload, handle)
PY
    launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "$domain" "$plist"
    echo "Installed weekly schedule: Monday 08:00"
    echo "$plist"
    ;;
  uninstall)
    launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
    rm -f "$plist"
    echo "Removed schedule: $label"
    ;;
  status)
    if launchctl print "$domain/$label" >/dev/null 2>&1; then
      echo "Schedule is installed: $plist"
    else
      echo "Schedule is not installed"
    fi
    ;;
  *)
    echo "Usage: bash install_launchd.sh [install|uninstall|status]" >&2
    exit 1
    ;;
esac
