#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"

source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  bash run_followup.sh [--no-ai] [--summaries-only] [--from-date YYYY-MM-DD] [--to-date YYYY-MM-DD]

Modes:
  default           Fetch, match, summarize pending records, and render Markdown.
  --no-ai           Fetch, match, and render without calling Codex.
  --summaries-only  Retry pending summaries and render without fetching sources.
USAGE
}

no_ai=0
summaries_only=0
from_date=""
to_date=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-ai) no_ai=1; shift ;;
    --summaries-only) summaries_only=1; shift ;;
    --from-date) from_date="${2:-}"; shift 2 ;;
    --to-date) to_date="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

mkdir -p "$LITERATURE_FOLLOWUP_DATA_DIR" "$FOLLOWUP_CACHE_DIR" "$FOLLOWUP_LOG_DIR" \
  "$FOLLOWUP_WEEKLY_DIR" "$FOLLOWUP_PROJECTS_DIR"

lock_dir="$LITERATURE_FOLLOWUP_DATA_DIR/.run.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "Another literature-followup run is active: $lock_dir" >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

run_stamp="$(date +%Y%m%d-%H%M%S)"
log_file="$FOLLOWUP_LOG_DIR/$run_stamp.log"
exec > >(tee -a "$log_file") 2>&1

echo "[followup] started: $(date '+%F %T %z')"
echo "[followup] database: $FOLLOWUP_DB"

if [[ "$summaries_only" -eq 0 ]]; then
  sync_args=(sync)
  [[ -n "$from_date" ]] && sync_args+=(--from-date "$from_date")
  [[ -n "$to_date" ]] && sync_args+=(--to-date "$to_date")
  python3 "$RUNNER_DIR/followup.py" "${sync_args[@]}"
fi

summarized=0
if [[ "$no_ai" -eq 0 ]]; then
  if ! command -v codex >/dev/null 2>&1; then
    echo "[followup] codex CLI not found; leaving matched records pending" >&2
  else
    while [[ "$summarized" -lt "$FOLLOWUP_SUMMARY_LIMIT" ]]; do
      remaining=$((FOLLOWUP_SUMMARY_LIMIT - summarized))
      batch_size="$FOLLOWUP_SUMMARY_BATCH_SIZE"
      if [[ "$remaining" -lt "$batch_size" ]]; then
        batch_size="$remaining"
      fi
      pending_file="$FOLLOWUP_CACHE_DIR/pending-$run_stamp-$summarized.json"
      prompt_file="$FOLLOWUP_CACHE_DIR/prompt-$run_stamp-$summarized.txt"
      output_file="$FOLLOWUP_CACHE_DIR/summary-$run_stamp-$summarized.json"
      python3 "$RUNNER_DIR/followup.py" pending --limit "$batch_size" > "$pending_file"
      pending_count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$pending_file")"
      if [[ "$pending_count" -eq 0 ]]; then
        break
      fi
      python3 "$RUNNER_DIR/followup.py" build-prompt --input "$pending_file" --output "$prompt_file"
      echo "[followup] summarizing batch: $pending_count"
      if codex exec \
        --ignore-user-config \
        --skip-git-repo-check \
        --ephemeral \
        --sandbox read-only \
        --model "$FOLLOWUP_CODEX_MODEL" \
        --cd "$LITERATURE_DIR" \
        --output-schema "$FOLLOWUP_SKILL_DIR/assets/summary_schema.json" \
        --output-last-message "$output_file" \
        - < "$prompt_file"; then
        import_result="$(python3 "$RUNNER_DIR/followup.py" import-summaries --input "$output_file")"
        imported="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["imported"])' "$import_result")"
        echo "[followup] imported summaries: $imported"
        summarized=$((summarized + imported))
        if [[ "$imported" -eq 0 ]]; then
          python3 "$RUNNER_DIR/followup.py" mark-attempt --input "$pending_file" --error "Codex response imported zero valid summaries"
          break
        fi
      else
        python3 "$RUNNER_DIR/followup.py" mark-attempt --input "$pending_file" --error "Codex CLI execution failed"
        echo "[followup] Codex failed; records remain retryable" >&2
        break
      fi
    done
  fi
fi

python3 "$RUNNER_DIR/followup.py" render
python3 "$RUNNER_DIR/followup.py" status
echo "[followup] completed: $(date '+%F %T %z')"
echo "[followup] log: $log_file"
