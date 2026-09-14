#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"
source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

find "$READING_DIR" "$LIB_DIR" -type f -name "*.md" -print0 2>/dev/null \
  | xargs -0 grep -EIl "^status:[[:space:]]*human-(reviewed|extended|add2lib)$" 2>/dev/null || true
