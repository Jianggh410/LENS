# Installation

## Requirements

- Codex CLI
- `markitdown`
- `uv`
- Bash 3.2 or newer
- Python 3

## Install for Codex discovery

From the `_system` directory, run:

```bash
bash scripts/install.sh
```

The installer creates these symbolic links by default:

```text
~/.codex/skills/lens-paper-note -> <Literature>/_system/skills/lens-paper-note
~/.codex/skills/lens-literature-followup -> <Literature>/_system/skills/lens-literature-followup
```

Using a symbolic link keeps the installed Skill synchronized with this repository and preserves access to the runtime configuration three levels above the Skill scripts.

Override the Codex home directory when needed:

```bash
CODEX_HOME=/custom/codex/home bash scripts/install.sh
```

Run `bash scripts/validate.sh` after installation.

The follow-up scheduler is optional and is not installed by the main installer. On macOS, install it explicitly with:

```bash
bash skills/lens-literature-followup/scripts/install_launchd.sh install
```

The default schedule is Monday at 08:00 local time.
