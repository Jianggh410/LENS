#!/usr/bin/env python3
"""Deterministic fetch, match, persistence, and rendering for LENS follow-up."""

from __future__ import annotations

import argparse
import email.utils
import hashlib
import html
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable


USER_AGENT = "LENS-Literature-Followup/1.0 (+local research workflow)"
DOI_RE = re.compile(r"10\.\d{4,9}/[-._;()/:A-Z0-9]+", re.I)
TAG_RE = re.compile(r"<[^>]+>")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def require_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"Missing environment variable: {name}. Source lens_config.sh first.")
    return value


def paths() -> dict[str, Path]:
    return {
        "db": Path(require_env("FOLLOWUP_DB")),
        "sources": Path(require_env("FOLLOWUP_SOURCE_CONFIG")),
        "output": Path(require_env("FOLLOWUP_DIR")),
        "weekly": Path(require_env("FOLLOWUP_WEEKLY_DIR")),
        "projects": Path(require_env("FOLLOWUP_PROJECTS_DIR")),
        "template": Path(require_env("FOLLOWUP_TEMPLATE_DIR")) / "weekly_digest.md",
    }


def connect() -> sqlite3.Connection:
    db = paths()["db"]
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS sources (
          source_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          source_type TEXT NOT NULL,
          config_json TEXT NOT NULL,
          last_success_at TEXT,
          last_error TEXT
        );

        CREATE TABLE IF NOT EXISTS articles (
          article_id INTEGER PRIMARY KEY AUTOINCREMENT,
          canonical_key TEXT NOT NULL UNIQUE,
          doi TEXT,
          title TEXT NOT NULL,
          authors_json TEXT NOT NULL DEFAULT '[]',
          abstract TEXT NOT NULL DEFAULT '',
          journal TEXT NOT NULL DEFAULT '',
          source_id TEXT NOT NULL,
          source_url TEXT NOT NULL DEFAULT '',
          published_at TEXT NOT NULL DEFAULT '',
          version TEXT NOT NULL DEFAULT '',
          content_hash TEXT NOT NULL,
          first_seen_at TEXT NOT NULL,
          last_seen_at TEXT NOT NULL,
          summary_status TEXT NOT NULL DEFAULT 'not_matched',
          summary_attempts INTEGER NOT NULL DEFAULT 0,
          summary_error TEXT NOT NULL DEFAULT '',
          FOREIGN KEY(source_id) REFERENCES sources(source_id)
        );

        CREATE INDEX IF NOT EXISTS idx_articles_doi ON articles(doi);
        CREATE INDEX IF NOT EXISTS idx_articles_summary_status ON articles(summary_status);

        CREATE TABLE IF NOT EXISTS matches (
          article_id INTEGER NOT NULL,
          project TEXT NOT NULL,
          keywords_json TEXT NOT NULL,
          fields_json TEXT NOT NULL,
          score INTEGER NOT NULL,
          first_matched_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(article_id, project),
          FOREIGN KEY(article_id) REFERENCES articles(article_id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS summaries (
          article_id INTEGER PRIMARY KEY,
          summary_zh TEXT NOT NULL,
          project_relevance_json TEXT NOT NULL,
          suggested_action TEXT NOT NULL,
          confidence TEXT NOT NULL,
          limitations_zh TEXT NOT NULL,
          model TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(article_id) REFERENCES articles(article_id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS runs (
          run_id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at TEXT NOT NULL,
          finished_at TEXT,
          from_date TEXT NOT NULL,
          to_date TEXT NOT NULL,
          fetched_count INTEGER NOT NULL DEFAULT 0,
          changed_count INTEGER NOT NULL DEFAULT 0,
          matched_count INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          error_json TEXT NOT NULL DEFAULT '[]'
        );
        """
    )
    conn.commit()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def http_get(url: str, accept: str = "application/json, application/xml, text/xml, */*") -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    with urllib.request.urlopen(request, timeout=40) as response:
        return response.read()


def clean_text(value: Any) -> str:
    if value is None:
        return ""
    text = html.unescape(TAG_RE.sub(" ", str(value)))
    return re.sub(r"\s+", " ", text).strip()


def normalize_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    return re.sub(r"\s+", " ", value).strip()


def normalize_doi(value: str) -> str:
    value = clean_text(value)
    value = re.sub(r"^(?:https?://(?:dx\.)?doi\.org/|doi:\s*)", "", value, flags=re.I)
    match = DOI_RE.search(value)
    return match.group(0).rstrip(".,;)").lower() if match else ""


def canonical_key(record: dict[str, Any]) -> str:
    if record.get("doi"):
        return f"doi:{record['doi'].lower()}"
    if record.get("source_url"):
        return f"url:{record['source_url'].split('#', 1)[0]}"
    title = normalize_text(record["title"])
    return "title:" + hashlib.sha256(title.encode()).hexdigest()


def content_hash(record: dict[str, Any]) -> str:
    payload = json.dumps(
        {
            "title": record.get("title", ""),
            "authors": record.get("authors", []),
            "abstract": record.get("abstract", ""),
            "published_at": record.get("published_at", ""),
            "version": record.get("version", ""),
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def parse_date(value: str) -> str:
    value = clean_text(value)
    if not value:
        return ""
    try:
        parsed = email.utils.parsedate_to_datetime(value)
        return parsed.date().isoformat()
    except (TypeError, ValueError):
        pass
    match = re.search(r"\d{4}-\d{2}-\d{2}", value)
    return match.group(0) if match else value[:10]


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def child_values(node: ET.Element, names: set[str]) -> list[str]:
    values: list[str] = []
    for child in list(node):
        if local_name(child.tag) in names:
            value = "".join(child.itertext())
            if clean_text(value):
                values.append(clean_text(value))
    return values


def fetch_rss(source: dict[str, Any], from_date: date) -> list[dict[str, Any]]:
    root = ET.fromstring(http_get(source["url"], "application/rss+xml, application/xml, text/xml"))
    entries = [node for node in root.iter() if local_name(node.tag) in {"item", "entry"}]
    records: list[dict[str, Any]] = []
    for item in entries:
        titles = child_values(item, {"title"})
        if not titles:
            continue
        links = child_values(item, {"link"})
        if not links:
            for child in list(item):
                if local_name(child.tag) == "link" and child.attrib.get("href"):
                    links.append(child.attrib["href"])
        descriptions = child_values(item, {"description", "summary", "abstract", "encoded"})
        creators = child_values(item, {"creator", "author"})
        dates = child_values(item, {"date", "pubdate", "published", "updated"})
        identifiers = child_values(item, {"identifier", "doi"})
        published = parse_date(dates[0] if dates else "")
        if published:
            try:
                if date.fromisoformat(published) < from_date:
                    continue
            except ValueError:
                pass
        link = links[0] if links else ""
        doi = normalize_doi(" ".join(identifiers + links + descriptions))
        records.append(
            {
                "doi": doi,
                "title": titles[0],
                "authors": creators,
                "abstract": descriptions[0] if descriptions else "",
                "journal": source.get("journal", source["name"]),
                "source_id": source["id"],
                "source_url": link,
                "published_at": published,
                "version": "",
            }
        )
    return records


def fetch_biorxiv(source: dict[str, Any], from_date: date, to_date: date) -> list[dict[str, Any]]:
    server = source.get("server", "biorxiv")
    categories = source.get("categories") or [""]
    collected: dict[str, dict[str, Any]] = {}
    for category in categories:
        cursor = 0
        while True:
            base = f"https://api.biorxiv.org/details/{server}/{from_date.isoformat()}/{to_date.isoformat()}/{cursor}"
            url = base
            if category:
                url += "?" + urllib.parse.urlencode({"category": category})
            payload = json.loads(http_get(url))
            batch = payload.get("collection", [])
            for item in batch:
                doi = normalize_doi(item.get("doi", ""))
                key = doi or item.get("title", "")
                collected[key] = {
                    "doi": doi,
                    "title": clean_text(item.get("title", "")),
                    "authors": [a.strip() for a in item.get("authors", "").split(";") if a.strip()],
                    "abstract": clean_text(item.get("abstract", "")),
                    "journal": source.get("journal", source["name"]),
                    "source_id": source["id"],
                    "source_url": f"https://doi.org/{doi}" if doi else "",
                    "published_at": parse_date(item.get("date", "")),
                    "version": str(item.get("version", "")),
                }
            if not batch:
                break
            total = int((payload.get("messages") or [{}])[0].get("total", 0) or 0)
            cursor += len(batch)
            if len(batch) < 30 or (total and cursor >= total):
                break
            time.sleep(0.05)
    return list(collected.values())


def crossref_enrich(record: dict[str, Any], mailto: str) -> dict[str, Any]:
    if not record.get("doi") or record.get("abstract"):
        return record
    url = "https://api.crossref.org/works/" + urllib.parse.quote(record["doi"], safe="")
    if mailto:
        url += "?" + urllib.parse.urlencode({"mailto": mailto})
    try:
        message = json.loads(http_get(url)).get("message", {})
    except Exception:
        return record
    enriched = dict(record)
    enriched["abstract"] = clean_text(message.get("abstract", ""))
    if not enriched.get("authors"):
        enriched["authors"] = [
            " ".join(filter(None, [author.get("given", ""), author.get("family", "")]))
            for author in message.get("author", [])
        ]
    return enriched


def upsert_source(conn: sqlite3.Connection, source: dict[str, Any]) -> None:
    conn.execute(
        """INSERT INTO sources(source_id, name, source_type, config_json)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(source_id) DO UPDATE SET
             name=excluded.name, source_type=excluded.source_type, config_json=excluded.config_json""",
        (source["id"], source["name"], source["type"], json.dumps(source, ensure_ascii=False)),
    )


def upsert_article(conn: sqlite3.Connection, record: dict[str, Any]) -> tuple[int, bool]:
    now = utc_now()
    key = canonical_key(record)
    current = conn.execute("SELECT * FROM articles WHERE canonical_key = ?", (key,)).fetchone()
    if current:
        merged = dict(record)
        for field in ("doi", "title", "abstract", "journal", "source_url", "published_at", "version"):
            if not merged.get(field):
                merged[field] = current[field]
        if not merged.get("authors"):
            merged["authors"] = json.loads(current["authors_json"])
        new_hash = content_hash(merged)
        changed = new_hash != current["content_hash"]
        conn.execute(
            """UPDATE articles SET doi=?, title=?, authors_json=?, abstract=?, journal=?, source_id=?,
               source_url=?, published_at=?, version=?, content_hash=?, last_seen_at=? WHERE article_id=?""",
            (
                merged.get("doi", ""), merged["title"], json.dumps(merged.get("authors", []), ensure_ascii=False),
                merged.get("abstract", ""), merged.get("journal", ""), merged["source_id"],
                merged.get("source_url", ""), merged.get("published_at", ""), merged.get("version", ""),
                new_hash, now, current["article_id"],
            ),
        )
        if changed:
            conn.execute("DELETE FROM matches WHERE article_id=?", (current["article_id"],))
            conn.execute("DELETE FROM summaries WHERE article_id=?", (current["article_id"],))
            conn.execute(
                "UPDATE articles SET summary_status='not_matched', summary_attempts=0, summary_error='' WHERE article_id=?",
                (current["article_id"],),
            )
        return int(current["article_id"]), changed

    record_hash = content_hash(record)
    cursor = conn.execute(
        """INSERT INTO articles(canonical_key, doi, title, authors_json, abstract, journal, source_id,
           source_url, published_at, version, content_hash, first_seen_at, last_seen_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            key, record.get("doi", ""), record["title"], json.dumps(record.get("authors", []), ensure_ascii=False),
            record.get("abstract", ""), record.get("journal", ""), record["source_id"],
            record.get("source_url", ""), record.get("published_at", ""), record.get("version", ""),
            record_hash, now, now,
        ),
    )
    return int(cursor.lastrowid), True


def load_research_projects() -> dict[str, list[str]]:
    raw = require_env("USER_RESEARCH")
    value = json.loads(raw)
    if not isinstance(value, dict) or not all(isinstance(v, list) for v in value.values()):
        raise ValueError("USER_RESEARCH must map project names to keyword arrays")
    return {str(k): [str(item) for item in v if str(item).strip()] for k, v in value.items()}


def match_articles(conn: sqlite3.Connection) -> int:
    projects = load_research_projects()
    now = utc_now()
    matched_articles = 0
    for article in conn.execute("SELECT * FROM articles").fetchall():
        title = normalize_text(article["title"])
        abstract = normalize_text(article["abstract"])
        old = {
            row["project"]: (row["keywords_json"], row["fields_json"], row["score"])
            for row in conn.execute("SELECT * FROM matches WHERE article_id=?", (article["article_id"],))
        }
        new: dict[str, tuple[str, str, int]] = {}
        for project, keywords in projects.items():
            matched_keywords: list[str] = []
            fields: dict[str, list[str]] = {}
            score = 0
            for keyword in keywords:
                needle = normalize_text(keyword)
                locations: list[str] = []
                if needle and needle in title:
                    locations.append("title")
                    score += 3
                if needle and needle in abstract:
                    locations.append("abstract")
                    score += 1
                if locations:
                    matched_keywords.append(keyword)
                    fields[keyword] = locations
            if matched_keywords:
                new[project] = (
                    json.dumps(matched_keywords, ensure_ascii=False),
                    json.dumps(fields, ensure_ascii=False, sort_keys=True),
                    score,
                )

        if old != new:
            conn.execute("DELETE FROM matches WHERE article_id=?", (article["article_id"],))
            conn.execute("DELETE FROM summaries WHERE article_id=?", (article["article_id"],))
            for project, (keywords_json, fields_json, score) in new.items():
                conn.execute(
                    """INSERT INTO matches(article_id, project, keywords_json, fields_json, score, first_matched_at, updated_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (article["article_id"], project, keywords_json, fields_json, score, now, now),
                )
            status = "pending" if new else "not_matched"
            conn.execute(
                "UPDATE articles SET summary_status=?, summary_attempts=0, summary_error='' WHERE article_id=?",
                (status, article["article_id"]),
            )
        elif new and article["summary_status"] == "not_matched":
            conn.execute("UPDATE articles SET summary_status='pending' WHERE article_id=?", (article["article_id"],))
        if new:
            matched_articles += 1
    conn.commit()
    return matched_articles


def command_sync(args: argparse.Namespace) -> None:
    config = load_json(paths()["sources"])
    lookback = int(config.get("lookback_days", 10))
    to_date = date.fromisoformat(args.to_date) if args.to_date else date.today()
    from_date = date.fromisoformat(args.from_date) if args.from_date else to_date - timedelta(days=lookback - 1)
    conn = connect()
    init_db(conn)
    started = utc_now()
    run_id = conn.execute(
        "INSERT INTO runs(started_at, from_date, to_date, status) VALUES (?, ?, ?, 'running')",
        (started, from_date.isoformat(), to_date.isoformat()),
    ).lastrowid
    fetched = changed = 0
    errors: list[dict[str, str]] = []
    for source in config.get("sources", []):
        if not source.get("enabled", True):
            continue
        upsert_source(conn, source)
        try:
            if source["type"] == "rss":
                records = fetch_rss(source, from_date)
            elif source["type"] == "biorxiv":
                records = fetch_biorxiv(source, from_date, to_date)
            else:
                raise ValueError(f"Unsupported source type: {source['type']}")
            for record in records:
                if config.get("crossref_enrich"):
                    existing = None
                    if record.get("doi") and not record.get("abstract"):
                        existing = conn.execute(
                            "SELECT abstract, authors_json FROM articles WHERE canonical_key=?",
                            (f"doi:{record['doi'].lower()}",),
                        ).fetchone()
                    if existing and existing["abstract"]:
                        record["abstract"] = existing["abstract"]
                        if not record.get("authors"):
                            record["authors"] = json.loads(existing["authors_json"])
                    else:
                        record = crossref_enrich(record, config.get("crossref_mailto", ""))
                _, was_changed = upsert_article(conn, record)
                fetched += 1
                changed += int(was_changed)
            conn.execute(
                "UPDATE sources SET last_success_at=?, last_error='' WHERE source_id=?",
                (utc_now(), source["id"]),
            )
            conn.commit()
        except Exception as exc:
            errors.append({"source": source["id"], "error": str(exc)})
            conn.execute("UPDATE sources SET last_error=? WHERE source_id=?", (str(exc), source["id"]))
            conn.commit()
    matched = match_articles(conn)
    status = "complete" if not errors else "partial"
    conn.execute(
        """UPDATE runs SET finished_at=?, fetched_count=?, changed_count=?, matched_count=?, status=?, error_json=?
           WHERE run_id=?""",
        (utc_now(), fetched, changed, matched, status, json.dumps(errors, ensure_ascii=False), run_id),
    )
    conn.commit()
    print(json.dumps({"run_id": run_id, "from": str(from_date), "to": str(to_date), "fetched": fetched,
                      "changed": changed, "matched": matched, "errors": errors}, ensure_ascii=False))


def pending_records(conn: sqlite3.Connection, limit: int) -> list[dict[str, Any]]:
    max_attempts = int(os.environ.get("FOLLOWUP_SUMMARY_MAX_ATTEMPTS", "3"))
    rows = conn.execute(
        """SELECT * FROM articles WHERE summary_status='pending' AND summary_attempts < ?
           ORDER BY first_seen_at, article_id LIMIT ?""",
        (max_attempts, limit),
    ).fetchall()
    records: list[dict[str, Any]] = []
    for row in rows:
        matches = conn.execute(
            "SELECT project, keywords_json, fields_json, score FROM matches WHERE article_id=? ORDER BY project",
            (row["article_id"],),
        ).fetchall()
        records.append(
            {
                "article_id": row["article_id"],
                "title": row["title"],
                "authors": json.loads(row["authors_json"]),
                "abstract": row["abstract"],
                "journal": row["journal"],
                "published_at": row["published_at"],
                "doi": row["doi"],
                "source_url": row["source_url"],
                "evidence_level": "Abstract-only" if row["abstract"] else "Metadata-only",
                "matches": [
                    {"project": item["project"], "keywords": json.loads(item["keywords_json"]),
                     "fields": json.loads(item["fields_json"]), "score": item["score"]}
                    for item in matches
                ],
            }
        )
    return records


def command_pending(args: argparse.Namespace) -> None:
    conn = connect()
    init_db(conn)
    print(json.dumps(pending_records(conn, args.limit), ensure_ascii=False, indent=2))


def command_build_prompt(args: argparse.Namespace) -> None:
    records = load_json(Path(args.input))
    prompt = f"""You summarize newly discovered scientific papers for abstract-level triage.

Return JSON matching the supplied schema. Process every input article exactly once and preserve each article_id.
Use only the supplied metadata and abstract. Do not browse, use tools, or infer unstated methods or results.
Write summary_zh, every reason_zh, and limitations_zh in concise Chinese. Keep scientific terms in conventional English.
For project_relevance, include exactly the matched projects supplied for that article.
Choose read only when the abstract shows strong direct relevance to a matched project; otherwise choose watch.
Use low confidence for Metadata-only records. Mention missing or limited abstract evidence in limitations_zh.

Input articles:
{json.dumps(records, ensure_ascii=False, indent=2)}
"""
    Path(args.output).write_text(prompt, encoding="utf-8")


def command_mark_attempt(args: argparse.Namespace) -> None:
    records = load_json(Path(args.input))
    ids = [int(item["article_id"]) for item in records]
    conn = connect()
    init_db(conn)
    max_attempts = int(os.environ.get("FOLLOWUP_SUMMARY_MAX_ATTEMPTS", "3"))
    for article_id in ids:
        conn.execute(
            """UPDATE articles SET summary_attempts=summary_attempts+1,
               summary_status=CASE WHEN summary_attempts + 1 >= ? THEN 'failed' ELSE 'pending' END,
               summary_error=? WHERE article_id=? AND summary_status='pending'""",
            (max_attempts, args.error or "Summary attempt failed", article_id),
        )
    conn.commit()


def command_import(args: argparse.Namespace) -> None:
    payload = load_json(Path(args.input))
    summaries = payload.get("summaries", [])
    conn = connect()
    init_db(conn)
    imported = 0
    model = os.environ.get("FOLLOWUP_CODEX_MODEL", os.environ.get("CODEX_EXEC_MODEL", ""))
    for item in summaries:
        article_id = int(item["article_id"])
        valid = conn.execute(
            "SELECT 1 FROM articles WHERE article_id=? AND summary_status='pending'", (article_id,)
        ).fetchone()
        if not valid:
            continue
        expected = {
            row["project"] for row in conn.execute("SELECT project FROM matches WHERE article_id=?", (article_id,))
        }
        received = {entry["project"] for entry in item["project_relevance"]}
        if expected != received:
            conn.execute(
                "UPDATE articles SET summary_error=? WHERE article_id=?",
                (f"Project mismatch: expected {sorted(expected)}, received {sorted(received)}", article_id),
            )
            continue
        now = utc_now()
        conn.execute(
            """INSERT INTO summaries(article_id, summary_zh, project_relevance_json, suggested_action,
               confidence, limitations_zh, model, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(article_id) DO UPDATE SET summary_zh=excluded.summary_zh,
                 project_relevance_json=excluded.project_relevance_json,
                 suggested_action=excluded.suggested_action, confidence=excluded.confidence,
                 limitations_zh=excluded.limitations_zh, model=excluded.model, updated_at=excluded.updated_at""",
            (article_id, item["summary_zh"], json.dumps(item["project_relevance"], ensure_ascii=False),
             item["suggested_action"], item["confidence"], item["limitations_zh"], model, now, now),
        )
        conn.execute(
            "UPDATE articles SET summary_status='complete', summary_error='' WHERE article_id=?", (article_id,)
        )
        imported += 1
    conn.commit()
    print(json.dumps({"imported": imported}, ensure_ascii=False))


def command_retry_failed(_: argparse.Namespace) -> None:
    conn = connect()
    init_db(conn)
    cursor = conn.execute(
        "UPDATE articles SET summary_status='pending', summary_attempts=0, summary_error='' WHERE summary_status='failed'"
    )
    conn.commit()
    print(json.dumps({"reset": cursor.rowcount}))


def safe_filename(value: str) -> str:
    value = re.sub(r"[\\/:*?\"<>|]", "-", value).strip(" .")
    return value or "Unnamed"


def iso_week(timestamp: str) -> str:
    day = date.fromisoformat(timestamp[:10])
    year, week, _ = day.isocalendar()
    return f"{year}-W{week:02d}"


def markdown_article(article: sqlite3.Row, matches: list[sqlite3.Row], summary: sqlite3.Row | None,
                     project_filter: str | None = None) -> str:
    url = f"https://doi.org/{article['doi']}" if article["doi"] else article["source_url"]
    title = article["title"].replace("[", "\\[").replace("]", "\\]")
    heading = f"## [{title}]({url})" if url else f"## {title}"
    authors = json.loads(article["authors_json"])
    author_text = "; ".join(authors[:8]) + ("; et al." if len(authors) > 8 else "")
    selected = [row for row in matches if project_filter is None or row["project"] == project_filter]
    projects = ", ".join(row["project"] for row in selected)
    keywords = sorted({kw for row in selected for kw in json.loads(row["keywords_json"])})
    lines = [heading, "", f"- **Journal / source:** {article['journal']}",
             f"- **Published:** {article['published_at'] or '未说明'}",
             f"- **Authors:** {author_text or '未说明'}", f"- **Matched projects:** {projects}",
             f"- **Matched keywords:** {', '.join(keywords)}"]
    if article["doi"]:
        lines.append(f"- **DOI:** https://doi.org/{article['doi']}")
    evidence = "Abstract-only" if article["abstract"] else "Metadata-only"
    lines.append(f"- **Evidence level:** {evidence}")
    if summary:
        relevance = {item["project"]: item["reason_zh"] for item in json.loads(summary["project_relevance_json"])}
        lines.extend(["", f"**Summary:** {summary['summary_zh']}", ""])
        for project in [row["project"] for row in selected]:
            lines.append(f"**{project}:** {relevance.get(project, '未说明')}")
            lines.append("")
        lines.extend([f"**Suggested action:** {summary['suggested_action']}", "",
                      f"**Confidence:** {summary['confidence']}", "",
                      f"**Limitations:** {summary['limitations_zh']}"])
    else:
        lines.extend(["", "**Summary status:** Pending"])
    return "\n".join(lines).rstrip() + "\n"


def render_pages(conn: sqlite3.Connection) -> dict[str, int]:
    p = paths()
    for directory in (p["output"], p["weekly"], p["projects"]):
        directory.mkdir(parents=True, exist_ok=True)
    articles = conn.execute(
        """SELECT DISTINCT a.* FROM articles a JOIN matches m ON m.article_id=a.article_id
           ORDER BY a.first_seen_at DESC, a.article_id DESC"""
    ).fetchall()
    grouped_weeks: dict[str, list[sqlite3.Row]] = {}
    grouped_projects: dict[str, list[sqlite3.Row]] = {}
    for article in articles:
        matches = conn.execute("SELECT * FROM matches WHERE article_id=? ORDER BY project", (article["article_id"],)).fetchall()
        first_match = min(row["first_matched_at"] for row in matches)
        grouped_weeks.setdefault(iso_week(first_match), []).append(article)
        for row in matches:
            grouped_projects.setdefault(row["project"], []).append(article)

    template = p["template"].read_text(encoding="utf-8")
    for week, week_articles in grouped_weeks.items():
        blocks = []
        for article in week_articles:
            matches = conn.execute("SELECT * FROM matches WHERE article_id=? ORDER BY project", (article["article_id"],)).fetchall()
            summary = conn.execute("SELECT * FROM summaries WHERE article_id=?", (article["article_id"],)).fetchone()
            blocks.append(markdown_article(article, matches, summary))
        content = template.replace("{{ISO_WEEK}}", week).replace("{{CONTENT}}", "\n".join(blocks))
        (p["weekly"] / f"{week}.md").write_text(content, encoding="utf-8")

    for project, project_articles in grouped_projects.items():
        blocks = [f"# Literature Follow-up - {project}", "",
                  "> Automatically generated from literal title/abstract matches.", ""]
        for article in project_articles:
            matches = conn.execute("SELECT * FROM matches WHERE article_id=? ORDER BY project", (article["article_id"],)).fetchall()
            summary = conn.execute("SELECT * FROM summaries WHERE article_id=?", (article["article_id"],)).fetchone()
            blocks.append(markdown_article(article, matches, summary, project))
        (p["projects"] / f"{safe_filename(project)}.md").write_text("\n".join(blocks), encoding="utf-8")

    latest = conn.execute("SELECT * FROM runs ORDER BY run_id DESC LIMIT 1").fetchone()
    complete = conn.execute("SELECT COUNT(*) FROM articles WHERE summary_status='complete'").fetchone()[0]
    pending = conn.execute("SELECT COUNT(*) FROM articles WHERE summary_status='pending'").fetchone()[0]
    index = ["# Literature Follow-up", "", "> LENS 自动生成的标题与摘要级文献追踪入口。", "",
             "## Status", "", f"- **Matched articles:** {len(articles)}",
             f"- **Summaries complete:** {complete}", f"- **Summaries pending:** {pending}"]
    if latest:
        index.extend([f"- **Last run:** {latest['finished_at'] or latest['started_at']}",
                      f"- **Last run status:** {latest['status']}"])
    index.extend(["", "## Weekly", ""])
    for week in sorted(grouped_weeks, reverse=True):
        index.append(f"- [[Weekly/{week}|{week}]]")
    index.extend(["", "## Projects", ""])
    for project in sorted(grouped_projects):
        index.append(f"- [[Projects/{safe_filename(project)}|{project}]]")
    (p["output"] / "index.md").write_text("\n".join(index).rstrip() + "\n", encoding="utf-8")
    return {"articles": len(articles), "weeks": len(grouped_weeks), "projects": len(grouped_projects)}


def command_render(_: argparse.Namespace) -> None:
    conn = connect()
    init_db(conn)
    print(json.dumps(render_pages(conn), ensure_ascii=False))


def command_status(_: argparse.Namespace) -> None:
    conn = connect()
    init_db(conn)
    statuses = {row["summary_status"]: row["count"] for row in conn.execute(
        "SELECT summary_status, COUNT(*) AS count FROM articles GROUP BY summary_status"
    )}
    latest = conn.execute("SELECT * FROM runs ORDER BY run_id DESC LIMIT 1").fetchone()
    result = {"database": str(paths()["db"]), "articles": sum(statuses.values()), "statuses": statuses,
              "latest_run": dict(latest) if latest else None}
    print(json.dumps(result, ensure_ascii=False, indent=2))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init").set_defaults(func=lambda _: (lambda c: (init_db(c), print(paths()["db"])))(connect()))
    sync = sub.add_parser("sync")
    sync.add_argument("--from-date")
    sync.add_argument("--to-date")
    sync.set_defaults(func=command_sync)
    pending = sub.add_parser("pending")
    pending.add_argument("--limit", type=int, default=8)
    pending.set_defaults(func=command_pending)
    prompt = sub.add_parser("build-prompt")
    prompt.add_argument("--input", required=True)
    prompt.add_argument("--output", required=True)
    prompt.set_defaults(func=command_build_prompt)
    attempt = sub.add_parser("mark-attempt")
    attempt.add_argument("--input", required=True)
    attempt.add_argument("--error", default="")
    attempt.set_defaults(func=command_mark_attempt)
    importer = sub.add_parser("import-summaries")
    importer.add_argument("--input", required=True)
    importer.set_defaults(func=command_import)
    sub.add_parser("retry-failed").set_defaults(func=command_retry_failed)
    sub.add_parser("render").set_defaults(func=command_render)
    sub.add_parser("status").set_defaults(func=command_status)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
