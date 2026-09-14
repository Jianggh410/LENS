# LENS Typography Rules

Apply these rules to newly generated Chinese explanatory prose. Preserve source titles, quotations, URLs, DOI strings, code, YAML syntax, Markdown syntax, gene/protein names, and established scientific notation when automatic spacing would alter them.

- Insert one half-width space between Chinese characters and adjacent Latin letters or Arabic numerals: `ATF3 调控基因表达`; `共检测到 32,058 个 peaks`.
- Apply normal English spacing inside English phrases: `ATF3 and p53`; do not insert abnormal extra spaces between abbreviations.
- Use full-width Chinese punctuation in Chinese prose: `，。；：（）`.
- Do not add spaces before or after Chinese punctuation: `ATF3、p53 和 H3K27ac。`
- Insert one space between a number and a scientific unit: `10 kb`, `1.5 μM`, `37 °C`.
- Do not insert a space before a percent sign: `37%`.
- Do not add spaces around `/`, hyphens, or range dashes inside scientific expressions: `ATF3/p53`, `ATF3-KO`, `5–10 kb`.
- Do not add inner spaces in Chinese parentheses: `（Fig. 3）`.
- Keep Markdown links directly adjacent to Chinese punctuation: `实验室网站：[Jindan Yu Lab](https://example.org/)`.
- Remove leading, trailing, repeated, and punctuation-adjacent spaces.

Preferred example:

> 作者在 ATF3-WT 与 ATF3-KO HCT116 细胞中开展 ChIP-seq，发现约 37% 的 p300 peaks 被 ATF3 占据（Fig. 3）。
