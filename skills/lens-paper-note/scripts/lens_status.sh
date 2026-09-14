#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"
source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

echo "LENS system status"
echo "========================"
echo "RAW_DIR:        $RAW_DIR"
echo "LITERATURE_DIR: $LITERATURE_DIR"
echo "USER_RESEARCH:  ${USER_RESEARCH:-}"
echo

echo "Raw papers:"
find "$RAW_DIR" -maxdepth 1 \( -name "*.pdf" -o -name "*.md" \) | wc -l

echo "Reading notes:"
find "$READING_DIR" -type f -name "*.md" ! -path "*/assets/*" | wc -l

echo "Library notes:"
find "$LIB_DIR" -type f -name "*.md" | wc -l

echo "Synthesis notes:"
find "$SYNTHESIS_DIR" -maxdepth 1 -name "*.md" | wc -l

echo
echo "AI draft notes:"
{
  find "$READING_DIR" "$LIB_DIR" -type f -name "*.md" -print0 2>/dev/null \
    | xargs -0 grep -Il "^status:[[:space:]]*ai-draft$" 2>/dev/null || true
} | wc -l

echo "Human notes:"
{
  find "$READING_DIR" "$LIB_DIR" -type f -name "*.md" -print0 2>/dev/null \
    | xargs -0 grep -EIl "^status:[[:space:]]*human-(reviewed|extended|add2lib)$" 2>/dev/null || true
} | wc -l
