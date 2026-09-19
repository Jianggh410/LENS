---
name: lens-literature-followup
description: Monitor configured scientific journal RSS feeds and bioRxiv, deduplicate new articles in SQLite, match title or abstract text against LENS USER_RESEARCH projects, generate abstract-grounded Chinese summaries, and maintain weekly and project-based Markdown follow-up pages. Trigger for literature follow-up, weekly paper monitoring, RSS journal tracking, bioRxiv tracking, research-keyword alerts, pending follow-up summaries, or follow-up status checks.
---

# LENS Literature Follow-up

Use the shared runtime configuration at `../../config/lens_config.sh`. This Skill discovers and triages papers; use the sibling `lens-paper-note` Skill only after User chooses a paper for full-text reading.

## Route the task

- **Run the complete weekly workflow:** read `references/workflows/run-weekly.md`, then run `scripts/run_followup.sh`.
- **Fetch and match without AI:** run `scripts/run_followup.sh --no-ai`.
- **Retry pending summaries:** run `scripts/run_followup.sh --summaries-only`.
- **Rebuild Markdown from SQLite:** run `scripts/followup.py render`.
- **Inspect status:** run `scripts/followup.py status`.
- **Configure sources:** read `references/source-rules.md`, then edit the shared source registry specified by `$FOLLOWUP_SOURCE_CONFIG`.
- **Configure matching:** read `references/matching-rules.md`; research projects come from `$USER_RESEARCH`.
- **Install or remove the weekly macOS schedule:** run `scripts/install_launchd.sh install` or `scripts/install_launchd.sh uninstall` only when User explicitly requests it.

## Operating rules

1. A title or abstract must contain at least one configured keyword before an article can enter the AI summary queue.
2. Treat follow-up summaries as abstract-level triage, never as full-paper reading notes.
3. Never invent missing abstracts, methods, results, data accessions, or publication status.
4. Keep fetched records and pending work in SQLite so an AI or network failure does not lose the run.
5. Do not generate a `Reading/ai-draft` note automatically. Promotion to full reading is a separate User decision.
6. Do not edit generated `Followup/` pages manually; rebuild them from SQLite.
7. Do not install a scheduler or make network calls unless the current task requires it.
