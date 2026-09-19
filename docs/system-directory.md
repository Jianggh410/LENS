# System directories and cleanup

This document describes the directories under `_system/`, their responsibilities, whether they may be cleaned, the impact of removal, and whether LENS recreates them automatically.

## Cleanup summary

| Path | Purpose | Safe to clean? | Impact if removed | Recreated automatically? |
| --- | --- | --- | --- | --- |
| `cache/` | Disposable PDF conversion, prompt, queue, and AI-response intermediates | Yes, when no LENS process is running | The next run must regenerate or redownload intermediate data | Yes |
| `logs/` | Timestamped runtime and follow-up logs | Yes, periodically | Historical debugging records are lost | Yes, when a workflow writes logs |
| `data/` | Persistent SQLite databases and workflow state | No | Follow-up history, processing state, and attempt records may be lost | Directory: yes; lost state: no |
| `config/` | Runtime variables and literature-source registry | No | Paths, projects, sources, and workflow behavior are lost or invalid | No |
| `skills/` | LENS Skills, rules, templates, schemas, configs, and workflow scripts | No | LENS capabilities stop working | No |
| `scripts/` | Repository installation, update, and validation utilities | No | Maintenance and validation commands become unavailable | No |
| `docs/` | Operational and development documentation | Not recommended | Runtime may continue, but maintenance guidance is lost | No |
| `assets/` | Images and other attachments used by repository documentation | Not recommended | README images and documentation attachments break | No |
| `.git/` | Git history and repository metadata | No | Version control and safe updates break | No |

## `cache/`

`cache/` is a disposable runtime workspace and is excluded from Git. It is not the literature database or an authoritative output location.

Expected subdirectories:

```text
cache/
├── ingest_markdown/       # Markdown converted from source PDFs
├── ingest_prompts/        # Generated ingestion prompts and note inventories
├── literature_followup/   # Pending records, prompts, and structured AI responses
└── assets/                # Reserved temporary generated assets
```

- `skills/lens-paper-note/scripts/ingest_paper.sh` uses `ingest_markdown/` and `ingest_prompts/`.
- `skills/lens-literature-followup/scripts/run_followup.sh` uses `literature_followup/`.
- Subdirectories are created on demand and may be absent or empty between runs.
- If `_system/cache` is not writable, paper ingestion falls back to `${TMPDIR:-/tmp}/literature_ingest_cache` for that run.

Before clearing it, confirm that no ingestion, extraction, or follow-up process is running. Clearing cache does not remove source PDFs, structured Markdown files, associated assets, Wiki pages, or the persistent follow-up database.

## `data/`

`data/` contains persistent machine state and must not be treated as cache. The main current state is the literature-follow-up SQLite database:

```text
data/literature_followup/literature_followup.sqlite3
```

It records fetched publications, project matching, summarization status, attempts, and history. SQLite files are excluded from Git; `.gitkeep` only preserves the directory structure. Back up this directory before migration or destructive maintenance.

## `config/`

- `lens_config.sh` defines or derives the Literature workspace, paper inbox, research projects, models, Figure extraction behavior, PPT defaults, and runtime paths.
- `followup_sources.json` defines journal RSS feeds and preprint sources.

Environment variables can override portable settings for one run. Do not delete configuration files unless you intend to rebuild the configuration manually.

## `skills/`

- `lens-paper-note/`: full-paper Article/Review reading, structured Markdown generation, Figure/Table extraction, Wiki rebuilding, Reading Canvas, and file-status utilities.
- `lens-literature-followup/`: RSS/API fetching, project matching, persistent state, AI summaries, and weekly/project follow-up pages.
- `lens-paper-note-to-ppt/`: conversion of a LENS note into a figure-led PowerPoint using `ppt.config`.

Each Skill is self-contained and may include `SKILL.md`, `agents/`, `references/`, `assets/`, `scripts/`, schemas, templates, or dedicated configuration.

## `scripts/`

- `install.sh`: links supported Skills into the Codex Skills directory.
- `update.sh`: performs a safe fast-forward repository update, validation, and reinstallation.
- `validate.sh`: validates required files, syntax, JSON, configuration, and derived paths.

Paper-specific execution scripts belong to their corresponding Skill directories.

## `docs/`

- `installation.md`: setup and installation.
- `configuration.md`: runtime configuration and source registry.
- `workflow.md`: end-to-end literature workflow.
- `troubleshooting.md`: common failures and recovery.
- `system-directory.md`: this English directory and cleanup guide.
- `system-directory_CN.md`: Chinese directory and cleanup guide.

## `assets/`

Stores version-controlled attachments used by the repository documentation, including README screenshots. This directory is separate from:

- `cache/assets/`, which is disposable;
- `Reading/ai-draft/assets/<note-stem>/`, which contains note-specific figures and PPTX files;
- Library-local assets, which belong to curated notes.

## `logs/`

Created on demand and excluded from Git. Literature follow-up writes timestamped logs under `logs/literature_followup/`. Logs may be removed periodically after they are no longer needed for debugging.

## Files at the `_system` root

- `README.md`: default Chinese project documentation rendered on the GitHub repository homepage.
- `README_EN.md`: English project documentation linked from `README.md`.
- `LICENSE`: repository license.
- `.gitignore`: excludes cache, logs, databases, and local noise.
- `.git/`: Git history and metadata; never edit or clean it manually.

## Authoritative outputs outside `_system`

User-facing outputs intentionally live in the parent `Literature/` workspace:

- `Reading/ai-draft/`: AI-generated paper notes.
- `Reading/ai-draft/assets/<note-stem>/`: extracted visuals and generated PPTX files.
- `Library/`: curated notes and their assets.
- `Synthesis/`: cross-paper synthesis notes.
- `Followup/`: weekly and project-level follow-up pages.
- `Wiki/Reading/` and `Wiki/Library/`: generated pages, JSON indexes, and GraphView files.

Source PDFs remain the source of truth and normally live under the configured `RAW_DIR` or another user-supplied path.
