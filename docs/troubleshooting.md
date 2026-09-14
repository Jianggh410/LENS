# Troubleshooting

## Validate the installation

```bash
bash scripts/validate.sh
```

## Codex does not discover LENS

Run `bash scripts/install.sh`, verify that `~/.codex/skills/lens-paper-note` is a symbolic link, and restart the Codex session if the Skill list was loaded before installation.

## Missing configuration

Workflow scripts locate `config/lens_config.sh` relative to their physical repository path. If scripts are copied elsewhere instead of symlinked, set an explicit path:

```bash
LENS_CONFIG_FILE="/absolute/path/to/config/lens_config.sh" \
  bash /path/to/ingest_paper.sh "/path/to/paper.pdf"
```

## Figure extraction finds no figures

Confirm that the Article note contains numbered `## Fig. N ...` or `## Figure N ...` headings under `# Results`. Inspect the matching `figures.json` for caption or crop failures.

## Codex reconnects or fails

Inspect the paper-specific files in `logs/`. The converted Markdown remains in `cache/ingest_markdown/`, so the source conversion does not need to be repeated manually.
