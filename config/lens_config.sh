#!/usr/bin/env bash

if [[ -n "${BASH_VERSION:-}" ]]; then
  CONFIG_SOURCE="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  CONFIG_SOURCE="${(%):-%x}"
else
  CONFIG_SOURCE="$0"
fi
CONFIG_DIR="$(cd "$(dirname "$CONFIG_SOURCE")" && pwd)"

# Runtime code and generated system data live beside this configuration file.
# Use the LENS-specific override only when embedding the config elsewhere.
export SYSTEM_DIR="${LENS_SYSTEM_DIR:-$(cd "$CONFIG_DIR/.." && pwd)}"
# Portable user settings. Override RAW_DIR, LITERATURE_DIR, or USER_RESEARCH when needed.
export LITERATURE_DIR="${LITERATURE_DIR:-$(cd "$SYSTEM_DIR/.." && pwd)}"
export LENS_SKILL_DIR="$SYSTEM_DIR/skills/lens-paper-note"
export NOTE_TO_PPT_SKILL_DIR="$SYSTEM_DIR/skills/lens-paper-note-to-ppt"
export NOTE_TO_PPT_SCRIPT="$NOTE_TO_PPT_SKILL_DIR/scripts/lens-paper-note-to-ppt.py"
export LENS_NOTE_TO_PPT_CONFIG="${LENS_NOTE_TO_PPT_CONFIG:-$NOTE_TO_PPT_SKILL_DIR/ppt.config}"
export FOLLOWUP_SKILL_DIR="$SYSTEM_DIR/skills/lens-literature-followup"
export RAW_DIR="${RAW_DIR:-$HOME/ASPIRE/Inbox/Paper}"
# Reading board = PDFs directly in RAW_DIR plus PDFs recursively in these colon-separated queue folders.
export READING_QUEUE_DIRS="${READING_QUEUE_DIRS:-$RAW_DIR/waiting4ai-draft}"
# Obsidian vault root used for vault-relative PDF links in Canvas files.
export OBSIDIAN_VAULT_DIR="${OBSIDIAN_VAULT_DIR:-$HOME/ASPIRE}"
# Research projects and matching keywords. Keep this value as valid JSON so both
# note generation and literature-followup workflows can consume it.
export USER_RESEARCH="${USER_RESEARCH:-$(cat <<'JSON'
{
  "E2G_mediator": [
    "Gene regulation",
    "Enhancer",
    "Promoter",
    "Mediator",
    "Condensate"
  ],
  "E2G_prediction": [
    "Gene regulation",
    "Enhancer",
    "Promoter",
    "Deep learning",
    "S2F",
    "Machine learning"
  ]
}
JSON
)}"
# Default Codex model used by ingest scripts. Override per run if needed.
export CODEX_EXEC_MODEL="${CODEX_EXEC_MODEL:-gpt-5.5}"
export LENS_FIGURE_AI_FALLBACK="${LENS_FIGURE_AI_FALLBACK:-1}"
export LENS_FIGURE_AI_MODEL="${LENS_FIGURE_AI_MODEL:-$CODEX_EXEC_MODEL}"
export LENS_FIGURE_AI_TIMEOUT_SECONDS="${LENS_FIGURE_AI_TIMEOUT_SECONDS:-240}"
# Figure crops start from the first detected panel/graphic and retain this much
# headroom. Horizontal crops stay inside the detected journal content frame.
export LENS_FIGURE_TOP_SAFETY_MARGIN="${LENS_FIGURE_TOP_SAFETY_MARGIN:-10}"
export LENS_FIGURE_CLAMP_TO_MAIN_FRAME="${LENS_FIGURE_CLAMP_TO_MAIN_FRAME:-1}"
export LENS_FIGURE_EDGE_CLEARANCE="${LENS_FIGURE_EDGE_CLEARANCE:-1}"
# Keep the complete original caption in the exported Figure whenever the Figure
# and caption share a PDF page and can be isolated as one rectangle.
export LENS_FIGURE_INCLUDE_ORIGINAL_CAPTION="${LENS_FIGURE_INCLUDE_ORIGINAL_CAPTION:-1}"
export LENS_FIGURE_CAPTION_PADDING_PT="${LENS_FIGURE_CAPTION_PADDING_PT:-6}"
# After vision AI identifies and verifies a complete Figure, expand its pixel
# bounding box by this many PDF points on every available side before insertion.
export LENS_FIGURE_AI_BBOX_PADDING_PT="${LENS_FIGURE_AI_BBOX_PADDING_PT:-10}"
# Review figures often place a narrow caption beside the Figure or use compact
# lower-case panel markers such as "a |" and "b." instead of "(A)".
export LENS_REVIEW_HORIZONTAL_ADJACENCY="${LENS_REVIEW_HORIZONTAL_ADJACENCY:-1}"
export LENS_REVIEW_PANEL_LABEL_STYLES="${LENS_REVIEW_PANEL_LABEL_STYLES:-parenthesized,pipe,dot}"
# Review Evidence treats numbered Tables as first-class visual evidence. When
# enabled, `## Table N. ...` headings are cropped and inserted like Figures,
# using stable Table-NN.png assets and table-specific managed markers.
export LENS_REVIEW_EXTRACT_TABLES="${LENS_REVIEW_EXTRACT_TABLES:-1}"
# Optional comma-separated Figure numbers for re-running selected figures through
# the complete-region + vision-AI recovery path (for example: "2,4").
export LENS_FIGURE_AI_FORCE_NUMBERS="${LENS_FIGURE_AI_FORCE_NUMBERS:-}"
# Structured-note to PowerPoint defaults. The converter accepts one Markdown
# note path and writes <note-stem>.pptx inside assets/<note-stem>/ by default.
export LENS_NOTE_TO_PPT_ASPECT_RATIO="${LENS_NOTE_TO_PPT_ASPECT_RATIO:-16:9}"
export LENS_NOTE_TO_PPT_PRESENTER="${LENS_NOTE_TO_PPT_PRESENTER:-JGH}"
export LENS_NOTE_TO_PPT_EXCLUDED_SECTIONS="${LENS_NOTE_TO_PPT_EXCLUDED_SECTIONS:-Works|Question–Method Map|Key references}"
export FOLLOWUP_CODEX_MODEL="${FOLLOWUP_CODEX_MODEL:-$CODEX_EXEC_MODEL}"
export FOLLOWUP_SUMMARY_BATCH_SIZE="${FOLLOWUP_SUMMARY_BATCH_SIZE:-8}"
export FOLLOWUP_SUMMARY_LIMIT="${FOLLOWUP_SUMMARY_LIMIT:-24}"
export FOLLOWUP_SUMMARY_MAX_ATTEMPTS="${FOLLOWUP_SUMMARY_MAX_ATTEMPTS:-3}"


# Automatically generated paths
export READING_DIR="$LITERATURE_DIR/Reading"
export AI_DRAFT_DIR="$READING_DIR/ai-draft"
export AI_DRAFT_ASSET_DIR="$AI_DRAFT_DIR/assets"
export READING_LIST_CANVAS="$READING_DIR/Reading_list.canvas"
export LIB_DIR="$LITERATURE_DIR/Library"
export SYNTHESIS_DIR="$LITERATURE_DIR/Synthesis"
export FOLLOWUP_DIR="$LITERATURE_DIR/Followup"
export FOLLOWUP_WEEKLY_DIR="$FOLLOWUP_DIR/Weekly"
export FOLLOWUP_PROJECTS_DIR="$FOLLOWUP_DIR/Projects"
export WIKI_DIR="$LITERATURE_DIR/Wiki"
export READING_WIKI_DIR="$WIKI_DIR/Reading"
export LIBRARY_WIKI_DIR="$WIKI_DIR/Library"
export READING_WIKI_PAGES_DIR="$READING_WIKI_DIR/pages"
export READING_WIKI_DATA_DIR="$READING_WIKI_DIR/data"
export READING_WIKI_GRAPH_VIEW_DIR="$READING_WIKI_DIR/GraphView"
export LIBRARY_WIKI_PAGES_DIR="$LIBRARY_WIKI_DIR/pages"
export LIBRARY_WIKI_DATA_DIR="$LIBRARY_WIKI_DIR/data"
export LIBRARY_WIKI_GRAPH_VIEW_DIR="$LIBRARY_WIKI_DIR/GraphView"
export LOG_DIR="$SYSTEM_DIR/logs"
export CACHE_DIR="$SYSTEM_DIR/cache"
# Persistent LENS data. Unlike CACHE_DIR, this directory must not be cleared.
export DATA_DIR="$SYSTEM_DIR/data"
export LITERATURE_FOLLOWUP_DATA_DIR="$DATA_DIR/literature_followup"
export FOLLOWUP_DB="$LITERATURE_FOLLOWUP_DATA_DIR/literature_followup.sqlite3"
export FOLLOWUP_SOURCE_CONFIG="$SYSTEM_DIR/config/followup_sources.json"
export FOLLOWUP_CACHE_DIR="$CACHE_DIR/literature_followup"
export FOLLOWUP_LOG_DIR="$LOG_DIR/literature_followup"
export REFERENCE_DIR="$LENS_SKILL_DIR/references"
export TEMPLATE_DIR="$LENS_SKILL_DIR/assets/templates"
export PROMPT_DIR="$CACHE_DIR/ingest_prompts"
export SCRIPT_DIR="$LENS_SKILL_DIR/scripts"
export FOLLOWUP_SCRIPT_DIR="$FOLLOWUP_SKILL_DIR/scripts"
export FOLLOWUP_TEMPLATE_DIR="$FOLLOWUP_SKILL_DIR/assets/templates"
