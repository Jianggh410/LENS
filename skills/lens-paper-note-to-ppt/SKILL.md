---
name: lens-paper-note-to-ppt
description: Convert a LENS Markdown paper note into a figure-led PowerPoint. Use when the user asks “把这篇文章的笔记做成 PPT”, requests a PPT from a LENS note, or invokes $lens-paper-note-to-ppt.
---

# LENS Paper Note to PPT

Use the deterministic converter at `scripts/lens-paper-note-to-ppt.py`. The input is one existing LENS Markdown note; the default output is `assets/<note-stem>/<note-stem>.pptx` beside that note.

## Workflow

1. Resolve the note path from the user's link, mentioned file, or the single unambiguous paper note in the conversation. Ask only when multiple notes remain plausible.
2. Load the shared runtime configuration at `../../config/lens_config.sh` when available. Fixed PowerPoint typography and geometry live in `ppt.config`; use `LENS_NOTE_TO_PPT_CONFIG` only to select an alternate config file.
3. Run:

   ```bash
   uv run scripts/lens-paper-note-to-ppt.py "/absolute/path/to/note.md"
   ```

4. Read the printed summary. Report missing image assets or generation failures; otherwise return the absolute PPTX path.

## Content contract

- Omit the complete top-level sections `# Works`, `# Question–Method Map`, and `# Key references`.
- Present the opening top-level sections in the fixed order `# Info`, `# Intro`, `# Summary`, regardless of their order in the note. Preserve source order for the other included top-level sections.
- Always use an included `#` heading as a section divider.
- Immediately after the `# Summary` section and before `# Results`, add an `Overall study strategy and workflow` slide listing the cleaned titles of every Results-level `## Figure/Table` block in source order. If the note has no included Summary section, place this overview immediately after the Results divider.
- Before each Results-level Figure/Table content block, repeat that workflow slide and highlight the current `##` title in black while rendering the other titles in light gray. This is the Figure/Table secondary transition page.
- After the Results secondary transition page, treat the `##` block as a Figure/Table content slide. Derive its title from the first image legend, then continue with any following `###` content slides.
- Use a `##` heading as a section divider only when it contains at least one `###` content block and does not directly contain a Figure/Table image. Omit a `##` block that contains neither a `###` block nor an image, such as `## 数据与代码` under `# Info`.
- Use `###` as a content-slide title and place at most the first two images from its first uninterrupted image sequence on that same slide. An image block includes its immediately adjacent Citation. The next image joins the same sequence only when it starts on the very next line after the preceding image or its Citation; a blank line, prose, heading, or other intervening content ends the sequence, so ignore all later images in that `###` block. If either selected image has a legend, place an 18 pt label centered immediately above its corresponding image, prefixed by a hollow square (`□`); do not reserve label space for an image without a legend. Use the first `####` beneath it as its subtitle.
- When a `##` block contains a Figure/Table but no `###`, create a content slide and derive its title from the first image legend. Remove the leading `Fig. N`, `Figure N`, or `Table N`, and remove the final period. Fall back to the cleaned `##` heading only if no legend is available.
- Use images only from the note. Do not fabricate diagrams or interpretation.
- Keep at most two source images on one content slide and preserve aspect ratio. For a Figure/Table `##` content page, use its legend to derive the page title and do not repeat it around the image. The above-image legend rule applies only to images grouped beneath a `###` content title.
- Treat a Markdown blockquote as a slide Citation only when it is the immediate next semantic line after an image block (`</center>` or a Markdown image). LENS `<!-- figure:... -->` and `<!-- table:... -->` markers may be skipped, but a blank line, prose line, heading, or any other block breaks adjacency. Ignore all non-adjacent blockquotes. Bind each accepted Citation to that specific image rather than to the slide. Render it at 14 pt, centered immediately below its image; when a slide has two cited images, show one independent Citation beneath each image.
- Add a small light-gray page number at the bottom-right of every slide except the cover. Number the first post-cover slide as page 1 by default.
- Ignore ordinary Markdown prose, lists, YAML, and Markdown tables; this workflow produces a figure-led journal-report deck.
- Preserve existing image files and the source note. Re-running may replace only the converter's default PPTX output.

## PowerPoint style configuration

- Edit `ppt.config` instead of changing fixed visual constants in the converter.
- `[paper_title]` controls the paper title; `[citation]` controls cover and image-bound citations and defaults to 14 pt. `image_gap_above_in` and `image_height_in` control the gap below each image and the Citation box height.
- `[page_number]` controls page-number visibility, starting number, font, color, and bottom-right placement. `show_on_cover` defaults to `false`.
- `[section_title]` controls `#` and structural `##` transition-page titles. Its text box height should stay close to the configured font size rather than forming an oversized empty frame.
- `[results_outline_title]`, `[results_outline_item]`, and `[results_outline_inactive_item]` control the Results workflow overview and highlighted Figure/Table transition pages.
- `[content_title]` controls Figure/Table legend titles and `###` titles. `[content_subtitle]` controls optional subtitles. `[image_caption]` controls the centered labels shown above captioned images beneath a `###`; `show_above_h3` defaults to `true`.

## Verification

The script must reopen the generated PPTX, verify its slide count, and fail if any referenced image needed for a generated slide is missing. Do not claim PowerPoint visual inspection unless the deck was actually opened and reviewed there.
