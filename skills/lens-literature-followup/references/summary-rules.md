# Summary Rules

Generate summaries only from the supplied title, authors, source, date, abstract, and literal match evidence.

For each article return:

- concise Chinese abstract summary;
- one relevance explanation per matched research project;
- suggested action: `read` or `watch`;
- confidence: `high`, `medium`, or `low`;
- a limitation statement, especially when the abstract is absent or sparse.

Do not infer details that are not stated in the abstract. Mark every rendered item as `Abstract-only` or `Metadata-only`.
