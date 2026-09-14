#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_DIR="$(cd "$RUNNER_DIR" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

source "$CONFIG_FILE"

ingest_script="$RUNNER_DIR/ingest_paper.sh"
if [[ ! -f "$ingest_script" ]]; then
  echo "Missing ingest script: $ingest_script" >&2
  exit 1
fi

shopt -s nullglob
files=("$RAW_DIR"/*.pdf "$RAW_DIR"/*.md)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No source papers found in $RAW_DIR"
  exit 0
fi

processed=0
skipped=0
failed=0

normalize_note_key() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]:：_-]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

yaml_scalar() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    $0 == "---" && in_yaml == 0 { in_yaml = 1; next }
    $0 == "---" && in_yaml == 1 { exit }
    in_yaml == 1 && $0 ~ ("^" key ":") {
      line = $0
      sub("^[^:]*:[[:space:]]*", "", line)
      print line
      exit
    }
  ' "$file"
}

normalize_doi() {
  local value="$1"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#doi:}"
  value="${value#DOI:}"
  value="${value#https://doi.org/}"
  value="${value#http://doi.org/}"
  value="${value#https://dx.doi.org/}"
  value="${value#http://dx.doi.org/}"
  value="${value#/}"
  printf '%s' "$value"
}

extract_doi_from_text() {
  local file="$1"
  python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors="ignore")
m = re.search(r'(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)', text)
print(m.group(1) if m else "")
PY
}

extract_title_from_text() {
  local file="$1"
  python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text(errors="ignore").splitlines()

def clean(line: str) -> str:
    line = re.sub(r'^\s*#+\s*', '', line).strip()
    return re.sub(r'\s+', ' ', line)

for raw in lines[:80]:
    line = clean(raw)
    if not line:
        continue
    if line.lower() in {"article", "review", "abstract", "introduction", "contents"}:
        continue
    if len(line) > 220:
        continue
    print(line)
    break
else:
    print("")
PY
}

for paper_path in "${files[@]}"; do
  paper_name="$(basename "$paper_path")"
  paper_stem="${paper_name%.*}"
  paper_ext="${paper_name##*.}"
  paper_ext_lc="$(printf '%s' "$paper_ext" | tr '[:upper:]' '[:lower:]')"
  paper_key="$(normalize_note_key "$paper_stem")"

  tmp_converted="$(mktemp)"
  case "$paper_ext_lc" in
    md)
      cp "$paper_path" "$tmp_converted"
      ;;
    pdf|doc|docx|ppt|pptx|html|htm)
      if ! markitdown "$paper_path" -o "$tmp_converted" >/dev/null 2>&1; then
        rm -f "$tmp_converted"
        echo "[run] $paper_name"
        if bash "$ingest_script" "$paper_path"; then
          processed=$((processed + 1))
        else
          echo "[fail] $paper_name" >&2
          failed=$((failed + 1))
        fi
        continue
      fi
      ;;
    *)
      rm -f "$tmp_converted"
      echo "[run] $paper_name"
      if bash "$ingest_script" "$paper_path"; then
        processed=$((processed + 1))
      else
        echo "[fail] $paper_name" >&2
        failed=$((failed + 1))
      fi
      continue
      ;;
  esac

  paper_doi="$(normalize_doi "$(extract_doi_from_text "$tmp_converted")")"
  paper_title="$(extract_title_from_text "$tmp_converted")"
  paper_title_key="$(normalize_note_key "$paper_title")"

  existing="$(
    find "$READING_DIR" "$LIB_DIR" -type f -name '*.md' -print 2>/dev/null \
      | while IFS= read -r note_path; do
          note_name="$(basename "$note_path")"
          note_stem="${note_name%.md}"
          note_doi="$(normalize_doi "$(yaml_scalar "$note_path" "doi")")"
          note_title="$(yaml_scalar "$note_path" "title")"
          note_title_key="$(normalize_note_key "$note_title")"
          note_base_key="$(normalize_note_key "$note_stem")"

          if [[ -n "$paper_doi" && -n "$note_doi" && "$paper_doi" == "$note_doi" ]]; then
            printf '%s\n' "$note_path"
          elif [[ -n "$paper_title_key" && -n "$note_title_key" && "$paper_title_key" == "$note_title_key" ]]; then
            printf '%s\n' "$note_path"
          elif [[ "$paper_key" == "$note_base_key" ]]; then
            printf '%s\n' "$note_path"
          fi
        done
  )"
  rm -f "$tmp_converted"
  if [[ -n "$existing" ]]; then
    echo "[skip] $paper_name"
    skipped=$((skipped + 1))
    continue
  fi

  echo "[run] $paper_name"
  if bash "$ingest_script" "$paper_path"; then
    processed=$((processed + 1))
  else
    echo "[fail] $paper_name" >&2
    failed=$((failed + 1))
  fi
done

echo
echo "Batch ingest complete"
echo "Processed: $processed"
echo "Skipped:   $skipped"
echo "Failed:    $failed"
