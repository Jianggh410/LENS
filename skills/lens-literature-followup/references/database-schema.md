# Database Schema

The authoritative state lives in `$FOLLOWUP_DB`.

- `sources`: configured source identity and last successful fetch.
- `articles`: normalized current metadata and summary state.
- `matches`: article-to-project keyword evidence and first match time.
- `summaries`: abstract-grounded Chinese summary and project relevance JSON.
- `runs`: fetch/match execution history and error messages.

Canonical identity priority is DOI, canonical URL, then normalized-title SHA-256. Content changes invalidate old matches and summaries so revised preprints can be processed again.
