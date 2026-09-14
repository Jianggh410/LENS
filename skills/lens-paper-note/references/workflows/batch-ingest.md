Read `ingest-paper.md` and the references it requires first.

Task:
Process all unprocessed papers in raw_dir.

Rules:
1. Process .pdf and .md files.
2. Skip files that already have a corresponding note anywhere under Reading or Library.
3. For each paper:
   - classify as Article or Review
   - create note in Reading/ai-draft
   - set status: ai-draft
   - keep the note title in English, but write the explanatory body text in Chinese
   - if the paper title contains `:` or `：`, replace that character with `-` when recording the title in the note
   - store assets under Reading/ai-draft/assets/{note_filename_without_md}/
   - add figure inspection section if needed
4. Update Reading Wiki index.md and log.md.
5. At the end, report:
   - processed files
   - skipped files
   - failed files
   - notes needing manual figure inspection
