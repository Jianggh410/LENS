# Wiki Rules

Write all generated outputs under the top-level `Literature/Wiki/` directory. Do not place generated Wiki files under `_system/` or curated `Synthesis/`.

## Reading scope

Include valid Article and Review notes under both `Reading/` and `Library/`. A note moved to Library remains part of the reading knowledge base.

## Library scope

Include only valid Article and Review notes physically stored under `Library/`.

## Generated structure

Each scope contains:

- `pages/`: numbered Markdown navigation pages, each starting with one `#` title.
- `data/`: `notes.json`, `topics.json`, `authors.json`, and `graph.json`.
- `GraphView/`: `Topics-graph.md` and `Authors-graph.md`, linked through `nodes/Topics/` and `nodes/Authors/` to paper notes.

Generated outputs are disposable projections of the notes. Never edit them manually; rebuild them with `scripts/rebuild_wiki.sh`.
