#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"
source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

mkdir -p "$READING_DIR"

python3 - "$RAW_DIR" "$READING_QUEUE_DIRS" "$READING_LIST_CANVAS" "$OBSIDIAN_VAULT_DIR" "${READING_LIST_RESET_LAYOUT:-0}" <<'PY'
import hashlib
import json
import math
import os
import sys
from pathlib import Path

raw_dir = Path(sys.argv[1]).expanduser().resolve()
queue_dirs = [
    Path(value).expanduser().resolve()
    for value in sys.argv[2].split(os.pathsep)
    if value.strip()
]
canvas_path = Path(sys.argv[3]).expanduser().resolve()
vault_dir = Path(sys.argv[4]).expanduser().resolve()
reset_layout = sys.argv[5] == "1"

if not raw_dir.is_dir():
    raise SystemExit(f"Raw paper directory not found: {raw_dir}")

try:
    raw_dir.relative_to(vault_dir)
    canvas_path.relative_to(vault_dir)
except ValueError as exc:
    raise SystemExit(
        "RAW_DIR and Reading Canvas must be inside OBSIDIAN_VAULT_DIR: "
        f"{vault_dir}"
    ) from exc

pdf_path_set = {
    path.resolve()
    for path in raw_dir.glob("*")
    if path.is_file() and path.suffix.lower() == ".pdf"
}
for queue_dir in queue_dirs:
    if not queue_dir.is_dir():
        continue
    pdf_path_set.update(
        path.resolve()
        for path in queue_dir.rglob("*")
        if path.is_file() and path.suffix.lower() == ".pdf"
    )

pdf_paths = sorted(pdf_path_set, key=lambda path: (path.name.casefold(), path.as_posix()))
pdf_files = [path.relative_to(vault_dir).as_posix() for path in pdf_paths]

existing_nodes = []
if canvas_path.exists() and not reset_layout:
    try:
        existing_nodes = json.loads(canvas_path.read_text(encoding="utf-8")).get("nodes", [])
    except (json.JSONDecodeError, OSError):
        existing_nodes = []

existing_cards = {
    node.get("file"): node
    for node in existing_nodes
    if node.get("type") == "file" and node.get("file")
}

columns = 3
slot_width = 400
slot_height = 560
x_gap = 40
y_gap = 40
x_pitch = slot_width + x_gap
y_pitch = slot_height + y_gap
card_x_offset = 20
card_y_offset = 35
card_width = 360
card_height = 500


def stable_id(prefix: str, value: str) -> str:
    return hashlib.sha1(f"{prefix}:{value}".encode("utf-8")).hexdigest()[:16]


def occupied_slot(node: dict) -> int | None:
    try:
        x = float(node["x"])
        y = float(node["y"])
    except (KeyError, TypeError, ValueError):
        return None
    if x < 0 or y < 0:
        return None
    col = int(x // x_pitch)
    row = int(y // y_pitch)
    if not 0 <= col < columns:
        return None
    slot_x = col * x_pitch
    slot_y = row * y_pitch
    if x > slot_x + slot_width or y > slot_y + slot_height:
        return None
    return row * columns + col


occupied = {
    slot
    for file_path, node in existing_cards.items()
    if file_path in pdf_files and (slot := occupied_slot(node)) is not None
}

new_files = [file_path for file_path in pdf_files if file_path not in existing_cards]
next_slots = []
candidate = 0
while len(next_slots) < len(new_files):
    if candidate not in occupied:
        next_slots.append(candidate)
        occupied.add(candidate)
    candidate += 1

slot_by_new_file = dict(zip(new_files, next_slots))
highest_slot = max(occupied, default=-1)
slot_count = max(9, len(pdf_files), highest_slot + 1)
slot_count = math.ceil(slot_count / columns) * columns

nodes = []
for index in range(slot_count):
    row, col = divmod(index, columns)
    nodes.append(
        {
            "id": stable_id("slot", str(index + 1)),
            "type": "group",
            "x": col * x_pitch,
            "y": row * y_pitch,
            "width": slot_width,
            "height": slot_height,
            "label": str(index + 1),
        }
    )

for file_path in pdf_files:
    if file_path in existing_cards:
        old = existing_cards[file_path]
        card = {
            "id": old.get("id") or stable_id("pdf", file_path),
            "type": "file",
            "file": file_path,
            "subpath": old.get("subpath", "#page=1"),
            "x": old.get("x", card_x_offset),
            "y": old.get("y", card_y_offset),
            "width": old.get("width", card_width),
            "height": old.get("height", card_height),
        }
        if "color" in old:
            card["color"] = old["color"]
    else:
        index = slot_by_new_file[file_path]
        row, col = divmod(index, columns)
        card = {
            "id": stable_id("pdf", file_path),
            "type": "file",
            "file": file_path,
            "subpath": "#page=1",
            "x": col * x_pitch + card_x_offset,
            "y": row * y_pitch + card_y_offset,
            "width": card_width,
            "height": card_height,
        }
    nodes.append(card)

canvas = {"nodes": nodes, "edges": []}
canvas_path.write_text(
    json.dumps(canvas, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

print(f"Reading list PDFs: {len(pdf_files)}")
print(f"Canvas:   {canvas_path}")
PY
