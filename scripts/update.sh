#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "LENS is not inside a Git repository: $ROOT_DIR" >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "LENS has uncommitted changes; update aborted to protect local work." >&2
  exit 1
fi

git -C "$ROOT_DIR" pull --ff-only
bash "$ROOT_DIR/scripts/validate.sh"
bash "$ROOT_DIR/scripts/install.sh"
