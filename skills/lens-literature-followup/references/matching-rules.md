# Matching Rules

`USER_RESEARCH` must be a JSON object whose keys are research-project names and whose values are keyword arrays.

```json
{
  "Project_name": ["Keyword", "Multi-word phrase", "ACRONYM"]
}
```

- Match case-insensitively against title and abstract only.
- Normalize repeated whitespace and Unicode width before matching.
- A keyword hit in the title scores 3; a hit in the abstract scores 1.
- Record every matched keyword and whether it occurred in title, abstract, or both.
- Only articles with at least one literal hit enter `summary_pending`.
- An article may match multiple projects.
- Semantic similarity may rank literal hits later, but must not admit a zero-hit article by default.
