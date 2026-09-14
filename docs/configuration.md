# Configuration

Runtime settings live in:

```text
config/lens_config.sh
```

Important variables:

| Variable | Purpose |
|---|---|
| `LITERATURE_DIR` | Root containing Reading, Library, and Synthesis |
| `LENS_SYSTEM_DIR` | Optional override for the runtime `_system` directory |
| `RAW_DIR` | Default paper inbox |
| `READING_QUEUE_DIRS` | Additional Reading Canvas queues |
| `OBSIDIAN_VAULT_DIR` | Vault root for Canvas file links |
| `USER_RESEARCH` | JSON object mapping research-project names to matching keywords |
| `CODEX_EXEC_MODEL` | Codex model used by ingest scripts |
| `FOLLOWUP_CODEX_MODEL` | Codex model used for abstract-level follow-up summaries |
| `FOLLOWUP_SUMMARY_BATCH_SIZE` | Articles sent to one structured summary call |
| `FOLLOWUP_SUMMARY_LIMIT` | Maximum summaries attempted in one run |
| `FOLLOWUP_SUMMARY_MAX_ATTEMPTS` | Failed attempts allowed before manual reset |
| `DATA_DIR` | Persistent LENS runtime data; do not clear it like cache |
| `LITERATURE_FOLLOWUP_DATA_DIR` | Persistent database directory for literature follow-up |

The configuration derives the Skill, cache, and log paths from its own `_system` location. Generated Wiki content is written to the top-level `Literature/Wiki/` directory. It exports generated paths for Reading, Library, Synthesis, Wiki, scripts, references, and templates. Override user variables in the environment before running a script instead of editing executable files.

`USER_RESEARCH` must be valid JSON. Each key is a research project and each value is the list of keywords used to explain research relevance and, later, to match literature-followup records.

When `lens-paper-note` writes `### My Research` under `# Discussion`, it creates one `#### <Project name>` subsection for every configured project in JSON key order. Each subsection discusses that project's relevance separately and concisely; weakly related projects are identified rather than omitted.

```json
{
  "E2G_mediator": ["Gene regulation", "Enhancer", "Mediator"],
  "E2G_prediction": ["Enhancer", "Deep learning", "S2F"]
}
```

Persistent databases belong under `data/`, while disposable API responses and converted files belong under `cache/`. Runtime SQLite files are intentionally excluded from Git.

Journal and preprint sources are configured in `config/followup_sources.json`. It supports generic RSS sources and the official bioRxiv API adapter. Disable a source with `"enabled": false` without deleting its historical records.

Example:

```bash
RAW_DIR="/path/to/papers" CODEX_EXEC_MODEL="gpt-5.5" \
  bash skills/lens-paper-note/scripts/batch_ingest.sh
```
