# Source Rules

- Keep source definitions in `$FOLLOWUP_SOURCE_CONFIG`, not in executable scripts.
- Supported source types are `rss` and `biorxiv`.
- Each source needs a stable lowercase `id`, display `name`, `type`, and `enabled` flag.
- RSS sources also need `url` and normally `journal`.
- A bioRxiv source needs `server` and may restrict `categories`.
- Prefer publisher RSS or official APIs. Do not scrape search-result pages.
- Crossref enrichment is metadata fallback only. Missing Crossref abstracts must remain missing.
- Disable a source with `"enabled": false`; do not delete historical database records.
