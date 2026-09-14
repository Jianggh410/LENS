---
name: lens-paper-note
description: Use LENS to convert scientific papers into structured Chinese Obsidian notes, extract numbered PDF figures and Review tables, maintain Reading and Library wikis, manage the reading Canvas, and create cross-paper synthesis. Trigger for LENS, paper ingestion, literature notes, ai-draft notes, figure or table extraction, literature wiki rebuilds, or LENS status checks.
---

# LENS Paper Note

Use the runtime configuration at `../../config/lens_config.sh`. It keeps cache and logs under `_system`, writes generated wikis to the top-level `Literature/Wiki/` directory, and keeps user notes in the Literature workspace while this skill provides rules, templates, and executable workflows.

## Route the task

- **Ingest one paper:** read `references/workflows/ingest-paper.md`, `references/note-rules.md`, `references/metadata-rules.md`, `references/citation-rules.md`, `references/narrative-taxonomy.md`, and `references/typography-rules.md`; then run `scripts/ingest_paper.sh <paper-path>`.
- **Batch ingest:** read `references/workflows/batch-ingest.md`; then run `scripts/batch_ingest.sh`.
- **Extract or replace figures/tables:** read `references/figure-rules.md` and `references/workflows/extract-figures.md`; then run `scripts/extract_figures.sh <paper.pdf> <note.md> [--replace-existing]`.
- **Rebuild wikis:** read `references/wiki-rules.md` and `references/workflows/rebuild-wiki.md`; then run `scripts/rebuild_wiki.sh`.
- **Synchronize the Reading Canvas:** run `scripts/rebuild_reading_list.sh` only when the user explicitly requests synchronization.
- **Create synthesis:** read `references/workflows/create-synthesis.md` and the synthesis rules in `references/note-rules.md`.
- **Inspect status:** run `scripts/lens_status.sh`, `scripts/list_ai_drafts.sh`, or `scripts/list_human_reviewed.sh` as appropriate.

## Operating rules

1. Treat the original PDF as the source of truth.
2. Use `assets/templates/Article_note_template.md` or `assets/templates/Review_note_template.md` without dropping required YAML fields or sections.
3. Keep explanatory note text in Chinese and the paper title and scientific terms in their conventional English form.
4. Never invent metadata, laboratory websites, data accessions, methods, results, citations, or figure interpretations.
5. Do not manually edit generated wiki outputs; use the deterministic scripts.
6. Preserve user-edited notes and assets. Do not overwrite an existing note unless the user explicitly requests an update.
7. Report the created or modified note paths and any extraction or validation failures.
