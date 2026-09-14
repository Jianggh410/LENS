Read `../wiki-rules.md` first.

Task:
Rebuild the literature wikis.

Part 1: Reading Wiki
- Scan reading notes recursively under Reading plus all Library markdown notes.
- Treat Library notes as still part of the Reading knowledge base.
- Exclude `_system`, assets, templates, prompts, logs, cache, and Skill reference files.
- Remove entries whose note files no longer exist anywhere under literature_dir.
- Rebuild `Wiki/Reading/pages/`, `Wiki/Reading/data/`, and `Wiki/Reading/GraphView/`.
- Append the update to `Wiki/Reading/pages/04_Reading_Log.md`.

Part 2: Library Wiki
- Scan only Library.
- Include all markdown notes physically located in Library.
- Rebuild `Wiki/Library/pages/`, `Wiki/Library/data/`, and `Wiki/Library/GraphView/`.
- Append the update to `Wiki/Library/pages/04_Library_Log.md`.

Part 3: Output structure
- `pages/`: numbered Markdown pages for people; every page must start with one `#` title.
- `data/`: `notes.json`, `topics.json`, `authors.json`, and `graph.json` for programs and visualizations.
- `GraphView/`: two-level Markdown networks: `Topics-graph.md -> nodes/Topics/<topic>.md -> paper notes` and `Authors-graph.md -> nodes/Authors/<author>.md -> paper notes`.
- Do not recreate the retired flat `index.md`, `topics.md`, `authors.md`, `graph.md`, or `log.md` files.

Part 4: Report
- Number of Reading-scope notes
- Number of Library notes
- Notes still marked ai-draft
- Notes missing YAML fields
- Broken internal links if easy to detect
