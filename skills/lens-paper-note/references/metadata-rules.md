# Metadata Rules

Use the YAML fields and order defined by the selected template.

## Required behavior

- Set `type` to `Article` or `Review` from the paper itself.
- Set `status: ai-draft` for newly generated notes.
- Set `start_reading_date` to the date the AI draft is created.
- Leave `note`, `finish_reading_date`, and `complete_date` empty for a new AI draft.
- Write `doi` as a full `https://doi.org/...` URL when verified.
- Write `topics` and `tags` as YAML lists.
- Topics are human-readable categories and may contain spaces.
- Tags have no leading `#` or whitespace. Capitalize the first letter, preserve proper nouns, uppercase abbreviations, and join multiple words with hyphens, for example `Gene-regulation`, `RNA-seq`, `CRISPR-screen`, and `AIVC`.
- Prefer 3–8 focused tags and reuse existing spellings when possible.
- Set exactly one allowed `narrative` only when the evidence progression is clear; otherwise leave it empty.
- Write `summary_short` as one concise Chinese sentence.

Never invent missing metadata. Leave an optional YAML value empty when it cannot be verified.
