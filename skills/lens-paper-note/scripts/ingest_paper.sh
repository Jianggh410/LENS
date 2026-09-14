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
  bash ingest_paper.sh /absolute/path/to/paper.pdf

Pipeline:
  1. Convert the source paper with markitdown.
  2. Ask Codex CLI to create a structured note in Reading/ai-draft/.
  3. Rebuild the literature wiki.

Optional:
  CODEX_EXEC_MODEL=<model> bash ingest_paper.sh /absolute/path/to/paper.pdf
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

paper_path="$1"
if [[ ! -f "$paper_path" ]]; then
  echo "Input paper not found: $paper_path" >&2
  exit 1
fi

if ! command -v markitdown >/dev/null 2>&1; then
  echo "markitdown is required but not installed." >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI is required but not installed." >&2
  exit 1
fi

runtime_cache_dir="$CACHE_DIR"
runtime_log_dir="$LOG_DIR"
mkdir -p "$AI_DRAFT_DIR" "$AI_DRAFT_ASSET_DIR"
if ! mkdir -p "$CACHE_DIR/ingest_markdown" "$CACHE_DIR/ingest_prompts" "$LOG_DIR" 2>/dev/null; then
  runtime_cache_dir="${TMPDIR:-/tmp}/literature_ingest_cache"
  runtime_log_dir="${TMPDIR:-/tmp}/literature_ingest_logs"
  mkdir -p "$runtime_cache_dir/ingest_markdown" "$runtime_cache_dir/ingest_prompts" "$runtime_log_dir"
fi

paper_name="$(basename "$paper_path")"
paper_stem="${paper_name%.*}"
paper_ext="${paper_name##*.}"
paper_ext_lc="$(printf '%s' "$paper_ext" | tr '[:upper:]' '[:lower:]')"
converted_md="$runtime_cache_dir/ingest_markdown/${paper_stem}.md"
prompt_file="$runtime_cache_dir/ingest_prompts/${paper_stem}.prompt.txt"
output_log="$runtime_log_dir/${paper_stem}.ingest.log"
output_last="$runtime_log_dir/${paper_stem}.ingest.last.txt"
before_notes="$runtime_cache_dir/ingest_prompts/${paper_stem}.before-notes.txt"
ai_draft_date="$(date +%F)"

# 标准化笔记键
normalize_note_key() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]:：_-]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

# 提取YAML标量
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

# 标准化DOI
normalize_doi() {
  local value="$1"
  value="$(printf '%s' "$value" | tr -d '[:space:]' | sed -E 's/^["'\'']|["'\'']$//g')"
  value="${value#doi:}"
  value="${value#DOI:}"
  value="${value#https://doi.org/}"
  value="${value#http://doi.org/}"
  value="${value#https://dx.doi.org/}"
  value="${value#http://dx.doi.org/}"
  value="${value#/}"
  printf '%s' "$value"
}

# 提取DOI
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

# 提取标题
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

case "$paper_ext_lc" in
  md)
    cp "$paper_path" "$converted_md"
    ;;
  pdf|doc|docx|ppt|pptx|html|htm)
    markitdown "$paper_path" -o "$converted_md"
    ;;
  *)
    echo "Unsupported input format: .$paper_ext_lc" >&2
    exit 1
    ;;
esac

paper_key="$(normalize_note_key "$paper_stem")"
paper_doi="$(normalize_doi "$(extract_doi_from_text "$converted_md")")"
paper_title="$(extract_title_from_text "$converted_md")"
paper_title_key="$(normalize_note_key "$paper_title")"

duplicate_reason=""
duplicate_paths="$(
  find "$READING_DIR" "$LIB_DIR" -type f -name '*.md' -print 2>/dev/null \
    | while IFS= read -r note_path; do
        note_name="$(basename "$note_path")"
        note_stem="${note_name%.md}"
        note_doi="$(normalize_doi "$(yaml_scalar "$note_path" "doi")")"
        note_title="$(yaml_scalar "$note_path" "title")"
        note_title_key="$(normalize_note_key "$note_title")"
        note_base_key="$(normalize_note_key "$note_stem")"

        if [[ -n "$paper_doi" && -n "$note_doi" && "$paper_doi" == "$note_doi" ]]; then
          printf 'doi\t%s\n' "$note_path"
        elif [[ -n "$paper_title_key" && -n "$note_title_key" && "$paper_title_key" == "$note_title_key" ]]; then
          printf 'title\t%s\n' "$note_path"
        elif [[ "$paper_key" == "$note_base_key" ]]; then
          printf 'basename\t%s\n' "$note_path"
        fi
      done
)"
if [[ -n "$duplicate_paths" ]]; then
  duplicate_reason="$(printf '%s\n' "$duplicate_paths" | head -n 1 | cut -f1)"
  echo "A note with the same ${duplicate_reason} already exists:" >&2
  printf '%s\n' "$duplicate_paths" | cut -f2- >&2
  exit 0
fi

cat > "$prompt_file" <<PROMPT
Read these files first:
- $REFERENCE_DIR/note-rules.md
- $REFERENCE_DIR/metadata-rules.md
- $REFERENCE_DIR/citation-rules.md
- $REFERENCE_DIR/narrative-taxonomy.md
- $REFERENCE_DIR/typography-rules.md
- $REFERENCE_DIR/workflows/ingest-paper.md
- $TEMPLATE_DIR/Article_note_template.md
- $TEMPLATE_DIR/Review_note_template.md

Task:
Process one paper from raw_dir and create a literature note.

Input paper source:
$paper_path

Converted markdown to read:
$converted_md

Requirements:
- Work inside $LITERATURE_DIR.
- User research: ${USER_RESEARCH:-}
- Determine whether the paper is an Article or Review.
- Create one structured markdown note in $AI_DRAFT_DIR.
- Name the note exactly \`$paper_stem.md\`, preserving the input PDF stem and its journal/source abbreviation. Do not replace abbreviations such as N, NG, C, or bioRxiv with the formal journal name. Keep the formal journal name only in YAML \`journal\`.
- Use YAML fields from the template.
- Always set status: ai-draft.
- Set start_reading_date exactly to $ai_draft_date. This is the date the ai-draft is created, not the paper publication date.
- Keep the paper title in English, but write the explanatory body text in Chinese.
- Apply every mixed Chinese-English typography rule in $REFERENCE_DIR/typography-rules.md to newly generated explanatory prose, including half-width spacing, full-width Chinese punctuation, scientific units, percentages, slashes, hyphens, ranges, parentheses, Markdown links, and removal of redundant spaces.
- If the paper title contains ":" or "：", replace that character with "-" when recording the title in the note.
- For both Article and Review notes, use this exact # Info structure: ## 文章介绍; ## 通讯作者与单位; ## 数据与代码.
- Under ## 文章介绍, write one concise Chinese sentence describing only the document type, journal or preprint platform, publication status, and publication date or year. Do not summarize the research question, methods, results, conclusions, or relevance.
- Under ## 通讯作者与单位, give each clearly identified corresponding author a separate block: a standalone **通讯作者**：Name line followed by that author's - **单位**：, - **研究方向**：, and - **实验室网站**： fields. Leave a blank line between author blocks. Never combine multiple corresponding authors into shared fields. Search for each corresponding author's laboratory website and verify it against an official lab, university, institute, or ORCID page. Prefer the official lab website; never invent or use an unverified URL. Format every verified website as a clickable Markdown link, for example - **实验室网站**：[Daniel A. Lim Lab](https://danlimlab.ucsf.edu/); never output a verified website as a bare URL. If no website is verified, write - **实验室网站**：未说明.
- Under ## 数据与代码, explain which data the paper used or generated: biological source or cohort; organism, cell, or tissue type; assay or processing; new versus reused data; accession numbers and repositories. Also record verified code repositories and project links. Write 未说明 if unavailable.
- Never mention the user's research relevance in # Info; place it only under My Research in # Discussion.
- For Article notes, put figures worth focusing on at the end of # Summary, immediately before # Intro, not in # Info. Use the exact heading "**Figures worth focusing on**", followed by bullets such as "- **Fig. 1**：xxx。"
- In # Intro, do not introduce or explain figures.
- For Article notes, write # Works by work modules, not by figure. After reading # Works, the reader should understand how the paper is constructed.
- For Article notes, write # Results by the main result of each figure. Use the original English figure title as each subsection title whenever available, then explain the figure's main result and evidence in Chinese. Do not add a separate Key evidence block to # Results. After reading # Results, the reader should understand what the paper proved.
- For Article notes, add # Question–Method Map immediately after # Results and before # Discussion. This is a compressed question tree, not one question with one method and not an experiment list. State one Core Question, then choose 3–8 key Question–Method pairs that genuinely advance the evidence chain. Derive the questions from the paper instead of using fixed question categories. Format each pair as "## Qn. [an experimentally answerable key question]" followed by "**Method:** core experimental design + core analysis method + how the method answers the question" in concise Chinese. Order pairs by scientific logic rather than figure order, combine methods serving the same question, and omit routine procedural details.
- For Review notes, write # Works by viewpoint/framework modules, not by figure or by merely restating the original table of contents.
- For Review notes, organize # Evidence by the Review's main numbered figures in source order. Create one subsection per main figure using "## Figure N. Original English figure title" (or the source's Fig. style), then explain in Chinese the framework or model, supported viewpoint, representative evidence, and the boundary between evidence synthesis and author framing. Preserve the figure number and original English title exactly because these headings drive automatic extraction.
- For both Article and Review notes, use the concise # Discussion structure from note-rules.md and the templates. Under ## 1. Interpretation use ### Question & Conclusion with 核心问题 and 核心结论, ### Evidence Chain as 3–8 numbered evidential steps, and ### Logic / Paradigm as a compact scientific progression. Under ## 2. Contribution & Critique use ### Prior Knowledge & Advance, ### Innovation & Significance, and ### Limitations & Open Questions. Under ## 3. Implications use ### Storytelling, ### Experimental Strategy, ### Visualization, and ### My Research. Parse User research as a JSON object and, under ### My Research, create exactly one #### <project key> subsection for every configured project in JSON order. Discuss each project separately in 1–3 concise Chinese sentences, focusing on concrete relevance and transferable concepts, methods, experiments, datasets, models, or strategies. If relevance is weak, say so briefly and explain why; never omit a configured project or merge multiple projects into one paragraph. Write the analysis in Chinese and avoid repetition.
- Put the evidence chain under ## 1. Interpretation, never at the end of # Results or # Evidence.
- Fill summary_short, topics, and tags when possible. Write topics and tags as YAML lists, never semicolon- or comma-separated scalar strings. Topics may contain spaces. Tags must not have a leading #, spaces, commas, semicolons, or other whitespace. Capitalize the first letter of each tag, preserve proper-noun capitalization, write abbreviations/acronyms in uppercase, and join multiple words with hyphens; prefer 3–8 focused tags and reuse existing spellings when possible.
- Always include the lowercase YAML property narrative. If the paper's main evidence progression clearly matches one allowed value in narrative-taxonomy.md, set exactly one value, for example: narrative: Method-to-Discovery. If unclear or mixed, leave narrative empty. Do not invent values.
- Always write YAML doi as a full URL in the form https://doi.org/<DOI>.
- Write YAML citation as a two-line block scalar using the first author. Format: first line "First author et al., Journal (Year)"; second line "First author et al., Title, Journal (Year)".
- Leave YAML note empty for ai-draft notes. Do not put conversion-quality remarks, figure-extraction remarks, or other automatic comments into YAML note.
- If figures are missing or unreliable, add a "Figures to manually inspect" section instead of inventing figure interpretations.
- Store images under $AI_DRAFT_ASSET_DIR/{note_filename_without_md}/ if you create any asset placeholders.
- Do not overwrite an existing note unless an exact update is clearly needed.
- Do not run the wiki rebuild or figure-extraction scripts yourself; the shell pipeline runs them after locating the created note.
- In the final response, report the created note path.
PROMPT

{
  echo "[ingest] source: $paper_path"
  echo "[ingest] converted: $converted_md"
} | tee "$output_log"

find "$AI_DRAFT_DIR" -maxdepth 1 -type f -name '*.md' -print | sort > "$before_notes"

codex exec \
  --ignore-user-config \
  --skip-git-repo-check \
  --sandbox workspace-write \
  --model "$CODEX_EXEC_MODEL" \
  --cd "$LITERATURE_DIR" \
  --add-dir "$LITERATURE_DIR" \
  -o "$output_last" \
  "$(cat "$prompt_file")" | tee -a "$output_log"

if [[ -f "$output_last" ]]; then
  {
    echo "[ingest] codex summary:"
    cat "$output_last"
  } | tee -a "$output_log"
fi

created_note="$({
  find "$AI_DRAFT_DIR" -maxdepth 1 -type f -name '*.md' -print | sort
} | awk 'NR==FNR { before[$0]=1; next } !before[$0] { print }' "$before_notes" - | tail -n 1)"

if [[ -z "$created_note" ]]; then
  echo "[ingest] unable to locate a newly created note in $AI_DRAFT_DIR" | tee -a "$output_log" >&2
  exit 1
fi

expected_note="$AI_DRAFT_DIR/$paper_stem.md"
if [[ "$created_note" != "$expected_note" ]]; then
  if [[ -e "$expected_note" ]]; then
    echo "[ingest] expected PDF-stem note already exists: $expected_note" | tee -a "$output_log" >&2
    exit 1
  fi
  mv "$created_note" "$expected_note"
  created_note="$expected_note"
  echo "[ingest] normalized note filename to PDF stem: $created_note" | tee -a "$output_log"
fi

# Ensure verified laboratory websites render as clickable Markdown links even
# when the generated draft contains a bare URL.
python3 - "$created_note" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(r'(?m)^(- \*\*实验室网站\*\*[：:]\s*)(https?://\S+)\s*$')
updated = pattern.sub(lambda match: f'{match.group(1)}[{match.group(2)}]({match.group(2)})', text)
if updated != text:
    path.write_text(updated, encoding="utf-8")
PY

echo "[ingest] note: $created_note" | tee -a "$output_log"

if [[ -x "$SCRIPT_DIR/extract_figures.sh" ]]; then
  echo "[ingest] extracting figures" | tee -a "$output_log"
  if ! bash "$SCRIPT_DIR/extract_figures.sh" "$paper_path" "$created_note" 2>&1 | tee -a "$output_log"; then
    echo "[ingest] figure extraction failed; note retained for manual inspection" | tee -a "$output_log" >&2
  fi
else
  echo "[ingest] figure extractor unavailable: $SCRIPT_DIR/extract_figures.sh" | tee -a "$output_log" >&2
fi

echo "[ingest] rebuilding wiki" | tee -a "$output_log"
bash "$SCRIPT_DIR/rebuild_wiki.sh" 2>&1 | tee -a "$output_log"

echo "[ingest] done"
