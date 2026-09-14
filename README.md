# LENS

LENS is a Codex Skill and script-based workflow for monitoring new literature, matching it to configured research projects, converting selected papers into structured Chinese Obsidian notes, extracting numbered figures, and maintaining literature knowledge indexes.

## Repository layout

```text
_system/
├── README.md
├── LICENSE
├── docs/
├── scripts/                         # Install, update, and validation utilities
├── skills/
│   ├── lens-paper-note/             # Full-paper reading and note Skill
│   └── lens-literature-followup/    # RSS/API monitoring and triage Skill
├── config/                          # Runtime configuration retained in Literature
├── data/                            # Persistent SQLite and other LENS data
├── cache/                           # Generated conversion cache
└── logs/                            # Runtime logs
```

The installable Skill contains its own `SKILL.md`, references, executable workflow scripts, and note templates. Runtime cache and logs remain under `_system`; generated Reading and Library indexes are written to the top-level `Literature/Wiki/` directory for direct Obsidian access.

## Quick start

Validate and install the Skill for Codex discovery:

```bash
bash scripts/validate.sh
bash scripts/install.sh
```

Ingest one paper directly:

```bash
bash skills/lens-paper-note/scripts/ingest_paper.sh "/absolute/path/paper.pdf"
```

Or ask Codex: `Use LENS to read this paper and create a structured literature note.`

Run literature follow-up without AI summarization:

```bash
bash skills/lens-literature-followup/scripts/run_followup.sh --no-ai
```

Run the complete follow-up workflow:

```bash
bash skills/lens-literature-followup/scripts/run_followup.sh
```

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Workflow](docs/workflow.md)
- [Troubleshooting](docs/troubleshooting.md)
