# LENS

**Literature Engine for Note-making and Synthesis**

[中文](README_CN.md) · [Installation](docs/installation.md) · [Configuration](docs/configuration.md) · [Workflow](docs/workflow.md) · [System directories](docs/system-directory.md) · [Troubleshooting](docs/troubleshooting.md)

LENS is a research-literature workflow composed of Codex Skills and executable scripts. Give a PDF to an Agent and LENS can create a structured Chinese Obsidian note, extract Figures and Tables, build literature indexes, monitor new publications, and convert a note into a figure-led PowerPoint.

## Contents

- [1. Project ownership and operations](#1-project-ownership-and-operations)
- [2. Project philosophy and community](#2-project-philosophy-and-community)
- [3. Quick start](#3-quick-start)
- [4. Installation](#4-installation)
- [5. Skill index](#5-skill-index)
- [6. Contributing and development](#6-contributing-and-development)

## 1. Project ownership and operations

- **Creator and maintainer**: Howard Jiang
- **Repository**: [Jianggh410/LENS](https://github.com/Jianggh410/LENS)
- **Bug reports and feature requests**: [GitHub Issues](https://github.com/Jianggh410/LENS/issues)
- **License**: [LICENSE](LICENSE)

LENS began as a practical research knowledge-base workflow. Its goal is to connect literature discovery, full-paper reading, evidence extraction, note creation, continued curation, and presentation in one reusable system.

## 2. Project philosophy and community

LENS follows six principles:

1. **The source paper is authoritative**: metadata, methods, results, and figure interpretation must be grounded in the PDF or a verified first-party page.
2. **Evidence structure comes first**: notes organize Works, Results/Evidence, a Question–Method Map, an Evidence Chain, limitations, and research implications—not just an abstract-level summary.
3. **AI drafts and human curation are distinct**: new notes begin as `ai-draft` and move to the Library only after human review.
4. **Uncertainty triggers explicit fallback**: when Figure/Table completeness cannot be confirmed, LENS preserves a candidate and requests manual inspection instead of inventing missing content.
5. **Outputs remain directly usable**: workflows produce Markdown, PNG, JSON, Canvas, Wiki, and PPTX artifacts rather than leaving the result only inside a chat.
6. **Skills are self-contained and extensible**: rules, templates, and scripts are grouped by Skill so capabilities can evolve independently.

Use GitHub Issues for bugs, rule proposals, journal-layout examples, and workflow requests. Include a minimal reproducible input, expected behavior, and actual behavior whenever possible. Do not publicly upload copyrighted full text unless you have permission to distribute it.

## 3. Quick start

After installation, give a paper or note directly to an Agent. If you do not know which Skill applies, describe the outcome you want. If you know the Skill name, mention it explicitly.

| Goal | Example prompt |
| --- | --- |
| Read a paper | `Use LENS to read this PDF and create a structured literature note.` |
| Re-extract figures | `Use LENS to re-extract the Figures and verify panel completeness.` |
| Process a Review | `Use LENS to read this Review and organize Evidence by Figure and Table.` |
| Create slides | `Turn this paper note into a PowerPoint.` |
| Inspect status | `Check the current LENS literature-note status.` |
| Monitor literature | `Run the LENS literature follow-up workflow.` |

### Use LENS in an Agent

Attach a PDF and state the task in natural language. The Agent loads the local LENS rules, runs the corresponding workflow, and returns an openable note path plus extraction status.

![Using LENS in an Agent](assets/agent-usage-example.png)

### Structured note output

An Article note normally contains YAML metadata, Info, Summary, Intro, Works, Results, a Question–Method Map, Discussion, and Key references. A Review organizes Evidence around numbered Figures and Tables. Extracted visual assets live beside the note in its matching assets directory.

![Example LENS paper note](assets/paper-note-example.png)

## 4. Installation

### 4.1 Clone to a stable location

```bash
git clone git@github.com:Jianggh410/LENS.git
cd LENS
```

Do not place the repository in a temporary directory that the operating system may clean automatically. LENS derives its runtime configuration, Skills, and persistent-data locations from the repository path.

### 4.2 Validate the environment

```bash
bash scripts/validate.sh
```

Validation checks required files, shell and Python syntax, JSON configuration, and derived runtime paths.

### 4.3 Connect LENS to Codex

```bash
bash scripts/install.sh
```

The installer links supported LENS Skills into the Codex Skills directory. See the [installation guide](docs/installation.md) for dependencies, path configuration, and updates.

### 4.4 Configure research projects and sources

Edit:

- `config/lens_config.sh` for paper locations, the Literature workspace, project keywords, models, and extraction settings.
- `config/followup_sources.json` for journal RSS feeds and preprint sources.

See the [configuration guide](docs/configuration.md) for field-level details.

## 5. Skill index

### `lens-paper-note`

Reads an Article or Review PDF and creates a structured Chinese Obsidian note. It also provides:

- YAML metadata and narrative classification
- Article Results and Review Evidence organization
- Question–Method Map and Evidence Chain
- numbered Figure and Review Table extraction
- panel, caption, edge, and crop-integrity checks
- Reading and Library Wiki rebuilding
- Reading Canvas and note-status utilities

### `lens-literature-followup`

Fetches new records from configured RSS/API sources, matches them to `USER_RESEARCH` keywords, stores persistent history, and creates weekly and project-level follow-up pages.

### `lens-paper-note-to-ppt`

Converts a LENS Markdown note into a Figure/Table-led PPTX deck. Its title, typography, citation, legend, page-number, and layout rules are controlled by the Skill's `ppt.config`.

## 6. Contributing and development

### 6.1 Shared design principles

Every LENS Skill should follow these principles:

1. **Prefer primary sources**: base rules on original papers, official journal pages, databases, or explicit local sources.
2. **Prefer explicit state**: important decisions should leave a status, confidence, failure reason, or inspectable intermediate artifact.
3. **Respect document type and layout**: Articles, Reviews, journals, captions, and panel styles require context-aware logic.
4. **Deliver usable outputs**: return `.md`, `.png`, `.json`, `.canvas`, or `.pptx` artifacts.
5. **Remain extensible**: each Skill is self-contained; adding one should avoid breaking existing workflows.
6. **Protect user content**: do not overwrite human-edited notes, treat cache as persistent data, or hand-edit generated Wikis.

### 6.2 Repository structure

Directory responsibilities, cleanup safety, cleanup impact, and regeneration behavior are maintained in:

- [System directories and cleanup](docs/system-directory.md)
- [系统目录与清理说明](docs/system-directory_CN.md)

The README intentionally avoids duplicating runtime-directory details that could drift away from the implementation.

### 6.3 Adding a Skill

1. Create a standalone directory under `skills/`:

   ```text
   skills/lens-<topic>/
   ```

2. Add `SKILL.md` with clear triggers, scope boundaries, inputs, outputs, and fallback behavior.
3. Add `agents/`, `references/`, `assets/`, `scripts/`, or a dedicated configuration file as needed.
4. Add the required structural and syntax checks to `scripts/validate.sh`.
5. Update installation logic, the Skill index, and relevant documentation.
6. Run validation and test the complete workflow using a small, legally distributable example.

```bash
bash scripts/validate.sh
```

### 6.4 Change guidelines

- Do not commit user data, PDFs, databases, cache, or logs.
- Figure/Table extraction changes must document success, fallback, and manual-review paths.
- Template changes must preserve compatibility with the Wiki, PPT workflow, and existing notes.
- Configuration changes must be reflected in `docs/configuration.md` and its examples.
