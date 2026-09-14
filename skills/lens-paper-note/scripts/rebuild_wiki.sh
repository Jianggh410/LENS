#!/usr/bin/env bash
set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONFIG_FILE="${LENS_CONFIG_FILE:-$RUNNER_DIR/../../../config/lens_config.sh}"
source "$CONFIG_FILE" || {
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
}

timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p \
  "$READING_WIKI_PAGES_DIR" "$READING_WIKI_DATA_DIR" "$READING_WIKI_GRAPH_VIEW_DIR" \
  "$LIBRARY_WIKI_PAGES_DIR" "$LIBRARY_WIKI_DATA_DIR" "$LIBRARY_WIKI_GRAPH_VIEW_DIR"

tmp_reading="$(mktemp)"
tmp_library="$(mktemp)"
tmp_report="$(mktemp)"
tmp_workdir="$(mktemp -d)"

# 脚本结束时自动删除临时文件
cleanup() {
  rm -f "$tmp_reading" "$tmp_library" "$tmp_report"
  rm -rf "$tmp_workdir"
}
trap cleanup EXIT

# 检查笔记是否有效
is_valid_note() {
  local file="$1"
  local type title status

  [[ "$file" == *"/.codex_tmp/"* ]] && return 1

  if [[ "$(head -n 1 "$file" 2>/dev/null)" != "---" ]]; then
    return 1
  fi

  type="$(yaml_scalar "$file" "type")"
  title="$(yaml_scalar "$file" "title")"
  status="$(yaml_scalar "$file" "status")"

  [[ "$type" == "Article" || "$type" == "Review" ]] || return 1
  [[ -n "$title" ]] || return 1
  [[ -n "$status" ]] || return 1
}

# 收集阅读笔记
collect_reading_notes() {
  while IFS= read -r file; do
    if is_valid_note "$file"; then
      printf '%s\n' "$file"
    fi
  done < <(find "$READING_DIR" -type f -name "*.md" ! -path "*/assets/*")

  while IFS= read -r file; do
    if is_valid_note "$file"; then
      printf '%s\n' "$file"
    fi
  done < <(find "$LIB_DIR" -type f -name "*.md")

  return 0
}

# 收集图书馆笔记
collect_library_notes() {
  while IFS= read -r file; do
    if is_valid_note "$file"; then
      printf '%s\n' "$file"
    fi
  done < <(find "$LIB_DIR" -type f -name "*.md")

  return 0
}

status_count() {
  local wanted_status="$1"
  local file count=0

  while IFS= read -r file; do
    if [[ "$(yaml_scalar "$file" "status")" == "$wanted_status" ]]; then
      count=$((count + 1))
    fi
  done

  printf '%s\n' "$count"
}

# 提取YAML标量
yaml_scalar() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    $0 == "---" && in_yaml == 0 { in_yaml = 1; next }
    $0 == "---" && in_yaml == 1 { exit }
    in_yaml == 1 && $0 ~ ("^" key ":") {
      line = $0
      sub("^[^:]*:[[:space:]]*", "", line)
      print line
      exit
    }
  ' "$file"
}

# 提取YAML列表
yaml_list() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    $0 == "---" && in_yaml == 0 { in_yaml = 1; next }
    $0 == "---" && in_yaml == 1 { exit }
    in_yaml == 1 && $0 ~ ("^" key ":") { in_list = 1; next }
    in_yaml == 1 && in_list == 1 {
      if ($0 ~ /^[A-Za-z0-9_-]+:/) { exit }
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        line = $0
        sub("^[[:space:]]*-[[:space:]]*", "", line)
        print line
      }
    }
  ' "$file"
}

# 提取YAML列表的第一个元素
yaml_first_list_item() {
  local file="$1"
  local key="$2"
  yaml_list "$file" "$key" | head -n 1
}

# 将多行文本连接成一行
join_lines() {
  local separator="$1"
  awk -v sep="$separator" 'NF { out = out ? out sep $0 : $0 } END { print out }'
}

# 提取markdown段的摘要
markdown_section_summary() {
  local file="$1"
  awk '
    BEGIN { in_summary = 0 }
    /^# Summary/ { in_summary = 1; next }
    /^# / && in_summary == 1 { exit }
    in_summary == 1 {
      if ($0 ~ /^---$/) next
      if ($0 ~ /^#+ /) next
      if ($0 ~ /^[[:space:]]*$/) {
        if (seen_text == 1) exit
        next
      }
      if ($0 ~ /^</) next
      if ($0 ~ /^```/) next
      gsub(/[[:space:]]+/, " ", $0)
      text = text ? text " " $0 : $0
      seen_text = 1
    }
    END { print text }
  ' "$file"
}

# 截断文本
truncate_text() {
  local text="$1"
  local limit="$2"

  if [[ ${#text} -le $limit ]]; then
    printf '%s\n' "$text"
  else
    printf '%s...\n' "${text:0:limit}"
  fi
}

# 清理表格单元格
sanitize_cell() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//; s/|/\\|/g'
}

# Wiki/<scope>/pages -> Literature root
relative_link() {
  local file="$1"
  local relative="${file#$LITERATURE_DIR/}"
  relative="${relative//>/%3E}"
  relative="${relative//</%3C}"
  printf '<../../../%s>' "$relative"
}

# 提取论文标题
paper_title() {
  local file="$1"
  local title

  title="$(yaml_scalar "$file" "title")"
  if [[ -z "$title" ]]; then
    title="$(basename "${file%.md}")"
  fi
  printf '%s\n' "$title"
}

# 提取论文年份
paper_year() {
  local file="$1"
  local year
  year="$(yaml_scalar "$file" "year")"
  printf '%s\n' "${year:-unknown}"
}

# 提取论文状态
paper_status() {
  local file="$1"
  local status
  status="$(yaml_scalar "$file" "status")"
  printf '%s\n' "${status:-unknown}"
}

# 提取论文期刊
paper_journal() {
  local file="$1"
  local journal
  journal="$(yaml_scalar "$file" "journal")"
  printf '%s\n' "${journal:-unknown}"
}

# 提取论文作者
paper_author_display() {
  local file="$1"
  local first_author scalar_author

  first_author="$(yaml_first_list_item "$file" "author")"
  scalar_author="$(yaml_scalar "$file" "author")"

  if [[ -n "$first_author" ]]; then
    printf '%s\n' "$first_author"
  elif [[ -n "$scalar_author" ]]; then
    printf '%s\n' "$scalar_author"
  else
    printf 'unknown\n'
  fi
}

# 提取论文主题
paper_topics_display() {
  local file="$1"
  local topics tags joined

  topics="$(yaml_list "$file" "topics" | join_lines ', ')"
  tags="$(yaml_list "$file" "tags" | join_lines ', ')"

  if [[ -n "$topics" && -n "$tags" ]]; then
    joined="$topics, $tags"
  elif [[ -n "$topics" ]]; then
    joined="$topics"
  elif [[ -n "$tags" ]]; then
    joined="$tags"
  else
    joined="unknown"
  fi

  printf '%s\n' "$joined"
}

# 提取论文摘要
paper_one_line_summary() {
  local file="$1"
  local summary

  summary="$(yaml_scalar "$file" "summary_short")"
  if [[ -z "$summary" ]]; then
    summary="$(markdown_section_summary "$file")"
  fi
  if [[ -z "$summary" ]]; then
    summary="unknown"
  fi
  truncate_text "$summary" 400
}

# 生成表格行
note_row() {
  local file="$1"
  local relative title year status section link author journal topics summary

  relative="${file#$LITERATURE_DIR/}"
  title="$(paper_title "$file")"
  year="$(paper_year "$file")"
  status="$(paper_status "$file")"
  author="$(paper_author_display "$file")"
  journal="$(paper_journal "$file")"
  topics="$(paper_topics_display "$file")"
  summary="$(paper_one_line_summary "$file")"

  section="${relative%%/*}"
  relative="${relative//>/%3E}"
  relative="${relative//</%3C}"
  link="<../../../$relative>"

  printf '| %s | %s | %s | %s | %s | %s | %s | [%s](%s) |\n' \
    "$(sanitize_cell "$year")" \
    "$(sanitize_cell "$status")" \
    "$(sanitize_cell "$section")" \
    "$(sanitize_cell "$author")" \
    "$(sanitize_cell "$journal")" \
    "$(sanitize_cell "$topics")" \
    "$(sanitize_cell "$summary")" \
    "$(sanitize_cell "$title")" \
    "$link"
}

# 计算缺失YAML的数量
missing_yaml_count() {
  local count=0
  local file field value

  while IFS= read -r file; do
    for field in title year type status; do
      value="$(yaml_scalar "$file" "$field")"
      if [[ -z "$value" ]]; then
        count=$((count + 1))
        break
      fi
    done
  done

  printf '%s\n' "$count"
}

# 追加日志
append_log() {
  local file="$1"
  local scope="$2"
  local total="$3"
  local ai_drafts="$4"
  local missing_yaml="$5"

  printf -- '- %s | %s notes: %s | ai-draft: %s | missing-yaml: %s\n' \
    "$timestamp" "$scope" "$total" "$ai_drafts" "$missing_yaml" >> "$file"
}

# 生成主题页面
write_topics_page() {
  local list_file="$1"
  local output_file="$2"
  local scope_label="$3"
  local edges_file="$tmp_workdir/topics.tsv"
  local file topic title link year journal summary

  : > "$edges_file"
  while IFS= read -r file; do
    while IFS= read -r topic; do
      [[ -z "$topic" ]] && continue
      title="$(paper_title "$file")"
      link="$(relative_link "$file")"
      year="$(paper_year "$file")"
      journal="$(paper_journal "$file")"
      summary="$(paper_one_line_summary "$file")"
      printf '%s\t%s\t%s\t%s\t%s\n' "$topic" "$year" "$journal" "$summary" "[$title]($link)" >> "$edges_file"
    done < <(yaml_list "$file" "topics" | awk 'NF' | sort -u)
  done < "$list_file"

  {
    printf '# %s Topics\n\n' "$scope_label"
    printf 'Generated: %s\n\n' "$timestamp"
    printf 'This page groups notes by YAML `topics`. Tags remain available in `../data/notes.json`.\n\n'

    if [[ ! -s "$edges_file" ]]; then
      printf 'No topics found.\n'
    else
      python3 - "$edges_file" <<'PY2'
import sys
from collections import defaultdict
path = sys.argv[1]
groups = defaultdict(list)
with open(path, encoding='utf-8') as fh:
    for line in fh:
        topic, year, journal, summary, link = line.rstrip('\n').split('\t')
        groups[topic].append((year, journal, link, summary))
for topic in sorted(groups):
    print(f"## {topic} ({len(groups[topic])})\n")
    for year, journal, link, summary in groups[topic]:
        print(f"- {year} | {journal} | {link} | {summary}")
    print()
PY2
    fi
  } > "$output_file"
}

# 生成作者页面
write_authors_page() {
  local list_file="$1"
  local output_file="$2"
  local scope_label="$3"
  local edges_file="$tmp_workdir/authors.tsv"
  local file author title link year journal topics

  : > "$edges_file"
  while IFS= read -r file; do
    while IFS= read -r author; do
      [[ -z "$author" ]] && continue
      title="$(paper_title "$file")"
      link="$(relative_link "$file")"
      year="$(paper_year "$file")"
      journal="$(paper_journal "$file")"
      topics="$(paper_topics_display "$file")"
      printf '%s\t%s\t%s\t%s\t%s\n' "$author" "$year" "$journal" "$topics" "[$title]($link)" >> "$edges_file"
    done < <(yaml_list "$file" "author")
  done < "$list_file"

  {
    printf '# %s Authors\n\n' "$scope_label"
    printf 'Generated: %s\n\n' "$timestamp"
    printf 'This page groups notes by YAML `author`.\n\n'

    if [[ ! -s "$edges_file" ]]; then
      printf 'No author lists found.\n'
    else
      python3 - "$edges_file" <<'PY2'
import sys
from collections import defaultdict
path = sys.argv[1]
groups = defaultdict(list)
with open(path, encoding='utf-8') as fh:
    for line in fh:
        author, year, journal, topics, link = line.rstrip('\n').split('\t')
        groups[author].append((year, journal, link, topics))
for author in sorted(groups):
    print(f"## {author} ({len(groups[author])})\n")
    for year, journal, link, topics in groups[author]:
        print(f"- {year} | {journal} | {link} | {topics}")
    print()
PY2
    fi
  } > "$output_file"
}

# 生成索引页面
write_index_page() {
  local list_file="$1"
  local output_file="$2"
  local scope_label="$3"
  local scope_description="$4"

  {
    printf '# %s Literature Index\n\n' "$scope_label"
    printf 'Generated: %s\n\n' "$timestamp"
    printf '%s\n\n' "$scope_description"
    printf '| Year | Status | Scope | Author | Journal | Topics | One-line summary | Title |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
    while IFS= read -r file; do
      note_row "$file"
    done < "$list_file"
  } > "$output_file"
}

# 生成范围首页
write_home_page() {
  local output_file="$1"
  local scope_label="$2"
  local scope_description="$3"
  local total="$4"
  local ai_drafts="$5"
  local missing_yaml="$6"

  {
    printf '# %s Literature Wiki\n\n' "$scope_label"
    printf 'Generated: %s\n\n' "$timestamp"
    printf '%s\n\n' "$scope_description"
    printf '## Browse\n\n'
    printf -- '- [Literature index](./01_%s_Index.md)\n' "$scope_label"
    printf -- '- [Topics](./02_%s_Topics.md)\n' "$scope_label"
    printf -- '- [Authors](./03_%s_Authors.md)\n' "$scope_label"
    printf -- '- [Build log](./04_%s_Log.md)\n\n' "$scope_label"
    printf '## Snapshot\n\n'
    printf -- '- Notes: %s\n' "$total"
    printf -- '- AI drafts: %s\n' "$ai_drafts"
    printf -- '- Notes with missing core YAML (`title`, `year`, `type`, or `status`): %s\n' "$missing_yaml"
  } > "$output_file"
}

# 生成机器可读数据和 Markdown 关系图
write_structured_data() {
  local list_file="$1"
  local data_dir="$2"
  local visual_dir="$3"
  local scope_label="$4"

  python3 - "$list_file" "$data_dir" "$visual_dir" "$scope_label" "$LITERATURE_DIR" "$timestamp" <<'PY2'
import ast
import hashlib
import json
import re
import shutil
import sys
from collections import defaultdict
from pathlib import Path

list_file, data_dir, visual_dir, scope, literature_dir, generated = sys.argv[1:]
root = Path(literature_dir)
data_path = Path(data_dir)
visual_root = Path(visual_dir)
visual_root.mkdir(parents=True, exist_ok=True)


def clean_scalar(value):
    value = value.strip()
    if not value:
        return ""
    if value[0:1] in {'"', "'"} and value[-1:] == value[0]:
        try:
            return str(ast.literal_eval(value))
        except (ValueError, SyntaxError):
            return value[1:-1]
    return value


def frontmatter(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    fields = {}
    if not lines or lines[0].strip() != "---":
        return fields, text
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return fields, text
    yaml_lines = lines[1:end]
    i = 0
    while i < len(yaml_lines):
        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", yaml_lines[i])
        if not match:
            i += 1
            continue
        key, raw = match.group(1), match.group(2) or ""
        if not raw:
            values = []
            j = i + 1
            while j < len(yaml_lines):
                item = re.match(r"^\s+-\s+(.*)$", yaml_lines[j])
                if not item:
                    break
                values.append(clean_scalar(item.group(1)))
                j += 1
            fields[key] = values if values else ""
            i = j
            continue
        fields[key] = clean_scalar(raw)
        i += 1
    return fields, "\n".join(lines[end + 1:])


def section_summary(body):
    match = re.search(r"(?ms)^# Summary\s*\n(.*?)(?=^#\s|\Z)", body)
    if not match:
        return ""
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", match.group(1)) if p.strip()]
    if not paragraphs:
        return ""
    return re.sub(r"\s+", " ", paragraphs[0])[:400]


notes = []
for raw_path in Path(list_file).read_text(encoding="utf-8").splitlines():
    if not raw_path:
        continue
    path = Path(raw_path)
    fields, body = frontmatter(path)
    relative = path.relative_to(root).as_posix()
    authors = fields.get("author", [])
    topics = fields.get("topics", [])
    tags = fields.get("tags", [])
    if isinstance(authors, str):
        authors = [authors] if authors else []
    if isinstance(topics, str):
        topics = [topics] if topics else []
    if isinstance(tags, str):
        tags = [tags] if tags else []
    notes.append({
        "id": f"note:{relative}",
        "title": fields.get("title") or path.stem,
        "path": relative,
        "scope": relative.split("/", 1)[0],
        "year": fields.get("year") or "unknown",
        "type": fields.get("type") or "unknown",
        "status": fields.get("status") or "unknown",
        "journal": fields.get("journal") or "unknown",
        "doi": fields.get("doi") or "",
        "authors": authors,
        "topics": topics,
        "tags": tags,
        "narrative": fields.get("narrative") or fields.get("Narrative") or "",
        "summary_short": fields.get("summary_short") or section_summary(body) or "unknown",
    })

notes.sort(key=lambda item: (str(item["year"]), item["title"].casefold()), reverse=True)
topics = defaultdict(list)
authors = defaultdict(list)
for note in notes:
    brief = {key: note[key] for key in ("id", "title", "path", "year", "journal")}
    for topic in note["topics"]:
        topics[topic].append(brief)
    for author in note["authors"]:
        authors[author].append(brief)

meta = {"scope": scope, "generated": generated}
topics_doc = {"metadata": meta, "topics": [
    {"topic": key, "count": len(value), "notes": value}
    for key, value in sorted(topics.items(), key=lambda item: item[0].casefold())
]}
authors_doc = {"metadata": meta, "authors": [
    {"author": key, "count": len(value), "notes": value}
    for key, value in sorted(authors.items(), key=lambda item: item[0].casefold())
]}

graph_nodes = []
graph_edges = []
for note in notes:
    graph_nodes.append({"id": note["id"], "kind": "note", "label": note["title"], "path": note["path"]})
for topic in topics:
    topic_id = f"topic:{topic}"
    graph_nodes.append({"id": topic_id, "kind": "topic", "label": topic})
    for note in topics[topic]:
        graph_edges.append({"source": topic_id, "target": note["id"], "relation": "has_topic"})
for author in authors:
    author_id = f"author:{author}"
    graph_nodes.append({"id": author_id, "kind": "author", "label": author})
    for note in authors[author]:
        graph_edges.append({"source": author_id, "target": note["id"], "relation": "authored"})

documents = {
    "notes.json": {"metadata": meta, "notes": notes},
    "topics.json": topics_doc,
    "authors.json": authors_doc,
    "graph.json": {"metadata": meta, "nodes": graph_nodes, "edges": graph_edges},
}
for filename, document in documents.items():
    (data_path / filename).write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def safe_folder_name(label):
    cleaned = re.sub(r'[\\/:*?"<>|]', "-", label)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .") or "unnamed"
    if len(cleaned) > 100:
        cleaned = f"{cleaned[:87].rstrip()}-{hashlib.sha1(label.encode('utf-8')).hexdigest()[:12]}"
    return cleaned


def unique_folder_names(labels):
    result = {}
    used = {}
    for label in sorted(labels, key=str.casefold):
        base = safe_folder_name(label)
        key = base.casefold()
        if key in used and used[key] != label:
            base = f"{base}-{hashlib.sha1(label.encode('utf-8')).hexdigest()[:8]}"
        used[base.casefold()] = label
        result[label] = base
    return result


for old_canvas in visual_root.glob("*.canvas"):
    old_canvas.unlink()


def write_local_pages(groups, kind, singular):
    legacy_root = visual_root / kind
    if legacy_root.exists():
        shutil.rmtree(legacy_root)

    group_root = visual_root / "nodes" / kind
    group_root.mkdir(parents=True, exist_ok=True)
    file_names = unique_folder_names(groups)

    reserved = kind.casefold()
    for label, filename in list(file_names.items()):
        if filename.casefold() == reserved:
            suffix = hashlib.sha1(label.encode("utf-8")).hexdigest()[:8]
            file_names[label] = f"{filename}-{suffix}"

    expected_files = {f"{filename}.md" for filename in file_names.values()}
    for old_file in group_root.glob("*.md"):
        if old_file.name not in expected_files:
            old_file.unlink()

    index_lines = [
        f"# {scope} {kind}",
        "",
        f"Generated: {generated}",
        "",
        f"This page links each {singular.lower()} to its local paper graph.",
        "",
    ]
    for label, linked_notes in sorted(groups.items(), key=lambda item: item[0].casefold()):
        filename = file_names[label]
        index_lines.append(f"- [{label}](<nodes/{kind}/{filename}.md>) ({len(linked_notes)})")
    (visual_root / f"{kind}-graph.md").write_text("\n".join(index_lines) + "\n", encoding="utf-8")

    for label, linked_notes in sorted(groups.items(), key=lambda item: item[0].casefold()):
        lines = [
            f"# {singular}: {label}",
            "",
            f"Generated: {generated}",
            "",
            f"[{kind} graph index](../../{kind}-graph.md)",
            "",
            "## Papers",
            "",
        ]
        sorted_notes = sorted(
            linked_notes,
            key=lambda item: (str(item["year"]), item["title"].casefold()),
            reverse=True,
        )
        for note in sorted_notes:
            encoded_path = note["path"].replace(">", "%3E").replace("<", "%3C")
            lines.append(
                f"- {note['year']} | {note['journal']} | "
                f"[{note['title']}](<../../../../../{encoded_path}>)"
            )
        filename = file_names[label]
        (group_root / f"{filename}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


legacy_graph_root = visual_root / "graph"
if legacy_graph_root.exists():
    shutil.rmtree(legacy_graph_root)

write_local_pages(topics, "Topics", "Topic")
write_local_pages(authors, "Authors", "Author")
PY2
}

# 
collect_reading_notes | sort > "$tmp_reading"
collect_library_notes | sort > "$tmp_library"

reading_count="$(wc -l < "$tmp_reading" | tr -d ' ')"
library_count="$(wc -l < "$tmp_library" | tr -d ' ')"

reading_ai_drafts="$(status_count "ai-draft" < "$tmp_reading")"
library_ai_drafts="$(status_count "ai-draft" < "$tmp_library")"

reading_missing_yaml="$(missing_yaml_count < "$tmp_reading")"
library_missing_yaml="$(missing_yaml_count < "$tmp_library")"

reading_description='This wiki covers notes currently in `Reading/` and curated notes moved into `Library/`.'
library_description='This wiki covers high-quality notes physically stored in `Library/`.'

write_home_page \
  "$READING_WIKI_PAGES_DIR/00_Reading_Home.md" \
  'Reading' \
  "$reading_description" \
  "$reading_count" \
  "$reading_ai_drafts" \
  "$reading_missing_yaml"

write_home_page \
  "$LIBRARY_WIKI_PAGES_DIR/00_Library_Home.md" \
  'Library' \
  "$library_description" \
  "$library_count" \
  "$library_ai_drafts" \
  "$library_missing_yaml"

write_index_page \
  "$tmp_reading" \
  "$READING_WIKI_PAGES_DIR/01_Reading_Index.md" \
  'Reading' \
  "$reading_description"

write_index_page \
  "$tmp_library" \
  "$LIBRARY_WIKI_PAGES_DIR/01_Library_Index.md" \
  'Library' \
  "$library_description"

write_topics_page "$tmp_reading" "$READING_WIKI_PAGES_DIR/02_Reading_Topics.md" 'Reading'
write_topics_page "$tmp_library" "$LIBRARY_WIKI_PAGES_DIR/02_Library_Topics.md" 'Library'
write_authors_page "$tmp_reading" "$READING_WIKI_PAGES_DIR/03_Reading_Authors.md" 'Reading'
write_authors_page "$tmp_library" "$LIBRARY_WIKI_PAGES_DIR/03_Library_Authors.md" 'Library'

reading_log="$READING_WIKI_PAGES_DIR/04_Reading_Log.md"
library_log="$LIBRARY_WIKI_PAGES_DIR/04_Library_Log.md"
if [[ ! -f "$reading_log" && -f "$READING_WIKI_DIR/log.md" ]]; then
  cp "$READING_WIKI_DIR/log.md" "$reading_log"
fi
if [[ ! -f "$library_log" && -f "$LIBRARY_WIKI_DIR/log.md" ]]; then
  cp "$LIBRARY_WIKI_DIR/log.md" "$library_log"
fi
if [[ ! -f "$reading_log" ]]; then
  printf '# Reading Wiki Build Log\n\n' > "$reading_log"
fi
if [[ ! -f "$library_log" ]]; then
  printf '# Library Wiki Build Log\n\n' > "$library_log"
fi
append_log "$reading_log" 'Reading-scope' "$reading_count" "$reading_ai_drafts" "$reading_missing_yaml"
append_log "$library_log" 'Library' "$library_count" "$library_ai_drafts" "$library_missing_yaml"

write_structured_data \
  "$tmp_reading" \
  "$READING_WIKI_DATA_DIR" \
  "$READING_WIKI_GRAPH_VIEW_DIR" \
  'Reading'

write_structured_data \
  "$tmp_library" \
  "$LIBRARY_WIKI_DATA_DIR" \
  "$LIBRARY_WIKI_GRAPH_VIEW_DIR" \
  'Library'

{
  printf '# Literature Wiki\n\n'
  printf 'Generated: %s\n\n' "$timestamp"
  printf -- '- [Reading wiki](./Reading/pages/00_Reading_Home.md)\n'
  printf -- '- [Library wiki](./Library/pages/00_Library_Home.md)\n'
} > "$WIKI_DIR/README.md"

# Remove files from the former flat layout after the new outputs exist.
rm -f \
  "$READING_WIKI_DIR/index.md" "$READING_WIKI_DIR/topics.md" \
  "$READING_WIKI_DIR/authors.md" "$READING_WIKI_DIR/graph.md" "$READING_WIKI_DIR/log.md" \
  "$LIBRARY_WIKI_DIR/index.md" "$LIBRARY_WIKI_DIR/topics.md" \
  "$LIBRARY_WIKI_DIR/authors.md" "$LIBRARY_WIKI_DIR/graph.md" "$LIBRARY_WIKI_DIR/log.md"

rm -rf "$READING_WIKI_DIR/visual" "$LIBRARY_WIKI_DIR/visual"

{
  printf 'Reading-scope notes: %s\n' "$reading_count"
  printf 'Library notes: %s\n' "$library_count"
  printf 'Reading-scope ai-draft notes: %s\n' "$reading_ai_drafts"
  printf 'Library ai-draft notes: %s\n' "$library_ai_drafts"
  printf 'Reading-scope notes missing core YAML: %s\n' "$reading_missing_yaml"
  printf 'Library notes missing core YAML: %s\n' "$library_missing_yaml"
} > "$tmp_report"

cat "$tmp_report"
