#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SKILL_DIR="$ROOT_DIR/skills/lens-paper-note"
FOLLOWUP_SKILL_DIR="$ROOT_DIR/skills/lens-literature-followup"
CONFIG_FILE="$ROOT_DIR/config/lens_config.sh"

required_files=(
  "$ROOT_DIR/README.md"
  "$ROOT_DIR/LICENSE"
  "$SKILL_DIR/SKILL.md"
  "$SKILL_DIR/agents/openai.yaml"
  "$SKILL_DIR/references/note-rules.md"
  "$SKILL_DIR/references/metadata-rules.md"
  "$SKILL_DIR/references/citation-rules.md"
  "$SKILL_DIR/references/narrative-taxonomy.md"
  "$SKILL_DIR/references/figure-rules.md"
  "$SKILL_DIR/references/wiki-rules.md"
  "$SKILL_DIR/assets/templates/Article_note_template.md"
  "$SKILL_DIR/assets/templates/Review_note_template.md"
  "$CONFIG_FILE"
  "$ROOT_DIR/config/followup_sources.json"
  "$FOLLOWUP_SKILL_DIR/SKILL.md"
  "$FOLLOWUP_SKILL_DIR/agents/openai.yaml"
  "$FOLLOWUP_SKILL_DIR/references/source-rules.md"
  "$FOLLOWUP_SKILL_DIR/references/matching-rules.md"
  "$FOLLOWUP_SKILL_DIR/references/summary-rules.md"
  "$FOLLOWUP_SKILL_DIR/references/database-schema.md"
  "$FOLLOWUP_SKILL_DIR/references/workflows/run-weekly.md"
  "$FOLLOWUP_SKILL_DIR/assets/templates/weekly_digest.md"
  "$FOLLOWUP_SKILL_DIR/assets/summary_schema.json"
  "$FOLLOWUP_SKILL_DIR/scripts/followup.py"
  "$FOLLOWUP_SKILL_DIR/scripts/run_followup.sh"
  "$FOLLOWUP_SKILL_DIR/scripts/install_launchd.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file: $file" >&2
    exit 1
  fi
done

if ! grep -q '^name: lens-paper-note$' "$SKILL_DIR/SKILL.md"; then
  echo "Invalid Skill name in $SKILL_DIR/SKILL.md" >&2
  exit 1
fi
if ! grep -q '^description:' "$SKILL_DIR/SKILL.md"; then
  echo "Missing Skill description in $SKILL_DIR/SKILL.md" >&2
  exit 1
fi
if ! grep -q '^name: lens-literature-followup$' "$FOLLOWUP_SKILL_DIR/SKILL.md"; then
  echo "Invalid Skill name in $FOLLOWUP_SKILL_DIR/SKILL.md" >&2
  exit 1
fi

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT_DIR/scripts" "$SKILL_DIR/scripts" "$FOLLOWUP_SKILL_DIR/scripts" -maxdepth 1 -type f -name '*.sh' | sort)

python3 -m py_compile "$FOLLOWUP_SKILL_DIR/scripts/followup.py"
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$ROOT_DIR/config/followup_sources.json"
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$FOLLOWUP_SKILL_DIR/assets/summary_schema.json"

# shellcheck disable=SC1090
source "$CONFIG_FILE"
[[ "$SCRIPT_DIR" == "$SKILL_DIR/scripts" ]]
[[ "$TEMPLATE_DIR" == "$SKILL_DIR/assets/templates" ]]
[[ "$REFERENCE_DIR" == "$SKILL_DIR/references" ]]
[[ "$WIKI_DIR" == "$LITERATURE_DIR/Wiki" ]]
[[ "$FOLLOWUP_SCRIPT_DIR" == "$FOLLOWUP_SKILL_DIR/scripts" ]]
[[ "$FOLLOWUP_DB" == "$ROOT_DIR/data/literature_followup/literature_followup.sqlite3" ]]
[[ "$DATA_DIR" == "$ROOT_DIR/data" ]]
[[ "$LITERATURE_FOLLOWUP_DATA_DIR" == "$DATA_DIR/literature_followup" ]]
python3 -c 'import json, os; value = json.loads(os.environ["USER_RESEARCH"]); assert isinstance(value, dict); assert all(isinstance(v, list) for v in value.values())'

echo "LENS validation passed"
echo "Skill:      $SKILL_DIR"
echo "Follow-up:  $FOLLOWUP_SKILL_DIR"
echo "Literature: $LITERATURE_DIR"
echo "Cache:      $CACHE_DIR"
echo "Data:       $DATA_DIR"
echo "Logs:       $LOG_DIR"
echo "Wiki:       $READING_WIKI_DIR and $LIBRARY_WIKI_DIR"
