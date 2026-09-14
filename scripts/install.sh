#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
skills=(lens-paper-note lens-literature-followup)

mkdir -p "$CODEX_HOME/skills"
for skill in "${skills[@]}"; do
  skill_source="$ROOT_DIR/skills/$skill"
  skill_target="$CODEX_HOME/skills/$skill"
  if [[ ! -f "$skill_source/SKILL.md" ]]; then
    echo "Missing LENS Skill: $skill_source/SKILL.md" >&2
    exit 1
  fi
  if [[ -L "$skill_target" ]]; then
    current_target="$(readlink "$skill_target")"
    if [[ "$current_target" == "$skill_source" ]]; then
      echo "LENS Skill is already installed: $skill_target"
      continue
    fi
    rm "$skill_target"
  elif [[ -e "$skill_target" ]]; then
    echo "Install target already exists and is not a symbolic link: $skill_target" >&2
    echo "Move or remove it manually, then rerun this installer." >&2
    exit 1
  fi
  ln -s "$skill_source" "$skill_target"
  echo "Installed LENS Skill: $skill_target -> $skill_source"
done
