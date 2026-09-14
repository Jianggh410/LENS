# Run Weekly Follow-up

1. Source `../../config/lens_config.sh`.
2. Fetch the configured overlap window from every enabled source.
3. Normalize and upsert records into SQLite.
4. Recompute literal project matches from `USER_RESEARCH`.
5. Send only `summary_pending` records to Codex in bounded batches.
6. Import valid structured responses without deleting failed pending records.
7. Render `Followup/index.md`, `Followup/Weekly/`, and `Followup/Projects/`.
8. Report fetched, changed, matched, completed, and pending counts.

Use `--no-ai` for deterministic fetch/match/render testing. Use `--summaries-only` to retry pending records without fetching feeds again.
