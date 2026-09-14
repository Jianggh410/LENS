Read `../note-rules.md`, `../metadata-rules.md`, `../citation-rules.md`, `../narrative-taxonomy.md`, and `../typography-rules.md` first.

Task:
Process one paper from raw_dir.

Input paper:
{{PAPER_PATH}}

Steps:
1. Determine whether this is an Article or Review.
2. Use the corresponding template from `assets/templates/`.
3. Generate a structured markdown note in Reading/ai-draft.
3.1 Name the note exactly from the input PDF basename, replacing only `.pdf` with `.md`. Preserve user abbreviations such as `N`, `NG`, `C`, and `bioRxiv`; do not expand them from journal metadata. Use the same basename for the asset directory.
4. Fill YAML metadata.
4.5 Always write YAML doi as a full URL in the form https://doi.org/<DOI>.
4.6 Write YAML citation as a two-line block scalar using the first author. Format: first line `First author et al., Journal (Year)`; second line `First author et al., Title, Journal (Year)`. Do not use the corresponding author unless that person is also the first author.
4.7 Always include the lowercase YAML property `narrative`. Use exactly one value from `../narrative-taxonomy.md` when the paper's main evidence progression is clear, for example `narrative: Method-to-Discovery`. Otherwise leave `narrative:` empty. Do not invent new narrative values.
4.8 Write `topics` and `tags` as YAML lists. Topics may be human-readable phrases. Tags must not have a leading `#`, spaces, commas, semicolons, or other whitespace. Capitalize the first letter of each tag, preserve proper-noun capitalization, write abbreviations/acronyms in uppercase, and join multiple words with hyphens, for example `Gene-regulation`, `RNA-seq`, `CRISPR-screen`, and `AIVC`. Prefer 3–8 focused tags and reuse existing spellings when possible.
5. Set status: ai-draft.
5.1 Set `start_reading_date` to the `ai_draft_date` supplied by the ingest script. It is the date the AI draft is created, not the paper's publication date.
5.5 Keep the note title in English, but write the explanatory body text in Chinese.
5.5.0 Apply all Chinese–English spacing, punctuation, unit, percentage, slash, hyphen, range, parentheses, Markdown-link, and whitespace rules from `../typography-rules.md` to newly generated explanatory prose.
5.5.1 If the paper title contains `:` or `：`, replace that character with `-` when recording the title in the note.
5.5.2 For both Article and Review notes, use this exact # Info structure: `## 文章介绍`, `## 通讯作者与单位`, and `## 数据与代码`. Under 文章介绍, use one concise Chinese sentence to state only the document type, journal or preprint platform, publication status, and publication date or year; do not summarize scientific content. Under 通讯作者与单位, give every corresponding author a separate block: a standalone `**通讯作者**：Name` line followed by that author's `- **单位**：`, `- **研究方向**：`, and `- **实验室网站**：` fields, with a blank line between author blocks. Never merge multiple authors into shared fields. Search for each corresponding author's laboratory website and verify it using an official lab, university, institute, or ORCID page; prefer the official lab website and never invent a URL. Render every verified website as a clickable Markdown link such as `[Daniel A. Lim Lab](https://danlimlab.ucsf.edu/)`, never as a bare URL; write `未说明` when no website is verified. Under 数据与代码, explain what data were used or generated, including biological source, assay or processing, new versus reused status, accession numbers, repositories, code, and project links when available; write `未说明` when unavailable. Never discuss the user's research relevance in # Info.
5.5.3 For Article notes, put figures worth focusing on at the end of # Summary, immediately before # Intro, not in # Info. Use the exact heading `**Figures worth focusing on**`, followed by bullets such as `- **Fig. 1**：xxx。`
5.6 In # Intro, do not introduce or explain figures.
5.7 For Article notes, write # Works by work modules, not by figure. After reading # Works, the reader should understand how the paper is constructed.
5.8 For Article notes, write # Results by the main result of each figure. Use the original English figure title as each subsection title whenever available, then explain the figure's main result and evidence in Chinese. Do not add a separate Key evidence block to # Results. After reading # Results, the reader should understand what the paper proved.
5.8.1 For Article notes, add # Question–Method Map immediately after # Results and before # Discussion. Treat it as a compressed question tree: state one Core Question, then select 3–8 key Question–Method pairs that genuinely advance the evidence chain. Do not use a fixed list of questions, follow figure order, or turn it into an experiment inventory. Format each pair as `## Qn. [an experimentally answerable key question]`, followed by `**Method:**` and a concise Chinese summary of the core experimental design, core analysis method, and how the method answers that question. Combine methods that answer the same question and omit routine procedural details.
5.9 For Review notes, write # Works by viewpoint/framework modules, not by visual item or by merely restating the original table of contents. Organize # Evidence by the Review's main numbered Figures and Tables in source order. Create one subsection per item using `## Figure N. Original English title` (or the source's `Fig.` style) and `## Table N. Original English title`. Explain Figures in Chinese through their framework/model, supported viewpoint, representative evidence, and the boundary between evidence synthesis and author framing. Explain Tables through their comparison dimensions, important rows/columns, supported viewpoint, evidence provenance, and synthesis boundary. These headings are extraction anchors, so preserve the type, number, and original English title exactly.
5.10 For both Article and Review notes, use the concise Discussion structure from `../note-rules.md` and the templates. Interpretation contains `Question & Conclusion`, a numbered 3–8-step `Evidence Chain`, and `Logic / Paradigm`. Contribution & Critique contains `Prior Knowledge & Advance`, `Innovation & Significance`, and `Limitations & Open Questions`. Implications contains `Storytelling`, `Experimental Strategy`, `Visualization`, and `My Research`. Under `My Research`, create one `#### <Project name>` subsection for every project key in `USER_RESEARCH`, preserve configuration order, and discuss each project separately in 1–3 concise Chinese sentences. Do not omit weakly related projects; state the weak relationship briefly. Write the analysis in Chinese while retaining these English headings.
6. Add "Figures to manually inspect" if figures are missing or unreliable.
7. After the note is created, let the shell pipeline run `scripts/extract_figures.sh` for Article `# Results` Figure headings or Review `# Evidence` Figure/Table headings. Do not invent or prefill image paths during note generation.
8. Let the shell pipeline run `scripts/rebuild_wiki.sh`; do not edit generated wiki files manually.
9. Confirm the Reading pages, JSON data, and GraphView were rebuilt under `Wiki/Reading/`.
10. Store note assets under Reading/ai-draft/assets/{note_filename_without_md}/.
11. Do not update Library Wiki unless the note is already inside Library.
