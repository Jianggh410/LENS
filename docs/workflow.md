# Literature Workflow

## 0. Literature follow-up

- `lens-literature-followup` fetches configured journal RSS feeds and bioRxiv metadata.
- Only title or abstract records with literal `USER_RESEARCH` keyword hits enter the summary queue.
- SQLite state lives under `_system/data/literature_followup/`.
- Generated abstract-level pages live under `Literature/Followup/`.
- Run the complete workflow with:

```bash
bash "_system/skills/lens-literature-followup/scripts/run_followup.sh"
```

- A follow-up hit is not a full reading note. Put a selected PDF in Inbox before using `lens-paper-note`.

## 1. Inbox

- Put new PDFs into `$RAW_DIR` (default: `$HOME/ASPIRE/Inbox/Paper`).
- Keep the raw PDF as the source of truth.

## 2. AI first pass

- Let LENS read one PDF and create a markdown note in `Reading/ai-draft/`.
- Every AI-generated note should start with:

```yaml
status: ai-draft
```

- Also try to fill:

```yaml
summary_short:
topics:
tags:
Narrative:
```

- Set `Narrative` to one value from `skills/lens-paper-note/references/narrative-taxonomy.md` only when the paper's main narrative logic is clear, for example `Method-to-Discovery`; otherwise leave it empty.

- If figures are not reliably extracted, keep a manual figure-inspection section instead of forcing AI to guess.
- After a new Article note is generated, `ingest_paper.sh` automatically runs `extract_figures.sh` to crop and insert numbered figures, then rebuilds the wiki. Figure extraction failure does not delete the note.
- To rerun figure extraction independently:

```bash
bash "_system/skills/lens-paper-note/scripts/extract_figures.sh" "/absolute/path/paper.pdf" "/absolute/path/note.md"
```

## 2.5 Reading list

- Use `Reading/Reading_list.canvas` as the only reading-board interface. It supports PDF cards, numbered three-column positions, and manual drag-and-drop arrangement.
- The optional synchronization source is PDFs directly under `$RAW_DIR` plus PDFs in queue folders configured by `$READING_QUEUE_DIRS` (default: `$RAW_DIR/waiting4ai-draft`). Archive and topic folders are not included automatically.
- Synchronize the configured queue manually with:

```bash
bash "_system/skills/lens-paper-note/scripts/rebuild_reading_list.sh"
```

- Wiki rebuilding does not modify the Canvas. Run the synchronization script explicitly only when User wants to import the configured PDF queue. Existing PDF card positions are preserved, but cards manually removed from the Canvas are added again when an explicit synchronization is run while their PDFs remain in the configured queue.

## 3. Human revision

- Read the note yourself.
- Rewrite key sections in your own words where needed.
- Add figures manually into:

`Reading/ai-draft/assets/{note_filename_without_md}/`

- After manual revision, change the YAML status to:

```yaml
status: human-reviewed
```

## 4. Promote to Library

- If the note is digested, analyzed deeply, and worth long-term retention, change the YAML status to:

```yaml
status: human-add2lib
```

- Then manually move it into the correct folder under `Library/` based on the most relevant topic.
- The note being inside `Library/` is the main signal that it is curated/high-quality.
- Its images should live beside that note under the matching `assets/` folder in the same scope.

## 5. Rebuild wiki

- Run:

```bash
bash "_system/skills/lens-paper-note/scripts/rebuild_wiki.sh"
```

Run this command from the Literature root directory.

- `Reading Wiki` includes:
  - notes currently in `Reading/`
  - notes already moved into `Library/`
- `Library Wiki` includes:
  - notes physically stored in `Library/`
- Each wiki has:
  - `pages/`: human-readable home, index, topic, author, and log pages
  - `data/`: machine-readable notes, topics, authors, and graph JSON
  - `GraphView/`: topic/author relationship pages for Obsidian graph navigation

Generated wiki outputs are stored under the top-level `Literature/Wiki/` directory, separate from curated `Synthesis/` notes and runtime `_system/` files.

## 6. Recommended status vocabulary

- `ai-draft`: AI first pass, not manually verified.
- `human-reviewed`: manually read and revised by User; may include important figures, important understanding/thinking, and open questions.
- `human-extended`: User looked up additional material for unresolved questions and added deeper related context.
- `human-add2lib`: digested note with deeper analysis, ready to add to the most relevant Library topic location.

Avoid mixing older free-text statuses such as `AI summary`, `done`, or `finish reading waiting E` in new notes.
