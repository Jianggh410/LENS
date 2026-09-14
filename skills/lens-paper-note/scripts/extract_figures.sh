#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"
source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  bash extract_figures.sh /absolute/path/paper.pdf /absolute/path/note.md [--replace-existing]

Behavior:
  1. Read numbered Fig./Figure headings under # Results (Article), plus
     Fig./Figure/Table headings under # Evidence (Review).
  2. Locate matching captions/titles in the PDF and crop complete visual regions.
  3. Use full-page vision-AI isolation and panel verification when geometry is uncertain.
  4. Save stable Fig-NN.png or Table-NN.png files and figures.json beside the note assets.
  5. Insert only verified visuals as idempotent HTML blocks below matching headings.

Safety:
  Existing image blocks are skipped unless --replace-existing is supplied.
USAGE
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

pdf_path="$1"
note_path="$2"
replace_existing=0
if [[ ${3:-} == "--replace-existing" ]]; then
  replace_existing=1
elif [[ $# -eq 3 ]]; then
  usage
  exit 1
fi

if [[ ! -f "$pdf_path" ]]; then
  echo "PDF not found: $pdf_path" >&2
  exit 1
fi
if [[ ! -f "$note_path" ]]; then
  echo "Note not found: $note_path" >&2
  exit 1
fi
if [[ "${pdf_path##*.}" != "pdf" && "${pdf_path##*.}" != "PDF" ]]; then
  echo "Figure extraction currently supports PDF input only: $pdf_path" >&2
  exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required to run the isolated PyMuPDF figure extractor." >&2
  exit 1
fi

note_dir="$(cd "$(dirname "$note_path")" && pwd)"
note_name="$(basename "$note_path")"
note_stem="${note_name%.md}"
asset_root="$note_dir/assets"
asset_dir="$asset_root/$note_stem"
mkdir -p "$asset_dir"

uv run --quiet --with pymupdf --with pillow python - \
  "$pdf_path" "$note_path" "$asset_dir" "$replace_existing" <<'PY'
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import pymupdf
from PIL import Image

pdf_path = Path(sys.argv[1]).resolve()
note_path = Path(sys.argv[2]).resolve()
asset_dir = Path(sys.argv[3]).resolve()
replace_existing = sys.argv[4] == "1"
ai_fallback_enabled = os.environ.get("LENS_FIGURE_AI_FALLBACK", "1") != "0"
ai_model = os.environ.get("LENS_FIGURE_AI_MODEL", os.environ.get("CODEX_EXEC_MODEL", "gpt-5.5"))
ai_timeout_seconds = int(os.environ.get("LENS_FIGURE_AI_TIMEOUT_SECONDS", "240"))
figure_top_safety_margin = float(os.environ.get("LENS_FIGURE_TOP_SAFETY_MARGIN", "10"))
clamp_to_main_frame = os.environ.get("LENS_FIGURE_CLAMP_TO_MAIN_FRAME", "1") != "0"
figure_edge_clearance = float(os.environ.get("LENS_FIGURE_EDGE_CLEARANCE", "1"))
include_original_caption = (
    os.environ.get("LENS_FIGURE_INCLUDE_ORIGINAL_CAPTION", "1") != "0"
)
figure_caption_padding_pt = float(
    os.environ.get("LENS_FIGURE_CAPTION_PADDING_PT", "6")
)
figure_ai_bbox_padding_pt = float(
    os.environ.get("LENS_FIGURE_AI_BBOX_PADDING_PT", "10")
)
figure_render_scale = 2.5
review_horizontal_adjacency_enabled = os.environ.get(
    "LENS_REVIEW_HORIZONTAL_ADJACENCY", "1"
) != "0"
review_panel_label_styles = {
    value.strip().lower()
    for value in os.environ.get(
        "LENS_REVIEW_PANEL_LABEL_STYLES", "parenthesized,pipe,dot"
    ).split(",")
    if value.strip()
}
ai_force_numbers = {
    int(value)
    for value in re.findall(r"\d+", os.environ.get("LENS_FIGURE_AI_FORCE_NUMBERS", ""))
}

note_text = note_path.read_text(encoding="utf-8")
lines = note_text.splitlines(keepends=True)
note_type_match = re.search(r"(?mi)^type:\s*([^\r\n#]+)", note_text)
note_type = note_type_match.group(1).strip().lower() if note_type_match else ""
is_review_note = note_type == "review"
review_extract_tables_enabled = (
    os.environ.get("LENS_REVIEW_EXTRACT_TABLES", "1") != "0"
)


def visual_key(kind, number):
    return f"{kind}:{number}"


def extractable_visual_headings(source_lines):
    active_section = None
    headings = []
    pattern = re.compile(
        r"^##\s+(Fig\.|Figure|Table)\s*(\d+)\s*[.：:\-]?\s+(.+?)\s*$",
        re.I,
    )
    for index, line in enumerate(source_lines):
        stripped = line.rstrip("\r\n")
        if stripped in {"# Results", "# Evidence"}:
            active_section = stripped[2:]
            continue
        if active_section and stripped.startswith("# "):
            active_section = None
        if not active_section:
            continue
        match = pattern.match(stripped)
        if match:
            token = match.group(1).lower()
            kind = "table" if token == "table" else "figure"
            if kind == "table" and not (
                is_review_note
                and active_section == "Evidence"
                and review_extract_tables_enabled
            ):
                continue
            number = int(match.group(2))
            headings.append({
                "kind": kind,
                "key": visual_key(kind, number),
                "number": number,
                "title": match.group(3).strip(),
                "line_index": index,
                "section": active_section,
            })
    return headings


def section_bounds(source_lines, heading_index):
    end = len(source_lines)
    for index in range(heading_index + 1, len(source_lines)):
        if source_lines[index].startswith("## ") or source_lines[index].startswith("# "):
            end = index
            break
    return heading_index + 1, end


def has_existing_image(section):
    text = "".join(section)
    return bool(re.search(r"<img\b|!\[\[|!\[[^\]]*\]\(", text, re.I))


def strip_managed_block(section, kind, number):
    start_marker = f"<!-- {kind}:{number}:start -->"
    end_marker = f"<!-- {kind}:{number}:end -->"
    text = "".join(section)
    pattern = re.compile(
        rf"\s*{re.escape(start_marker)}.*?{re.escape(end_marker)}\s*",
        re.S,
    )
    cleaned = pattern.sub("", text, count=1).lstrip("\r\n")
    return cleaned.splitlines(keepends=True)


def normalize_caption(text):
    return " ".join(text.replace("\u00ad", "").split())


def caption_candidates(document, wanted_items):
    candidates = {}
    wanted_set = {item["key"] for item in wanted_items}
    # Require a caption delimiter after the visual number. This excludes
    # in-text references such as "Fig. 3b" that may begin a PDF text block.
    pattern = re.compile(
        r"^(Fig\.|Figure|Table)\s*(\d+)(?=\s|[|.:]|$)",
        re.I,
    )
    for page_index, page in enumerate(document):
        for block in page.get_text("blocks", sort=True):
            text = normalize_caption(block[4])
            match = pattern.match(text)
            if not match:
                continue
            token = match.group(1).lower()
            kind = "table" if token == "table" else "figure"
            number = int(match.group(2))
            key = visual_key(kind, number)
            if key not in wanted_set or key in candidates:
                continue
            candidates[key] = {
                "kind": kind,
                "caption_page": page_index,
                "caption_bbox": [float(value) for value in block[:4]],
                "caption": text,
            }
    # PyMuPDF can split a long caption into side-by-side column blocks. Merge
    # an adjacent continuation when it overlaps the caption row and carries
    # later panel enumerators (for example, a left block ending at f and a
    # right block containing g-k).
    panel_enumerator = re.compile(
        r"(?:^|\s)([a-z](?:\s*(?:,|[-–])\s*[a-z])*)\s*,\s+(?=[A-Z])"
    )
    for candidate in candidates.values():
        page = document[candidate["caption_page"]]
        base = pymupdf.Rect(candidate["caption_bbox"])
        additions = []
        for block in page.get_text("blocks", sort=True):
            other_text = normalize_caption(block[4])
            if not other_text or other_text == candidate["caption"]:
                continue
            other = pymupdf.Rect(block[:4])
            overlap = max(0.0, min(base.y1, other.y1) - max(base.y0, other.y0))
            minimum_height = max(1.0, min(base.height, other.height))
            horizontally_adjacent = (
                other.x0 >= base.x1 - 12.0 or other.x1 <= base.x0 + 12.0
            )
            if (
                overlap / minimum_height >= 0.65
                and horizontally_adjacent
                and len(other_text) >= 80
                and panel_enumerator.search(other_text)
            ):
                additions.append((other.x0, other_text, other))
        for _, other_text, other in sorted(additions):
            candidate["caption"] += " " + other_text
            base |= other
        candidate["caption_bbox"] = [float(value) for value in base]
    return candidates


def prose_bottom(page, minimum_y, default_bottom):
    prose_y = []
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        clean = normalize_caption(text)
        words = clean.split()
        alpha_words = sum(any(char.isalpha() for char in word) for word in words)
        if y0 <= minimum_y or alpha_words < 30:
            continue
        if len(clean) < 180:
            continue
        prose_y.append(float(y0))
    return min(prose_y) - 8 if prose_y else default_bottom


def region_metrics(page, top, bottom, left=None, right=None):
    left = 0.0 if left is None else left
    right = page.rect.width if right is None else right
    prose_blocks = 0
    short_blocks = 0
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        if y1 <= top or y0 >= bottom or x1 <= left or x0 >= right:
            continue
        clean = normalize_caption(text)
        words = clean.split()
        alpha_words = sum(any(char.isalpha() for char in word) for word in words)
        if len(clean) >= 180 and alpha_words >= 30:
            prose_blocks += 1
        elif clean and len(clean) <= 100:
            short_blocks += 1

    image_count = 0
    for image in page.get_images(full=True):
        try:
            rects = page.get_image_rects(image[0])
        except Exception:
            rects = []
        if any(
            rect.y1 > top
            and rect.y0 < bottom
            and rect.x1 > left
            and rect.x0 < right
            for rect in rects
        ):
            image_count += 1

    drawing_count = 0
    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if (
            rect
            and rect.y1 > top
            and rect.y0 < bottom
            and rect.x1 > left
            and rect.x0 < right
        ):
            drawing_count += 1

    return {
        "prose_blocks": prose_blocks,
        "short_blocks": short_blocks,
        "image_count": image_count,
        "drawing_count": drawing_count,
    }


def looks_like_figure(metrics):
    return (
        metrics["image_count"] > 0
        or metrics["drawing_count"] >= 50
        or metrics["short_blocks"] >= 15
    )


def caption_panel_labels(caption):
    """Return the ordered panel labels explicitly referenced by a caption."""
    matches = []
    if "parenthesized" in review_panel_label_styles or not is_review_note:
        matches.extend(
            (match.start(), match.group(1).lower())
            for match in re.finditer(r"\(([A-Za-z])\)", caption)
        )
    if is_review_note and "pipe" in review_panel_label_styles:
        matches.extend(
            (match.start(), match.group(1).lower())
            for match in re.finditer(r"(?:^|\s)([a-z])\s*\|\s*", caption)
        )
    if is_review_note and "dot" in review_panel_label_styles:
        matches.extend(
            (match.start(), match.group(1).lower())
            for match in re.finditer(r"(?:^|\s)([a-z])\.\s+(?=[A-Z])", caption)
        )
    # Nature-family captions use individual, grouped, and ranged enumerators:
    # "a, ...", "c,d, ...", and "a-d, ...".
    nature_pattern = re.compile(
        r"(?:^|\s)([a-z](?:\s*(?:,|[-–])\s*[a-z])*)\s*,\s+(?=[A-Z])"
    )
    for match in nature_pattern.finditer(caption):
        token = re.sub(r"\s+", "", match.group(1).lower())
        range_match = re.fullmatch(r"([a-z])[-–]([a-z])", token)
        if range_match:
            start_code = ord(range_match.group(1))
            end_code = ord(range_match.group(2))
            if start_code <= end_code:
                matches.extend(
                    (match.start(), chr(code))
                    for code in range(start_code, end_code + 1)
                )
                continue
        matches.extend(
            (match.start(), label)
            for label in re.findall(r"[a-z]", token)
        )
    labels = []
    for _, label in sorted(matches):
        if label not in labels:
            labels.append(label)
    return labels


def prose_end_before(page, before_y, left=None, right=None):
    """Find the bottom of article prose immediately above a figure region."""
    left = 0.0 if left is None else left
    right = page.rect.width if right is None else right
    endings = []
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        if y1 >= before_y or x1 <= left or x0 >= right:
            continue
        clean = normalize_caption(text)
        words = clean.split()
        alpha_words = sum(any(char.isalpha() for char in word) for word in words)
        if len(clean) < 180 or alpha_words < 30:
            continue
        endings.append(float(y1))
    return max(endings) if endings else None


def science_header_boundary(page):
    """Return the lower edge of a Science-style running header when detectable."""
    header_text_bottom = 0.0
    header_zone = page.rect.height * 0.12
    for block in page.get_text("blocks", sort=True):
        _, y0, _, y1, text = block[:5]
        if y0 >= header_zone:
            continue
        clean = normalize_caption(text).upper()
        if "RESEARCH" in clean or "REPORTS" in clean:
            header_text_bottom = max(header_text_bottom, float(y1))

    header_rule_bottom = 0.0
    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if (
            rect
            and rect.y0 < header_zone
            and rect.width >= page.rect.width * 0.65
            and rect.height <= 4.0
        ):
            header_rule_bottom = max(header_rule_bottom, float(rect.y1))
    return max(header_text_bottom + 4.0, header_rule_bottom, 0.0)


def journal_header_boundary(page):
    """Return the lower edge of common journal running-header content."""
    header_zone = page.rect.height * 0.13
    header_bottom = science_header_boundary(page)
    header_markers = (
        "PLEASE CITE",
        "OPEN ACCESS",
        "ARTICLE",
        "LETTER",
        "REVIEWS",
        "RESEARCH",
        "REPORTS",
    )
    for block in page.get_text("blocks", sort=True):
        _, y0, _, y1, text = block[:5]
        if y0 >= header_zone:
            continue
        clean = normalize_caption(text).upper()
        if clean and any(marker in clean for marker in header_markers):
            header_bottom = max(header_bottom, float(y1))
    return header_bottom


def page_main_content_frame(page):
    """Estimate the journal's main page frame, excluding bleed/header art."""
    width = page.rect.width
    if not clamp_to_main_frame:
        return (
            max(28.0, width * 0.045),
            min(width - 28.0, width * 0.955),
            "main-frame-clamp-disabled",
        )
    header_zone = page.rect.height * 0.14
    wide_header_frames = []
    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if (
            rect
            and rect.y0 < header_zone
            and rect.width >= width * 0.60
            and rect.x0 >= width * 0.03
            and rect.x1 <= width * 0.97
        ):
            wide_header_frames.append(rect)
    if wide_header_frames:
        frame = max(wide_header_frames, key=lambda rect: rect.width)
        return float(frame.x0), float(frame.x1), "running-header-frame"

    header_bottom = journal_header_boundary(page)
    text_lefts = []
    text_rights = []
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        if y0 <= header_bottom + 2.0 or y1 >= page.rect.height - 30.0:
            continue
        if normalize_caption(text):
            text_lefts.append(float(x0))
            text_rights.append(float(x1))
    if text_lefts:
        return (
            max(0.0, min(text_lefts) - 4.0),
            min(width, max(text_rights) + 4.0),
            "body-text-envelope",
        )
    return (
        max(28.0, width * 0.045),
        min(width - 28.0, width * 0.955),
        "page-margin-fallback",
    )


def figure_content_top(
    page,
    before_y,
    after_y=None,
    safety_margin=None,
    span_left=None,
    span_right=None,
):
    """Find the first Figure element inside the main frame and retain headroom."""
    if safety_margin is None:
        safety_margin = figure_top_safety_margin
    header_boundary = journal_header_boundary(page)
    frame_left, frame_right, frame_source = page_main_content_frame(page)
    if span_left is not None:
        frame_left = max(frame_left, span_left)
    if span_right is not None:
        frame_right = min(frame_right, span_right)
    content_floor = max(
        header_boundary + 2.0,
        (after_y + 2.0) if after_y is not None else 0.0,
    )
    search_after = max(header_boundary + 6.0, after_y or 0.0)
    visual_starts = []

    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if (
            rect
            and rect.x1 > frame_left
            and rect.x0 < frame_right
            and rect.y0 >= search_after
            and rect.y0 < before_y
        ):
            visual_starts.append(float(rect.y0))
    for image in page.get_images(full=True):
        try:
            rects = page.get_image_rects(image[0])
        except Exception:
            rects = []
        visual_starts.extend(
            float(rect.y0)
            for rect in rects
            if rect.x1 > frame_left
            and rect.x0 < frame_right
            and rect.y0 >= search_after
            and rect.y0 < before_y
        )
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, _, text = block[:5]
        if (
            x1 <= frame_left
            or x0 >= frame_right
            or y0 < search_after
            or y0 >= before_y
        ):
            continue
        clean = normalize_caption(text)
        if clean and len(clean) < 180:
            visual_starts.append(float(y0))

    first_visual_y = min(visual_starts) if visual_starts else search_after
    top = max(content_floor, first_visual_y - safety_margin)
    return top, {
        "header_boundary": round(header_boundary, 2),
        "first_visual_y": round(first_visual_y, 2),
        "safety_margin": safety_margin,
        "main_frame": [round(frame_left, 2), round(frame_right, 2)],
        "frame_source": frame_source,
        "source": "first-figure-element" if visual_starts else "post-header-or-prose-fallback",
    }


def visual_bottom_in_span(page, top, bottom, left, right):
    """Find the last non-prose Figure object inside one horizontal span."""
    visual_ends = []
    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if (
            rect
            and rect.x1 > left
            and rect.x0 < right
            and rect.y1 > top
            and rect.y0 < bottom
        ):
            visual_ends.append(float(min(rect.y1, bottom)))
    for image in page.get_images(full=True):
        try:
            rects = page.get_image_rects(image[0])
        except Exception:
            rects = []
        visual_ends.extend(
            float(min(rect.y1, bottom))
            for rect in rects
            if rect.x1 > left
            and rect.x0 < right
            and rect.y1 > top
            and rect.y0 < bottom
        )
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        if x1 <= left or x0 >= right or y1 <= top or y0 >= bottom:
            continue
        clean = normalize_caption(text)
        if clean and len(clean) < 180:
            visual_ends.append(float(min(y1, bottom)))
    return max(visual_ends) if visual_ends else bottom


def review_same_page_layout(page, candidate, usable_bottom):
    """Detect Review figures above or beside a narrow same-page caption."""
    if not (is_review_note and review_horizontal_adjacency_enabled):
        return None
    x0, y0, x1, y1 = candidate["caption_bbox"]
    frame_left, frame_right, _ = page_main_content_frame(page)
    frame_width = frame_right - frame_left
    caption_width = x1 - x0
    if frame_width <= 0 or caption_width / frame_width > 0.58:
        return None

    gap = 8.0
    column_left = max(frame_left, x0 - gap)
    column_right = min(frame_right, x1 + gap)

    # A Figure may sit immediately above a caption within one column while
    # ordinary article prose continues in the neighboring column.
    if y0 > journal_header_boundary(page) + 110.0:
        prose_end = prose_end_before(page, y0, column_left, column_right)
        top, top_detection = figure_content_top(
            page,
            y0 - 4.0,
            prose_end,
            span_left=column_left,
            span_right=column_right,
        )
        metrics = region_metrics(
            page, top, y0 - 4.0, column_left, column_right
        )
        if looks_like_figure(metrics) and metrics["prose_blocks"] <= 1:
            return {
                "top": top,
                "bottom": y0 - 1.0,
                "left": column_left,
                "right": column_right,
                "layout": "review-same-column-above-caption",
                "metrics": metrics,
                "top_detection": top_detection,
            }

    caption_on_right = x0 >= frame_left + frame_width * 0.48
    caption_on_left = x1 <= frame_left + frame_width * 0.52
    if not (caption_on_right or caption_on_left):
        return None
    if caption_on_right:
        open_left, open_right = max(20.0, frame_left - gap), x0 - 2.0
    else:
        open_left, open_right = x1 + 2.0, min(page.rect.width - 20.0, frame_right + gap)
    if open_right - open_left < frame_width * 0.30:
        return None

    search_bottom = min(usable_bottom, max(y1 + gap, y0 + 160.0))
    top, top_detection = figure_content_top(
        page,
        search_bottom,
        span_left=open_left,
        span_right=open_right,
    )
    metrics = region_metrics(
        page, top, search_bottom, open_left, open_right
    )
    if not looks_like_figure(metrics) or metrics["prose_blocks"] > 1:
        return None
    visual_bottom = visual_bottom_in_span(
        page, top, search_bottom, open_left, open_right
    )
    return {
        "top": top,
        "bottom": min(search_bottom, visual_bottom + gap),
        "left": open_left,
        "right": open_right,
        "layout": "review-horizontal-adjacent-caption",
        "metrics": metrics,
        "top_detection": top_detection,
    }


def article_same_column_above_caption(page, candidate):
    """Detect an Article Figure above a one-column caption beside prose."""
    if is_review_note:
        return None
    x0, y0, x1, _ = candidate["caption_bbox"]
    frame_left, frame_right, _ = page_main_content_frame(page)
    frame_width = frame_right - frame_left
    if frame_width <= 0 or (x1 - x0) / frame_width > 0.58:
        return None
    column_left = max(20.0, x0 - 4.0)
    column_right = min(page.rect.width - 20.0, x1 + 4.0)
    prose_end = prose_end_before(page, y0, column_left, column_right)
    top, top_detection = figure_content_top(
        page,
        y0 - 2.0,
        prose_end,
        span_left=column_left,
        span_right=column_right,
    )
    figure_metrics = region_metrics(
        page, top, y0 - 2.0, column_left, column_right
    )
    if not looks_like_figure(figure_metrics) or figure_metrics["prose_blocks"] > 1:
        return None

    if x0 <= frame_left + frame_width * 0.25:
        adjacent_left, adjacent_right = column_right + 2.0, frame_right
    elif x1 >= frame_left + frame_width * 0.75:
        adjacent_left, adjacent_right = frame_left, column_left - 2.0
    else:
        return None
    adjacent_metrics = region_metrics(
        page, top, y0 - 2.0, adjacent_left, adjacent_right
    )
    if adjacent_metrics["prose_blocks"] < 1 or looks_like_figure(adjacent_metrics):
        return None
    return {
        "top": top,
        "bottom": y0 - 2.0,
        "left": column_left,
        "right": column_right,
        "layout": "article-same-column-above-caption",
        "metrics": figure_metrics,
        "top_detection": top_detection,
    }


def science_figure_top(page, before_y, after_y=None, safety_margin=10.0):
    """Locate the first Figure element after the header/prose and retain headroom."""
    header_boundary = science_header_boundary(page)
    # Keep clear of the running-header rule and its decorative elements before
    # searching for the first real panel. The later 10 pt subtraction is the
    # Figure safety margin, not a header margin.
    search_after = max(header_boundary + 12.0, after_y or 0.0)
    visual_starts = []

    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if rect and rect.y0 >= search_after and rect.y0 < before_y:
            visual_starts.append(float(rect.y0))
    for image in page.get_images(full=True):
        try:
            rects = page.get_image_rects(image[0])
        except Exception:
            rects = []
        visual_starts.extend(
            float(rect.y0)
            for rect in rects
            if rect.y0 >= search_after and rect.y0 < before_y
        )
    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        if y0 < search_after or y0 >= before_y:
            continue
        clean = normalize_caption(text)
        if clean and len(clean) < 180:
            visual_starts.append(float(y0))

    first_visual_y = min(visual_starts) if visual_starts else search_after
    top = max(header_boundary + 2.0, first_visual_y - safety_margin)
    return top, {
        "header_boundary": round(header_boundary, 2),
        "first_visual_y": round(first_visual_y, 2),
        "safety_margin": safety_margin,
        "source": "first-figure-element" if visual_starts else "post-header-or-prose-fallback",
    }


def crop_edge_contacts(page, rect, clearance=1.0, top_content_start=None):
    """Identify text or visual content that is too close to a crop edge."""
    contacts = {"top": 0, "bottom": 0, "left": 0, "right": 0}

    def overlaps(candidate):
        return candidate.x1 > rect.x0 and candidate.x0 < rect.x1 and candidate.y1 > rect.y0 and candidate.y0 < rect.y1

    def inspect(candidate, visual=False):
        if not overlaps(candidate):
            return
        if (
            candidate.y0 < rect.y0 + clearance
            and candidate.y1 > rect.y0
            and (
                top_content_start is None
                or candidate.y1 > top_content_start + clearance
            )
        ):
            contacts["top"] += 1
        if candidate.y1 > rect.y1 - clearance and candidate.y0 < rect.y1:
            contacts["bottom"] += 1
        if candidate.x0 < rect.x0 + clearance and candidate.x1 > rect.x0:
            contacts["left"] += 1
        if candidate.x1 > rect.x1 - clearance and candidate.x0 < rect.x1:
            contacts["right"] += 1

    for block in page.get_text("blocks", sort=True):
        x0, y0, x1, y1, text = block[:5]
        if normalize_caption(text):
            inspect(pymupdf.Rect(x0, y0, x1, y1))
    for drawing in page.get_drawings():
        drawing_rect = drawing.get("rect")
        if drawing_rect and (drawing_rect.width >= 20.0 or drawing_rect.height >= 20.0):
            inspect(drawing_rect, visual=True)
    for image in page.get_images(full=True):
        try:
            rects = page.get_image_rects(image[0])
        except Exception:
            rects = []
        for image_rect in rects:
            if image_rect.width >= 20.0 and image_rect.height >= 20.0:
                inspect(image_rect, visual=True)
    return {edge: count for edge, count in contacts.items() if count}


def legend_continuation_y(page):
    """Locate Cell-style legend continuation markers below a full-page Figure."""
    for block in page.get_text("blocks", sort=True):
        _, y0, _, _, text = block[:5]
        clean = normalize_caption(text).lower()
        if "legend on next page" in clean or "legend continued on next page" in clean:
            return float(y0)
    return None


def choose_table_crop(document, candidate):
    """Crop a Review Table using the detected PDF table grid plus title/footnotes."""
    page_index = candidate["caption_page"]
    page = document[page_index]
    title_rect = pymupdf.Rect(candidate["caption_bbox"])
    detected = list(page.find_tables().tables)
    if not detected:
        raise ValueError("no structured table region detected on the title page")

    def title_distance(table):
        rect = pymupdf.Rect(table.bbox)
        if rect.y0 >= title_rect.y1:
            return rect.y0 - title_rect.y1
        if title_rect.y0 >= rect.y1:
            return title_rect.y0 - rect.y1
        return 0.0

    table = min(detected, key=title_distance)
    table_rect = pymupdf.Rect(table.bbox)
    if title_distance(table) > 100.0:
        raise ValueError("nearest structured table is too far from the Table title")
    if table.row_count < 2 or table.col_count < 2:
        raise ValueError(
            f"implausible table grid: {table.row_count} rows x {table.col_count} columns"
        )

    combined = pymupdf.Rect(title_rect)
    combined |= table_rect
    footnote_blocks = []
    # Most journal Tables place compact notes directly below the last row. Add
    # contiguous note blocks, while stopping before the running footer or prose.
    if table_rect.y0 >= title_rect.y0:
        cursor = table_rect.y1
        footer_top = page.rect.height - 60.0
        for block in page.get_text("blocks", sort=True):
            x0, y0, x1, y1, text = block[:5]
            clean = normalize_caption(text)
            if not clean or y0 < cursor - 1.0 or y0 >= footer_top:
                continue
            if x1 <= table_rect.x0 - 8.0 or x0 >= table_rect.x1 + 8.0:
                continue
            if y0 - cursor > 18.0:
                break
            if len(clean) > 500:
                break
            footnote_rect = pymupdf.Rect(block[:4])
            footnote_blocks.append(clean)
            combined |= footnote_rect
            cursor = max(cursor, float(y1))

    padding = max(6.0, figure_caption_padding_pt)
    frame_left, frame_right, frame_source = page_main_content_frame(page)
    rect = pymupdf.Rect(
        max(frame_left, combined.x0 - padding),
        max(0.0, combined.y0 - padding),
        min(frame_right, combined.x1 + padding),
        min(page.rect.height - 42.0, combined.y1 + padding),
    )
    if rect.width < 180 or rect.height < 100:
        raise ValueError(f"implausible Table crop rectangle: {rect}")

    diagnostics = {
        "expected_panels": [],
        "panel_check": "not-applicable",
        "table_check": "complete-structured-table",
        "table_rows": int(table.row_count),
        "table_columns": int(table.col_count),
        "footnote_blocks": len(footnote_blocks),
        "caption_included": True,
        "caption_status": "included-complete",
        "manual_review": False,
        "review_reason": None,
        "layout": "review-structured-table",
        "main_content_frame": {
            "left": round(frame_left, 2),
            "right": round(frame_right, 2),
            "source": frame_source,
        },
    }
    boundary_contacts = crop_edge_contacts(
        page,
        rect,
        clearance=figure_edge_clearance,
    )
    confidence = "high"
    if boundary_contacts:
        confidence = "low"
        diagnostics["manual_review"] = True
        diagnostics["table_check"] = "boundary-contact-unverified"
        diagnostics["boundary_contacts"] = boundary_contacts
        diagnostics["review_reason"] = (
            "Table text or rules touch the crop boundary: "
            + ", ".join(
                f"{edge} ({count})" for edge, count in boundary_contacts.items()
            )
            + ". Full-page AI verification required."
        )
    return page_index, rect, "same-page-structured-table", confidence, diagnostics


def science_wrapped_caption_layout(page, candidate, usable_bottom):
    """Detect Science-style figures that wrap panels around a narrow caption.

    In this layout the caption occupies one column while additional panels sit
    below it in the other columns. Treating caption_y0 as a page-wide boundary
    truncates those panels, so the entire post-prose figure region is required.
    """
    x0, y0, x1, y1 = candidate["caption_bbox"]
    expected_panels = caption_panel_labels(candidate["caption"])
    if len(expected_panels) < 2:
        return None
    width_ratio = (x1 - x0) / page.rect.width
    narrow_side_caption = (
        width_ratio <= 0.55
        and (x0 >= page.rect.width * 0.42 or x1 <= page.rect.width * 0.58)
    )
    if narrow_side_caption:
        if x0 >= page.rect.width * 0.55:
            open_left, open_right = 28.0, x0 - 8.0
        else:
            open_left, open_right = x1 + 8.0, page.rect.width - 6.0

        prose_end = prose_end_before(page, y0)
        figure_top, top_detection = science_figure_top(page, y0, prose_end)
        above_metrics = region_metrics(page, figure_top, y0 - 4.0)
        wrapped_below_metrics = region_metrics(
            page,
            y0 - 4.0,
            usable_bottom,
            open_left,
            open_right,
        )
        if looks_like_figure(above_metrics) and looks_like_figure(wrapped_below_metrics):
            return {
                "top": figure_top,
                "left": 28.0,
                "right": page.rect.width - 6.0,
                "bottom": usable_bottom,
                "layout": "science-style-wrapped-caption",
                "metrics": wrapped_below_metrics,
                "top_detection": top_detection,
            }

    # Science also places a figure plus caption across the left two columns
    # while normal article prose continues down the rightmost column. Crop to
    # the caption's column span and compute the top from prose in that span,
    # not from unrelated prose continuing in the adjacent column.
    left_column_span = (
        x0 <= page.rect.width * 0.10
        and 0.38 <= width_ratio <= 0.72
        and x1 <= page.rect.width * 0.72
    )
    if left_column_span:
        crop_left = max(28.0, x0 - 8.0)
        crop_right = min(page.rect.width - 28.0, x1 + 8.0)
        prose_end = prose_end_before(page, y0, crop_left, crop_right)
        figure_top, top_detection = science_figure_top(page, y0, prose_end)
        figure_metrics = region_metrics(
            page,
            figure_top,
            usable_bottom,
            crop_left,
            crop_right,
        )
        adjacent_prose = region_metrics(
            page,
            figure_top,
            usable_bottom,
            crop_right + 4.0,
            page.rect.width - 28.0,
        )
        adjacent_above_caption = region_metrics(
            page,
            figure_top,
            y0 - 4.0,
            crop_right + 4.0,
            page.rect.width - 28.0,
        )
        if (
            looks_like_figure(figure_metrics)
            and adjacent_prose["prose_blocks"] >= 1
            and adjacent_above_caption["prose_blocks"] >= 1
            and not looks_like_figure(adjacent_above_caption)
        ):
            return {
                "top": figure_top,
                "left": crop_left,
                "right": crop_right,
                "bottom": usable_bottom,
                "layout": "science-style-column-span-caption",
                "metrics": figure_metrics,
                "top_detection": top_detection,
            }

    # A caption may be extracted as one full-width text block because its text
    # continues beneath a side panel. If visual material exists both above and
    # below the caption's starting y coordinate, retain the complete figure and
    # stop at the next prose block after the caption.
    if width_ratio > 0.72:
        prose_end = prose_end_before(page, y0)
        figure_top, top_detection = science_figure_top(page, y0, prose_end)
        above_metrics = region_metrics(page, figure_top, y0 - 4.0)
        below_metrics = region_metrics(page, y0 - 4.0, usable_bottom)
        if looks_like_figure(above_metrics) and looks_like_figure(below_metrics):
            figure_bottom = prose_bottom(page, y1 + 4.0, usable_bottom)
            return {
                "top": figure_top,
                "left": 28.0,
                "right": page.rect.width - 6.0,
                "bottom": figure_bottom,
                "layout": "science-style-full-width-wrapped-caption",
                "metrics": below_metrics,
                "top_detection": top_detection,
            }

    return None


def choose_crop(document, candidate):
    caption_page_index = candidate["caption_page"]
    caption_page = document[caption_page_index]
    caption_y0 = candidate["caption_bbox"][1]
    caption_y1 = candidate["caption_bbox"][3]
    page_height = caption_page.rect.height
    usable_bottom = page_height - 42.0
    science_usable_bottom = page_height - 24.0
    expected_panels = caption_panel_labels(candidate["caption"])
    diagnostics = {
        "expected_panels": expected_panels,
        "panel_check": "not-applicable" if not expected_panels else "pending",
        "caption_included": False,
        "caption_status": "pending",
        "manual_review": False,
        "review_reason": None,
    }

    article_column_layout = article_same_column_above_caption(
        caption_page,
        candidate,
    )
    review_layout = review_same_page_layout(
        caption_page,
        candidate,
        usable_bottom,
    )
    science_layout = science_wrapped_caption_layout(
        caption_page,
        candidate,
        science_usable_bottom,
    )

    if article_column_layout:
        figure_page_index = caption_page_index
        figure_page = caption_page
        top = article_column_layout["top"]
        bottom = article_column_layout["bottom"]
        method = "same-page-article-column-aware"
        confidence = "high"
        diagnostics["panel_check"] = (
            "complete-layout-region" if expected_panels else "not-applicable"
        )
        diagnostics["layout"] = article_column_layout["layout"]
        diagnostics["wrapped_region_metrics"] = article_column_layout["metrics"]
        diagnostics["top_detection"] = article_column_layout["top_detection"]
    elif review_layout:
        figure_page_index = caption_page_index
        figure_page = caption_page
        top = review_layout["top"]
        bottom = review_layout["bottom"]
        method = "same-page-review-column-aware"
        confidence = "high"
        diagnostics["panel_check"] = (
            "complete-layout-region" if expected_panels else "not-applicable"
        )
        diagnostics["layout"] = review_layout["layout"]
        diagnostics["wrapped_region_metrics"] = review_layout["metrics"]
        diagnostics["top_detection"] = review_layout["top_detection"]
    elif science_layout:
        figure_page_index = caption_page_index
        figure_page = caption_page
        top = science_layout["top"]
        bottom = science_layout["bottom"]
        method = "same-page-wrapped-caption-full-figure"
        confidence = "high"
        diagnostics["panel_check"] = "complete-layout-region"
        diagnostics["layout"] = science_layout["layout"]
        diagnostics["wrapped_region_metrics"] = science_layout["metrics"]
        diagnostics["top_detection"] = science_layout["top_detection"]
    else:
        # If a multi-panel caption has visual material below its y coordinate,
        # the conventional above-caption crop would be incomplete. Fall back to
        # the complete usable page region and require manual review rather than
        # silently inserting a truncated figure.
        caption_x0, _, caption_x1, _ = candidate["caption_bbox"]
        omitted_metrics = region_metrics(
            caption_page,
            caption_y0 - 4.0,
            usable_bottom,
        )
        suspicious_wrapping = (
            len(expected_panels) >= 2
            and looks_like_figure(omitted_metrics)
            and (caption_x1 - caption_x0) < caption_page.rect.width * 0.75
        )
        if suspicious_wrapping:
            figure_page_index = caption_page_index
            figure_page = caption_page
            prose_end = prose_end_before(caption_page, caption_y0)
            top, top_detection = figure_content_top(
                caption_page,
                caption_y0,
                prose_end,
            )
            bottom = usable_bottom
            method = "same-page-complete-region-manual-review"
            confidence = "low"
            diagnostics["panel_check"] = "unverified-complete-region"
            diagnostics["manual_review"] = True
            diagnostics["top_detection"] = top_detection
            diagnostics["review_reason"] = (
                "Caption references multiple panels and visual material continues "
                "below the caption boundary; complete-region fallback used."
            )
        else:
            figure_page_index = None

    # Some journal layouts print a long caption before an otherwise full-page
    # figure. Prefer the next page only when the caption-page candidate is
    # prose-heavy and the next page has strong visual-layout evidence.
    same_page_top_is_figure = False
    if caption_y0 > 205.0:
        same_page_top, _ = figure_content_top(caption_page, caption_y0 - 8.0)
        same_top_metrics = region_metrics(caption_page, same_page_top, caption_y0 - 8.0)
        same_page_top_is_figure = (
            looks_like_figure(same_top_metrics)
            and same_top_metrics["prose_blocks"] <= 1
        )

    next_page_is_figure = False
    if caption_y0 > page_height * 0.55 and caption_page_index + 1 < len(document):
        same_page_top, _ = figure_content_top(caption_page, caption_y0 - 8.0)
        same_metrics = region_metrics(caption_page, same_page_top, caption_y0 - 8.0)
        next_page = document[caption_page_index + 1]
        next_page_top, _ = figure_content_top(
            next_page,
            next_page.rect.height - 42.0,
        )
        next_metrics = region_metrics(
            next_page,
            next_page_top,
            next_page.rect.height - 42.0,
        )
        next_page_is_figure = (
            same_metrics["prose_blocks"] >= 2
            and looks_like_figure(next_metrics)
            and next_metrics["prose_blocks"] <= 1
        )

    previous_page_is_figure = False
    previous_page_has_continued_legend = False
    if caption_page_index > 0:
        previous_page = document[caption_page_index - 1]
        previous_page_top, _ = figure_content_top(
            previous_page,
            previous_page.rect.height - 42.0,
        )
        previous_metrics = region_metrics(
            previous_page,
            previous_page_top,
            previous_page.rect.height - 42.0,
        )
        previous_page_has_continued_legend = legend_continuation_y(previous_page) is not None
        previous_page_is_figure = (
            looks_like_figure(previous_metrics)
            and previous_metrics["prose_blocks"] <= 1
            and (
                previous_page_has_continued_legend
                or caption_y0 < page_height * 0.45
            )
        )

    if figure_page_index is not None:
        pass
    elif previous_page_is_figure:
        figure_page_index = caption_page_index - 1
        figure_page = document[figure_page_index]
        top, top_detection = figure_content_top(
            figure_page,
            figure_page.rect.height - 42.0,
        )
        continuation_y = legend_continuation_y(figure_page)
        bottom = (
            continuation_y - 8.0
            if continuation_y is not None
            else prose_bottom(
                figure_page,
                figure_page.rect.height * 0.48,
                figure_page.rect.height - 52.0,
            )
        )
        method = (
            "previous-page-before-continued-caption"
            if previous_page_has_continued_legend
            else "previous-page-before-top-caption"
        )
        confidence = "high"
        diagnostics["panel_check"] = "complete-adjacent-page"
        diagnostics["top_detection"] = top_detection
    elif next_page_is_figure:
        figure_page_index = caption_page_index + 1
        figure_page = document[figure_page_index]
        top, top_detection = figure_content_top(
            figure_page,
            figure_page.rect.height - 42.0,
        )
        bottom = prose_bottom(
            figure_page,
            figure_page.rect.height * 0.48,
            figure_page.rect.height - 52.0,
        )
        method = "next-page-after-bottom-caption"
        confidence = "high"
        diagnostics["panel_check"] = "complete-adjacent-page"
        diagnostics["top_detection"] = top_detection
    # Many journal layouts place a full-page figure immediately before a
    # caption that starts near the top of the next page.
    elif (
        caption_y0 < page_height * 0.45
        and caption_page_index > 0
        and not same_page_top_is_figure
    ):
        figure_page_index = caption_page_index - 1
        figure_page = document[figure_page_index]
        top, top_detection = figure_content_top(
            figure_page,
            figure_page.rect.height - 42.0,
        )
        bottom = prose_bottom(
            figure_page,
            figure_page.rect.height * 0.48,
            figure_page.rect.height - 52.0,
        )
        method = "previous-page-before-top-caption"
        confidence = "high"
        diagnostics["panel_check"] = "complete-adjacent-page"
        diagnostics["top_detection"] = top_detection
    else:
        figure_page_index = caption_page_index
        figure_page = caption_page
        prose_end = prose_end_before(figure_page, caption_y0)
        top, top_detection = figure_content_top(
            figure_page,
            caption_y0,
            prose_end,
        )
        if include_original_caption:
            bottom = caption_y1 + figure_caption_padding_pt
            method = "same-page-with-caption"
        else:
            bottom = caption_y0 - 2.0
            method = "same-page-above-caption"
        confidence = "medium"
        diagnostics["panel_check"] = (
            "caption-and-panel-region-covered"
            if expected_panels and include_original_caption
            else ("caption-boundary-covered" if expected_panels else "not-applicable")
        )
        diagnostics["top_detection"] = top_detection

    frame_left, frame_right, frame_source = page_main_content_frame(figure_page)
    if article_column_layout and figure_page_index == caption_page_index:
        left = article_column_layout["left"]
        right = article_column_layout["right"]
    elif review_layout and figure_page_index == caption_page_index:
        left = max(review_layout["left"], 20.0)
        right = min(review_layout["right"], figure_page.rect.width - 20.0)
    elif science_layout and figure_page_index == caption_page_index:
        left = max(science_layout["left"], frame_left)
        right = min(science_layout["right"], frame_right)
    else:
        left = frame_left
        right = frame_right
    if (
        is_review_note
        and figure_page_index != caption_page_index
        and method.startswith("previous-page-")
    ):
        # Full-page Review illustrations commonly extend a few points beyond
        # the body-text envelope. Expand inside safe page margins without
        # admitting the footer rule or outer bleed decoration.
        left = max(20.0, left - 10.0)
        right = min(figure_page.rect.width - 20.0, right + 10.0)
        bottom = min(figure_page.rect.height - 36.0, bottom + 6.0)
    diagnostics["main_content_frame"] = {
        "left": round(frame_left, 2),
        "right": round(frame_right, 2),
        "source": frame_source,
    }
    if figure_page_index == caption_page_index and include_original_caption:
        caption_x0, _, caption_x1, _ = candidate["caption_bbox"]
        left = max(20.0, min(left, caption_x0 - 4.0))
        right = min(figure_page.rect.width - 20.0, max(right, caption_x1 + 4.0))
        bottom = max(bottom, caption_y1 + figure_caption_padding_pt)
        diagnostics["caption_included"] = True
        diagnostics["caption_status"] = "included-complete"
    elif figure_page_index == caption_page_index:
        diagnostics["caption_status"] = "omitted-by-config"
    else:
        diagnostics["caption_status"] = "external-not-co-located"
    bottom_margin = (
        18.0
        if diagnostics["caption_included"]
        else (24.0 if science_layout and figure_page_index == caption_page_index else 42.0)
    )
    bottom = min(bottom, figure_page.rect.height - bottom_margin)
    rect = pymupdf.Rect(left, top, right, bottom)
    if diagnostics["caption_included"] and rect.y1 + 0.5 < caption_y1:
        diagnostics["caption_included"] = False
        diagnostics["caption_status"] = "incomplete-page-boundary"
        diagnostics["manual_review"] = True
        diagnostics["panel_check"] = "caption-incomplete"
        diagnostics["review_reason"] = (
            "The same-page caption extends into the reserved footer/page boundary "
            "and cannot be included completely by the deterministic crop."
        )
    minimum_width = 160 if review_layout else 220
    if rect.width < minimum_width or rect.height < 150:
        raise ValueError(f"implausible crop rectangle: {rect}")
    top_detection = diagnostics.get("top_detection", {})
    boundary_contacts = crop_edge_contacts(
        figure_page,
        rect,
        clearance=figure_edge_clearance,
        top_content_start=top_detection.get("first_visual_y"),
    )
    if boundary_contacts:
        confidence = "low"
        diagnostics["manual_review"] = True
        diagnostics["panel_check"] = "boundary-contact-unverified"
        diagnostics["boundary_contacts"] = boundary_contacts
        diagnostics["review_reason"] = (
            "Text or graphical content touches the crop boundary: "
            + ", ".join(
                f"{edge} ({count})" for edge, count in boundary_contacts.items()
            )
            + ". Full-page AI verification required."
        )
    return figure_page_index, rect, method, confidence, diagnostics


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def complete_region_fallback(document, candidate, reason, page_index=None):
    if page_index is None:
        page_index = candidate["caption_page"]
    page = document[page_index]
    caption_same_page = page_index == candidate["caption_page"]
    return (
        page_index,
        pymupdf.Rect(page.rect),
        "full-page-ai-candidate",
        "low",
        {
            "expected_panels": caption_panel_labels(candidate["caption"]),
            "panel_check": "unverified-complete-region",
            "caption_included": caption_same_page,
            "caption_status": (
                "pending-ai-verification"
                if caption_same_page
                else "external-not-co-located"
            ),
            "manual_review": True,
            "review_reason": reason,
            "layout": "full-page-fallback",
        },
    )


def ai_refine_candidate(
    image_path,
    title,
    expected_panels,
    width,
    height,
    caption_required=True,
    kind="figure",
):
    """Ask a vision-capable Codex model to isolate and verify one visual item."""
    if not ai_fallback_enabled:
        return {
            "success": False,
            "reason": "AI figure fallback disabled by LENS_FIGURE_AI_FALLBACK=0.",
        }
    if not shutil.which("codex"):
        return {"success": False, "reason": "codex executable not found."}

    schema = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "success",
            "bbox",
            "visible_panels",
            "complete",
            "caption_complete",
            "content_intact",
            "separable_from_adjacent",
            "reason",
        ],
        "properties": {
            "success": {"type": "boolean"},
            "bbox": {
                "type": "array",
                "items": {"type": "number"},
                "minItems": 4,
                "maxItems": 4,
            },
            "visible_panels": {
                "type": "array",
                "items": {"type": "string"},
            },
            "complete": {"type": "boolean"},
            "caption_complete": {"type": "boolean"},
            "content_intact": {"type": "boolean"},
            "separable_from_adjacent": {"type": "boolean"},
            "reason": {"type": "string"},
        },
    }
    panel_text = ", ".join(expected_panels) if expected_panels else "not explicitly listed"
    target_name = "Table" if kind == "table" else "Figure"
    integrity_requirement = (
        "The box must include the Table title, complete column/row headers, every data "
        "row, and all symbol, abbreviation, and source footnotes. Reject a continued or "
        "multi-page Table unless the whole Table is visible on this candidate page."
        if kind == "table"
        else "The box must include every target panel, panel label, legend, axis, and plotted graphic."
    )
    caption_requirement = (
        f"The complete original {target_name} caption/title must be included in the bounding box."
        if caption_required
        else f"The original {target_name} caption/title is on another page and is not required in this image."
    )
    prompt = f"""
Inspect the attached complete-page or complete-region candidate for a scientific {kind}.
Target: {title}
Image size: {width} x {height} pixels.
Caption-expected panels: {panel_text}.
Caption requirement: {caption_requirement}
Integrity requirement: {integrity_requirement}

Return a tight rectangular bounding box [x0, y0, x1, y1] in attached-image pixel
coordinates that contains the entire target figure, every target panel, panel labels,
legends, axes, and the complete figure caption when present. Exclude unrelated article
prose, page headers, footers, download watermarks, and neighboring figures. Do not crop
through any panel, label, axis, plotted graphic, legend, or caption text. Set
the raw bbox outside the outermost target ink on every side; downstream padding cannot
repair a bbox that already cuts content. For a caption spanning multiple columns, trace
the caption through its final line and extend x1 through the full rightmost caption
column before declaring it complete. Set
complete=true only when the whole target {target_name} is confirmed complete. Set
caption_complete=true only when the full target caption is present. When the
caption requirement says the caption is external, caption_complete may be false. Set
content_intact=true only when text, axes, and graphics show no definite truncation.
Set separable_from_adjacent=true only when the target can be separated from neighboring
visual items with one rectangle. Set success=false if any of these properties cannot be
confirmed reliably. visible_panels must list only panel labels actually verified in the
proposed box. Respond only with the schema-conforming JSON object.
""".strip()

    with tempfile.TemporaryDirectory(prefix="lens-figure-ai-", dir=asset_dir) as temp_name:
        temp_dir = Path(temp_name)
        schema_path = temp_dir / "schema.json"
        response_path = temp_dir / "response.json"
        schema_path.write_text(json.dumps(schema), encoding="utf-8")
        command = [
            "codex",
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--model",
            ai_model,
            "--image",
            str(image_path),
            "--output-schema",
            str(schema_path),
            "--output-last-message",
            str(response_path),
            prompt,
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=asset_dir,
                capture_output=True,
                text=True,
                timeout=ai_timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "reason": f"AI figure fallback timed out after {ai_timeout_seconds}s.",
            }
        if completed.returncode != 0 or not response_path.exists():
            error = (completed.stderr or completed.stdout or "unknown Codex error").strip()
            return {
                "success": False,
                "reason": f"AI figure fallback failed: {error[-500:]}",
            }
        try:
            result = json.loads(response_path.read_text(encoding="utf-8"))
        except Exception as exc:
            return {"success": False, "reason": f"Invalid AI JSON response: {exc}"}

    if not result.get("success") or not result.get("complete"):
        return {
            "success": False,
            "reason": result.get("reason") or "AI could not verify a complete figure.",
            "ai_response": result,
        }
    if caption_required and not result.get("caption_complete"):
        return {
            "success": False,
            "reason": f"AI could not confirm that the {target_name} caption/title is complete.",
            "ai_response": result,
        }
    if not result.get("content_intact"):
        return {
            "success": False,
            "reason": "AI detected definite truncation of text, axes, or graphics.",
            "ai_response": result,
        }
    if not result.get("separable_from_adjacent"):
        return {
            "success": False,
            "reason": f"AI could not separate the target {target_name} from adjacent content.",
            "ai_response": result,
        }
    bbox = result.get("bbox") or []
    if len(bbox) != 4:
        return {"success": False, "reason": "AI returned an invalid bbox."}
    try:
        x0, y0, x1, y1 = [float(value) for value in bbox]
    except (TypeError, ValueError):
        return {"success": False, "reason": "AI bbox was not numeric."}
    raw_bbox = [x0, y0, x1, y1]
    if x0 < 0 or y0 < 0 or x1 > width or y1 > height:
        return {
            "success": False,
            "reason": "AI bbox extends outside the candidate/page and cannot be expanded safely.",
            "ai_response": result,
        }
    if x1 - x0 < 280 or y1 - y0 < 160:
        return {"success": False, "reason": "AI bbox is implausibly small."}

    visible_panels = [
        str(value).strip().lower()
        for value in result.get("visible_panels", [])
    ]
    missing_panels = [value for value in expected_panels if value not in visible_panels]
    if expected_panels and missing_panels:
        return {
            "success": False,
            "reason": f"AI did not verify expected panels: {', '.join(missing_panels)}.",
            "ai_response": result,
        }

    padding_px = max(0, round(figure_ai_bbox_padding_pt * figure_render_scale))
    expanded_x0 = max(0, math.floor(x0) - padding_px)
    expanded_y0 = max(0, math.floor(y0) - padding_px)
    expanded_x1 = min(width, math.ceil(x1) + padding_px)
    expanded_y1 = min(height, math.ceil(y1) + padding_px)
    padding_clamped_edges = []
    if expanded_x0 == 0 and math.floor(x0) - padding_px < 0:
        padding_clamped_edges.append("left")
    if expanded_y0 == 0 and math.floor(y0) - padding_px < 0:
        padding_clamped_edges.append("top")
    if expanded_x1 == width and math.ceil(x1) + padding_px > width:
        padding_clamped_edges.append("right")
    if expanded_y1 == height and math.ceil(y1) + padding_px > height:
        padding_clamped_edges.append("bottom")

    refined_path = image_path.with_suffix(".ai-refined.png")
    edge_contact_warning = []
    with Image.open(image_path) as source:
        clipped = source.crop(
            (expanded_x0, expanded_y0, expanded_x1, expanded_y1)
        )
        # The initial geometry gate still sends edge-contact cases to vision AI. Once
        # AI has explicitly verified panel, caption, content, and separation integrity,
        # residual raster contact is advisory: record it and insert at medium confidence.
        gray = clipped.convert("L")
        content_mask = gray.point(lambda value: 255 if value < 245 else 0)
        content_bbox = content_mask.getbbox()
        raster_clearance = max(4, round(figure_edge_clearance * figure_render_scale))
        if content_bbox:
            cx0, cy0, cx1, cy1 = content_bbox
            if cx0 <= raster_clearance:
                edge_contact_warning.append("left")
            if cy0 <= raster_clearance:
                edge_contact_warning.append("top")
            if clipped.width - cx1 <= raster_clearance:
                edge_contact_warning.append("right")
            if clipped.height - cy1 <= raster_clearance:
                edge_contact_warning.append("bottom")
        clipped.save(refined_path)
    refined_path.replace(image_path)
    return {
        "success": True,
        "ai_bbox": [round(value, 2) for value in raw_bbox],
        "bbox": [expanded_x0, expanded_y0, expanded_x1, expanded_y1],
        "padding_pt": figure_ai_bbox_padding_pt,
        "padding_px": padding_px,
        "padding_clamped_edges": padding_clamped_edges,
        "edge_contact_warning": edge_contact_warning,
        "visible_panels": visible_panels,
        "reason": result.get("reason", "AI verified complete figure."),
        "width": clipped.size[0],
        "height": clipped.size[1],
    }


headings = extractable_visual_headings(lines)
if not headings:
    print("No extractable numbered Figure/Table headings found; nothing to extract.")
    raise SystemExit(0)

document = pymupdf.open(pdf_path)
candidates = caption_candidates(document, headings)
manifest_path = asset_dir / "figures.json"
previous_entries = {}
if manifest_path.exists():
    try:
        previous_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for previous in previous_manifest.get("entries", []):
            previous_kind = previous.get("kind", "figure")
            previous_number = int(previous["number"])
            previous_entries[visual_key(previous_kind, previous_number)] = previous
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        previous_entries = {}
manifest_entries = []
blocks = {}
remove_managed_keys = set()
hash_owner = {}

for item in headings:
    kind = item["kind"]
    item_key = item["key"]
    number = item["number"]
    display_type = "Table" if kind == "table" else "Fig."
    file_prefix = "Table" if kind == "table" else "Fig"
    start, end = section_bounds(lines, item["line_index"])
    section = lines[start:end]
    existing = has_existing_image(section)
    managed = f"<!-- {kind}:{number}:start -->" in "".join(section)

    if managed and not replace_existing:
        previous = dict(previous_entries.get(item_key, {}))
        previous.update({"kind": kind, "number": number, "title": item["title"]})
        if previous:
            previous["run_status"] = "skipped-managed-image"
            previous.setdefault("status", "skipped-managed-image")
            manifest_entries.append(previous)
        else:
            manifest_entries.append({
                "kind": kind,
                "number": number,
                "title": item["title"],
                "status": "skipped-managed-image",
            })
        continue

    if existing and not managed and not replace_existing:
        manifest_entries.append({
            "kind": kind,
            "number": number,
            "title": item["title"],
            "status": "skipped-existing-image",
        })
        continue

    candidate = candidates.get(item_key)
    if not candidate:
        manifest_entries.append({
            "kind": kind,
            "number": number,
            "title": item["title"],
            "status": "caption-not-found",
        })
        continue

    output_path = asset_dir / f"{file_prefix}-{number:02d}.png"
    selection_error = None
    if kind == "table":
        try:
            page_index, crop, method, confidence, diagnostics = choose_table_crop(
                document,
                candidate,
            )
        except Exception as exc:
            selection_error = str(exc)
            page_index, crop, method, confidence, diagnostics = complete_region_fallback(
                document,
                candidate,
                f"Deterministic Table crop selection failed: {exc}",
            )
    else:
        try:
            page_index, crop, method, confidence, diagnostics = choose_crop(document, candidate)
        except Exception as exc:
            selection_error = str(exc)
            page_index, crop, method, confidence, diagnostics = complete_region_fallback(
                document,
                candidate,
                f"Deterministic crop selection failed: {exc}",
            )
    if kind == "figure" and number in ai_force_numbers:
        page_index, crop, method, confidence, diagnostics = complete_region_fallback(
            document,
            candidate,
            "Vision-AI fallback explicitly requested for this Figure.",
        )
    elif diagnostics.get("manual_review"):
        deterministic_diagnostics = diagnostics
        deterministic_method = method
        deterministic_crop = [round(value, 2) for value in crop]
        deterministic_confidence = confidence
        deterministic_reason = diagnostics.get(
            "review_reason",
            "Deterministic crop could not verify a complete Figure.",
        )
        page_index, crop, method, confidence, diagnostics = complete_region_fallback(
            document,
            candidate,
            deterministic_reason,
            page_index=page_index,
        )
        diagnostics["deterministic_crop"] = {
            "method": deterministic_method,
            "crop": deterministic_crop,
            "confidence": deterministic_confidence,
            "layout": deterministic_diagnostics.get("layout"),
            "top_detection": deterministic_diagnostics.get("top_detection"),
            "boundary_contacts": deterministic_diagnostics.get("boundary_contacts", {}),
        }

    try:
        page = document[page_index]
        matrix = pymupdf.Matrix(figure_render_scale, figure_render_scale)
        pixmap = page.get_pixmap(matrix=matrix, clip=crop, alpha=False, annots=False)
        layout_name = str(diagnostics.get("layout", ""))
        if layout_name.startswith("review-"):
            minimum_render_width = 400
        elif "column-span" in layout_name or layout_name.startswith("article-"):
            minimum_render_width = 500
        else:
            minimum_render_width = 700
        if pixmap.width < minimum_render_width or pixmap.height < 400:
            raise ValueError(f"render too small: {pixmap.width}x{pixmap.height}")
        pixmap.save(output_path)
    except Exception as exc:
        manifest_entries.append({
            "kind": kind,
            "number": number,
            "title": item["title"],
            "status": "crop-failed",
            "error": str(exc),
            "selection_error": selection_error,
        })
        continue

    final_width = pixmap.width
    final_height = pixmap.height
    ai_refined = False
    if diagnostics["manual_review"]:
        ai_trigger_reason = diagnostics.get("review_reason")
        ai_result = ai_refine_candidate(
            output_path,
            f"{display_type} {number} {item['title']}",
            diagnostics.get("expected_panels", []),
            final_width,
            final_height,
            caption_required=(
                diagnostics.get("caption_status") != "external-not-co-located"
            ),
            kind=kind,
        )
        if ai_result.get("success"):
            ai_refined = True
            final_width = ai_result["width"]
            final_height = ai_result["height"]
            method = "ai-refined-from-complete-region"
            confidence = "medium"
            diagnostics["manual_review"] = False
            diagnostics["review_reason"] = None
            diagnostics["panel_check"] = "ai-verified-complete"
            if diagnostics.get("caption_status") != "external-not-co-located":
                diagnostics["caption_included"] = True
                diagnostics["caption_status"] = "ai-verified-complete"
            diagnostics["ai_fallback"] = {
                "status": "verified",
                "model": ai_model,
                "source_method": "complete-region",
                "trigger_reason": ai_trigger_reason,
                "ai_bbox_pixels": ai_result["ai_bbox"],
                "bbox_pixels": ai_result["bbox"],
                "padding_pt": ai_result["padding_pt"],
                "padding_px": ai_result["padding_px"],
                "padding_clamped_edges": ai_result["padding_clamped_edges"],
                "edge-contact-warning": ai_result["edge_contact_warning"],
                "visible_panels": ai_result["visible_panels"],
                "reason": ai_result["reason"],
            }
        else:
            prior_reason = diagnostics.get("review_reason")
            ai_reason = ai_result.get("reason", "AI verification failed.")
            diagnostics["review_reason"] = (
                f"{prior_reason} AI fallback also failed: {ai_reason}"
                if prior_reason
                else f"AI fallback failed: {ai_reason}"
            )
            diagnostics["ai_fallback"] = {
                "status": "failed",
                "model": ai_model,
                "reason": ai_reason,
            }
            if ai_result.get("ai_response") is not None:
                diagnostics["ai_fallback"]["response"] = ai_result["ai_response"]

    digest = sha256(output_path)
    if digest in hash_owner and hash_owner[digest] != item_key:
        output_path.unlink(missing_ok=True)
        manifest_entries.append({
            "kind": kind,
            "number": number,
            "title": item["title"],
            "status": "duplicate-image",
            "duplicates": hash_owner[digest],
        })
        continue
    hash_owner[digest] = item_key

    entry_status = (
        "manual-review"
        if diagnostics["manual_review"]
        else ("inserted-ai-refined" if ai_refined else "inserted")
    )
    if diagnostics["manual_review"]:
        if managed and replace_existing:
            remove_managed_keys.add(item_key)
    else:
        relative_src = output_path.relative_to(note_path.parent).as_posix()
        caption = f"{display_type} {number} {item['title']}."
        block = (
            f"\n<!-- {kind}:{number}:start -->\n"
            "<center>\n"
            "  <img style=\"border-radius: 0.3125em;\n"
            "  box-shadow: 0 2px 4px 0 rgba(34,36,38,.12),0 2px 10px 0 rgba(34,36,38,.08);\"\n"
            f"  src=\"{relative_src}\">\n"
            "  <br>\n"
            "  <div style=\"display: inline-block;color: #999;padding: 2px;\">"
            f"{caption}</div>\n"
            "</center>\n"
            f"<!-- {kind}:{number}:end -->\n\n"
        )
        blocks[item_key] = block
    manifest_entries.append({
        "kind": kind,
        "number": number,
        "title": item["title"],
        "status": entry_status,
        "file": output_path.name,
        "sha256": digest,
        "caption_page": candidate["caption_page"] + 1,
        "figure_page": page_index + 1,
        "crop": [round(value, 2) for value in crop],
        "method": method,
        "confidence": confidence,
        "width": final_width,
        "height": final_height,
        **diagnostics,
    })

# Apply changes from bottom to top so original line indexes remain valid.
for item in sorted(headings, key=lambda value: value["line_index"], reverse=True):
    kind = item["kind"]
    item_key = item["key"]
    number = item["number"]
    if item_key in remove_managed_keys:
        start, end = section_bounds(lines, item["line_index"])
        lines[start:end] = strip_managed_block(lines[start:end], kind, number)
        continue
    if item_key not in blocks:
        continue
    start, end = section_bounds(lines, item["line_index"])
    section = strip_managed_block(lines[start:end], kind, number)
    if replace_existing:
        text = "".join(section)
        text = re.sub(r"\s*<center>.*?<img\b.*?</center>\s*", "\n", text, count=1, flags=re.S | re.I)
        section = text.splitlines(keepends=True)
    lines[start:end] = [blocks[item_key]] + section

if blocks or remove_managed_keys:
    note_path.write_text("".join(lines), encoding="utf-8")

def current_run_status(entry):
    return entry.get("run_status", entry["status"])


if manifest_entries and all(
    current_run_status(entry) == "skipped-managed-image" for entry in manifest_entries
):
    print(f"Visual extraction complete: inserted=0 skipped={len(manifest_entries)} failed=0")
    print(f"Assets: {asset_dir}")
    raise SystemExit(0)

manifest = {
    "source_pdf": str(pdf_path),
    "note": str(note_path),
    "generated": datetime.now().astimezone().isoformat(timespec="seconds"),
    "entries": sorted(
        manifest_entries,
        key=lambda value: next(
            index
            for index, item in enumerate(headings)
            if item["key"] == visual_key(value["kind"], value["number"])
        ),
    ),
}
(asset_dir / "figures.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

inserted = sum(current_run_status(entry).startswith("inserted") for entry in manifest_entries)
skipped = sum(current_run_status(entry).startswith("skipped-") for entry in manifest_entries)
manual_review = sum(current_run_status(entry) == "manual-review" for entry in manifest_entries)
failed = len(manifest_entries) - inserted - skipped - manual_review
print(
    f"Visual extraction complete: inserted={inserted} skipped={skipped} "
    f"manual_review={manual_review} failed={failed}"
)
print(f"Assets: {asset_dir}")
PY
