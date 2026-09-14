Read `../figure-rules.md` first.

Task:
Extract complete numbered Figures—and numbered Tables for Reviews—from one paper PDF and insert them into its existing Article or Review note.

Rules:
1. Run `scripts/extract_figures.sh <paper.pdf> <note.md>` after the structured note exists.
2. Extract Figures represented by numbered `## Fig. N ...` or `## Figure N ...` headings under `# Results` (Article) or `# Evidence` (Review). When `LENS_REVIEW_EXTRACT_TABLES=1`, also extract Review `## Table N. ...` headings under `# Evidence`; do not extract Tables from Article `# Results`.
3. Store stable images as `Fig-NN.png` or `Table-NN.png` and metadata as `figures.json` under the note's matching assets directory. Use type plus number as the unique identity.
4. Insert each image immediately below its matching heading using type-specific managed HTML markers defined by the extraction script.
5. Do not overwrite an existing unmarked image unless User explicitly requests `--replace-existing`.
6. Treat caption matching, crop dimensions, duplicate hashes, and visual inspection as quality gates. Never insert a guessed figure.
6.1 Keep the complete original caption in every same-page Figure crop by default. For Tables, keep the title, full header, every data row, and all footnotes. Include horizontally adjacent or column-confined caption/title blocks in the same rectangle without admitting neighboring prose. If the caption/title is on another page, keep it external and record that state explicitly in `figures.json`.
7. For Science-style column-wrapped figures, use column-aware figure bounds and caption panel references. If deterministic completeness remains uncertain, render a complete-region/page candidate and run the vision-AI isolation and panel-verification fallback.
7.1 For Review layouts, inspect the caption's own column above it and the neighboring horizontal span on the same page before selecting an adjacent page. Parse Review panel labels in parenthesized, pipe, and dot styles as configured at runtime.
8. Insert an AI-refined visual only after completeness is confirmed: all expected panels, caption, text/axes/graphics, and neighboring-Figure separation for a Figure; complete title, header, every row, all footnotes, and neighboring-item separation for a Table. Expand its bbox by the configured 8–12 pt safety padding (10 pt by default). Residual post-expansion contact is recorded as `edge-contact-warning` with `confidence: medium`; it does not block insertion. Use `status: manual-review` only for missing required content, definite truncation, inseparable neighboring items, an incomplete co-located caption/title, an unsafe out-of-page bbox, or failure by AI to confirm completeness.
9. To re-run selected Figures through this recovery path, set `LENS_FIGURE_AI_FORCE_NUMBERS` to comma-separated numbers (for example, `2,4`) and use `--replace-existing`.
