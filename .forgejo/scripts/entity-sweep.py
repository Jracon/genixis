#!/usr/bin/env python3
"""The entity text sweep of the forge (issue 392).

The sweep reads the bodies, the comments, and the review comments of the
issues and the pull requests of this repository, and it reports defect
classes of the entity text. It edits, closes, and opens no entity. The
findings never fail a run; a transport fault fails it.

Modes:

- brief: the class 4 gate check. The pull request event payload carries
  the body, so this mode reads the event file alone and needs no API call
  and no secret. The dispatcher reads the same payload shape
  (modules/services/dispatcher/dispatcher.py, the linked_issue read).
- report: the classes 1 to 3 sweep. This mode reads the forge through its
  API with the ENTITY_SWEEP_TOKEN secret, prints the report to the run
  log, and posts one comment on the issue that SWEEP_TRACKER names, the
  standing report home. A manual dispatch names another home through the
  tracker input of the workflow, and the dry run of issue 392 posts on
  that issue itself.
- selftest: the offline fixture proof of both modes. No network and no
  secret. The gate runs this mode as the entity-sweep-fixture check
  (lib/checks.nix).
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path
from typing import TypedDict

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TEMPLATE_PATH = REPO_ROOT / ".forgejo" / "PULL_REQUEST_TEMPLATE.md"

# class 4 binds to the pull request bodies created after the date of the
# one-shot audit of the entity text (issue 218): earlier bodies keep their
# historical shape
BRIEF_CUTOFF = "2026-11-09"

# the forge caps one page at 50 rows, so the sweep pages through the corpus,
# and a page cap stops a broken pagination loop
PAGE_LIMIT = 50
PAGE_CAP = 40

HEADING = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
ENTITY_REF = re.compile(
    r"#(\d+)\b|\bissues?\s+(\d+)\b|\bpulls?\s+(\d+)\b", re.IGNORECASE
)

# class 1, tool note without a home: each pattern captures the tool token of
# one sentence that states a missing, unavailable, or rejected tool. The
# patterns are the seed set: the dry run report lets the owner tune them
TOOL_NOTE_PATTERNS = [
    re.compile(r"\b([A-Za-z][\w.-]*)\s+is\s+(?:missing|absent|unavailable)\b"),
    re.compile(
        r"\bno\s+([A-Za-z][\w.-]*)\s+(?:in|on)\s+(?:the\s+)?"
        r"(?:PATH|environment|devShell|runner|machine|host|sandbox)\b"
    ),
    re.compile(
        r"\b([A-Za-z][\w.-]*)\s+is\s+not\s+(?:on|in)\s+(?:the\s+)?"
        r"(?:PATH|environment)\b"
    ),
    re.compile(r"\bmissing\s+(?:tool|binary|command|package):\s*([A-Za-z][\w.-]*)"),
    re.compile(
        r"\bthe\s+(?:runner|environment|machine|host|session|sandbox)\s+lacks?\s+"
        r"([A-Za-z][\w.-]*)"
    ),
    re.compile(r"\b([A-Za-z][\w.-]*)\s+is\s+not\s+(?:installed|available)\b"),
]

# words that a class 1 pattern can capture in a sentence that states no tool
TOOL_STOP_WORDS = {
    "anything",
    "body",
    "change",
    "comment",
    "commit",
    "diff",
    "evidence",
    "file",
    "finding",
    "gate",
    "hook",
    "input",
    "issue",
    "it",
    "line",
    "list",
    "name",
    "none",
    "nothing",
    "number",
    "one",
    "output",
    "path",
    "pull",
    "record",
    "report",
    "review",
    "row",
    "run",
    "script",
    "section",
    "session",
    "state",
    "task",
    "template",
    "test",
    "text",
    "this",
    "tool",
    "value",
    "word",
    "work",
}

# class 2, stale reference: a sentence that claims an open state for an
# entity that the forge holds as closed
OPEN_STATE_PATTERNS = [
    re.compile(
        r"\b(?:is|are|was|were|stays?|remains?|keeps?|stands?)\s+(?:wide\s+)?open\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\bopen\s+(?:record|tracker|issue|pull\s+request|entity)\b", re.IGNORECASE
    ),
]

# class 3, decision without a record: a comment that states a decision. The
# home check reads the register alone: a record under docs/adr/ or a line of
# docs/decisions.md must name the entity, because the records cite their
# issues
DECISION_MARKERS = [
    re.compile(r"\bruling of the owner\b", re.IGNORECASE),
    re.compile(r"\bthe owner\s+(?:rules|ruled|decides|decided)\b", re.IGNORECASE),
    re.compile(r"\bdecision\s+D\d+\b"),
    re.compile(r"\bwe\s+(?:decide|decided|rule|ruled)\b", re.IGNORECASE),
]

COMMENT_KINDS = ("comment", "review", "review comment")


class Unit(TypedDict):
    """One text unit of the corpus: a body, a comment, or a review comment."""

    entity: int
    kind: str
    text: str


class Entity(TypedDict):
    """The corpus fields of one entity that the sweep reads."""

    is_pr: bool
    state: str
    title: str


def sentences(text):
    """Each sentence of one text, one per line piece, in order."""
    for line in (text or "").splitlines():
        for sentence in SENTENCE_SPLIT.split(line.strip()):
            sentence = sentence.strip()
            if sentence:
                yield sentence


def entity_refs(sentence):
    """Each entity index that one sentence names, as a set."""
    refs = set()
    for match in ENTITY_REF.finditer(sentence):
        for group in match.groups():
            if group and group.isdigit():
                refs.add(int(group))
    return refs


def template_sections(path):
    """The section titles of the pull request template, in order."""
    if not path.is_file():
        raise SystemExit(f"brief check: no pull request template at {path}")
    return HEADING.findall(path.read_text())


def missing_sections(body, sections):
    """The template sections that one pull request body misses."""
    present = {title.strip() for title in HEADING.findall(body or "")}
    return [section for section in sections if section not in present]


def brief_applies(created_at):
    """True when the brief check binds: the body was created after the
    cutoff, or the payload names no creation date."""
    day = str(created_at or "")[:10]
    return not day or day > BRIEF_CUTOFF


def tool_named_in(tool, text):
    """True when the text names the tool as one word. The match keeps the
    case, because a tool name is case-bound and a lowercase common word
    must not home a tool."""
    return bool(re.search(rf"\b{re.escape(tool)}\b", text or ""))


def scan_tool_notes(units, home_text, open_text):
    """Class 1: each unit that states a missing tool with no home. A home is
    a documentation file of the checkout or the text of an open entity."""
    findings = []
    seen = set()
    for unit in units:
        for sentence in sentences(unit["text"]):
            tool = None
            for pattern in TOOL_NOTE_PATTERNS:
                match = pattern.search(sentence)
                if match:
                    tool = match.group(1).rstrip(".,;:()[]")
                    break
            if not tool or tool.lower() in TOOL_STOP_WORDS:
                continue
            if tool_named_in(tool, home_text) or tool_named_in(tool, open_text):
                continue
            key = (unit["entity"], tool)
            if key not in seen:
                seen.add(key)
                findings.append((unit, tool))
    return findings


def scan_stale_references(units, entities):
    """Class 2: each unit that claims an open state for a closed entity."""
    findings = []
    seen = set()
    for unit in units:
        for sentence in sentences(unit["text"]):
            if not any(pattern.search(sentence) for pattern in OPEN_STATE_PATTERNS):
                continue
            for ref in entity_refs(sentence):
                entry = entities.get(ref)
                if entry and entry["state"] == "closed":
                    key = (unit["entity"], ref)
                    if key not in seen:
                        seen.add(key)
                        findings.append((unit, ref))
    return findings


def scan_unrecorded_decisions(units, register_text):
    """Class 3: each comment that states a decision with no register record
    for its entity. Bodies sit outside the class, because the class reads
    comments."""
    findings = []
    seen = set()
    for unit in units:
        if unit["kind"] not in COMMENT_KINDS:
            continue
        marked = any(
            pattern.search(sentence)
            for sentence in sentences(unit["text"])
            for pattern in DECISION_MARKERS
        )
        if not marked:
            continue
        entity = unit["entity"]
        if re.search(rf"(?:#\s*|issues?\s+){entity}\b", register_text or ""):
            continue
        if entity not in seen:
            seen.add(entity)
            findings.append(unit)
    return findings


def entity_word(index, entities):
    """The report word of one entity index: pull request or issue."""
    entry = entities.get(index)
    if entry and entry["is_pr"]:
        return f"pull request #{index}"
    return f"issue #{index}"


def kind_word(kind):
    """The report word of one unit kind."""
    return {
        "body": "The body",
        "comment": "A comment",
        "review": "A review",
        "review comment": "A review comment",
    }[kind]


def tool_line(unit, tool, entities):
    """One class 1 finding. The sentence stays clear of the seed patterns,
    so a report comment feeds no finding into the next run."""
    return (
        f"{entity_word(unit['entity'], entities)}: {kind_word(unit['kind'])} "
        f"names the tool {tool} as missing, and neither a documentation "
        f"file nor a tracker names it."
    )


def stale_line(unit, ref, entities):
    """One class 2 finding, in the same clear shape."""
    return (
        f"{entity_word(unit['entity'], entities)}: {kind_word(unit['kind'])} "
        f"states {entity_word(ref, entities)} as open, and that entity "
        f"is closed."
    )


def decision_line(unit, entities):
    """One class 3 finding, in the same clear shape."""
    return (
        f"{entity_word(unit['entity'], entities)}: {kind_word(unit['kind'])} "
        f"states a decision, and no register record names this entity."
    )


def render_report(counts, tools, stale, decisions, entities):
    """The report comment of one run. The finding lines and the footer stay
    clear of the seed patterns, and the selftest proves this on the
    rendered text."""
    stamp = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        f"Entity sweep report, {stamp}.",
        "",
        f"Corpus: {counts['entities']} entities ({counts['issues']} issues, "
        f"{counts['pulls']} pull requests), {counts['comments']} comments, "
        f"{counts['review comments']} review comments.",
        "",
        f"Class 1, tool note without a home: {len(tools)} findings.",
    ]
    lines += [f"- {tool_line(unit, tool, entities)}" for unit, tool in tools]
    lines += ["", f"Class 2, stale reference: {len(stale)} findings."]
    lines += [f"- {stale_line(unit, ref, entities)}" for unit, ref in stale]
    lines += ["", f"Class 3, decision without a record: {len(decisions)} findings."]
    lines += [f"- {decision_line(unit, entities)}" for unit in decisions]
    lines += [
        "",
        "The ruling on each class, keep, tune, or drop, stays with the owner "
        "on issue 392. A class that proves stable and high-signal graduates "
        "under one owner ruling.",
    ]
    return "\n".join(lines)


def api_request(url, token, payload=None):
    """One API call with the sweep token. A transport fault stops the run,
    because a report over a partial corpus would lie about the corpus."""
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    request.add_header("Authorization", f"token {token}")
    if data:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as answer:
            body = answer.read().decode()
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:500]
        raise SystemExit(
            f"the forge API answered {err.code} on {url}: {detail}"
        ) from err
    except urllib.error.URLError as err:
        raise SystemExit(
            f"the forge API could not be reached at {url}: {err.reason}"
        ) from err
    return json.loads(body) if body else None


def fetch_pages(api, token, path, params=None):
    """Each row of one list endpoint, paged until the forge sends a short
    page."""
    rows = []
    page = 1
    while page <= PAGE_CAP:
        query = dict(params or {}, limit=PAGE_LIMIT, page=page)
        batch = api_request(f"{api}{path}?{urllib.parse.urlencode(query)}", token)
        if not isinstance(batch, list) or not batch:
            break
        rows.extend(batch)
        if len(batch) < PAGE_LIMIT:
            break
        page += 1
    return rows


def add_unit(units, entity, kind, text):
    """One text unit of the corpus, when the text holds anything."""
    if text and text.strip():
        units.append({"entity": entity, "kind": kind, "text": text})


def fetch_corpus(api, token, repo):
    """The whole entity corpus: each entity with its state, its text units,
    and the counts of the report header."""
    entities: dict[int, Entity] = {}
    units: list[Unit] = []
    counts = {
        "entities": 0,
        "issues": 0,
        "pulls": 0,
        "comments": 0,
        "review comments": 0,
    }
    for entry in fetch_pages(api, token, f"/repos/{repo}/issues", {"state": "all"}):
        index = entry.get("number")
        if index is None:
            continue
        is_pr = "pull_request" in entry
        entities[index] = {
            "is_pr": is_pr,
            "state": entry.get("state") or "open",
            "title": entry.get("title") or "",
        }
        counts["entities"] += 1
        counts["pulls" if is_pr else "issues"] += 1
        add_unit(units, index, "body", entry.get("body"))
        comments = fetch_pages(api, token, f"/repos/{repo}/issues/{index}/comments")
        counts["comments"] += len(comments)
        for comment in comments:
            add_unit(units, index, "comment", comment.get("body"))
        if is_pr:
            reviews = fetch_pages(api, token, f"/repos/{repo}/pulls/{index}/reviews")
            counts["review comments"] += len(reviews)
            for review in reviews:
                add_unit(units, index, "review", review.get("body"))
            inline = fetch_pages(api, token, f"/repos/{repo}/pulls/{index}/comments")
            counts["review comments"] += len(inline)
            for note in inline:
                add_unit(units, index, "review comment", note.get("body"))
    return entities, units, counts


def read_home_texts():
    """The class 1 home text of the checkout documentation and the class 3
    register text. The homes read the checkout, so a scheduled run reads the
    default branch."""
    home_files = [REPO_ROOT / "AGENTS.md", *sorted((REPO_ROOT / "docs").rglob("*.md"))]
    home_text = "\n".join(path.read_text(errors="replace") for path in home_files)
    register_files = sorted((REPO_ROOT / "docs" / "adr").glob("*.md"))
    register_parts = [
        (REPO_ROOT / "docs" / "decisions.md").read_text(errors="replace"),
        *(path.read_text(errors="replace") for path in register_files),
    ]
    return home_text, "\n".join(register_parts)


def open_entity_text(entities, units):
    """The text of the open entities, titles included: an open tracker is a
    home of a tool note."""
    open_indexes = {
        index for index, entry in entities.items() if entry["state"] == "open"
    }
    parts = [
        entry["title"] for index, entry in entities.items() if index in open_indexes
    ]
    parts += [unit["text"] for unit in units if unit["entity"] in open_indexes]
    return "\n".join(parts)


def brief_mode():
    """The class 4 gate check over the pull request event file."""
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if os.environ.get("GITHUB_EVENT_NAME") != "pull_request" or not event_path:
        print("brief check: no pull request event, nothing to check")
        return 0
    payload = json.loads(Path(event_path).read_text())
    pull = payload.get("pull_request") or {}
    number = payload.get("number") or pull.get("number") or "?"
    created = str(pull.get("created_at") or "")
    if not brief_applies(created):
        print(
            f"pull request {number}: created {created[:10]}, on or before "
            f"{BRIEF_CUTOFF}; the brief check skips it"
        )
        return 0
    missing = missing_sections(pull.get("body"), template_sections(TEMPLATE_PATH))
    for title in missing:
        print(f"pull request {number}: The body misses the template section '{title}'.")
    if missing:
        return 1
    print(f"pull request {number}: The body holds each template section.")
    return 0


def report_mode():
    """The classes 1 to 3 sweep over the forge API, with the report comment
    on the tracker issue."""
    token = os.environ.get("ENTITY_SWEEP_TOKEN", "")
    if not token:
        raise SystemExit(
            "report mode needs the ENTITY_SWEEP_TOKEN secret: the owner creates "
            "the dedicated login and states the scope on issue 392 (criterion 5)"
        )
    tracker = os.environ.get("SWEEP_TRACKER", "")
    if not tracker.isdigit():
        raise SystemExit(
            "report mode needs SWEEP_TRACKER, the issue number of the report home"
        )
    server = os.environ.get("GITHUB_SERVER_URL", "https://forgejo.local.jracon.xyz")
    api = f"{server.rstrip('/')}/api/v1"
    repo = os.environ.get("GITHUB_REPOSITORY", "jracon/genixis")
    entities, units, counts = fetch_corpus(api, token, repo)
    home_text, register_text = read_home_texts()
    tools = scan_tool_notes(units, home_text, open_entity_text(entities, units))
    stale = scan_stale_references(units, entities)
    decisions = scan_unrecorded_decisions(units, register_text)
    report = render_report(counts, tools, stale, decisions, entities)
    print(report)
    api_request(
        f"{api}/repos/{repo}/issues/{tracker}/comments", token, {"body": report}
    )
    print(f"report comment posted on issue {tracker}")
    return 0


def expect(actual, wanted, label, ok):
    """One fixture assertion: it prints the pass line or the failure."""
    if actual == wanted:
        print(f"pass: {label}")
        return ok
    print(f"FAIL {label}: got {actual!r}, wanted {wanted!r}")
    return False


def selftest():
    """The offline fixture proof. The brief fixtures bind to the template of
    the checkout, the class fixtures seed one defect and one control each,
    and the rendered report feeds back through the detectors, so a report
    comment of one run adds no finding to the next run."""
    ok = True
    sections = template_sections(TEMPLATE_PATH)
    ok = expect(bool(sections), True, "the template holds sections", ok)

    full_body = "\n".join(f"## {section}\n\ncontent" for section in sections)
    ok = expect(
        missing_sections(full_body, sections), [], "a conforming body passes", ok
    )
    skipped = ("Machine decisions", "Spine files")
    short_body = "\n".join(
        f"## {section}" for section in sections if section not in skipped
    )
    ok = expect(
        missing_sections(short_body, sections),
        list(skipped),
        "a body with two sections missing names both",
        ok,
    )
    ok = expect(
        missing_sections("", sections),
        sections,
        "an empty body misses every section",
        ok,
    )
    ok = expect(
        brief_applies("2026-11-09T10:00:00Z"), False, "the cutoff day stays exempt", ok
    )
    ok = expect(
        brief_applies("2026-11-10T00:00:00Z"),
        True,
        "the day after the cutoff binds",
        ok,
    )
    ok = expect(brief_applies(""), True, "a missing creation date binds", ok)

    units: list[Unit] = [
        {
            "entity": 10,
            "kind": "comment",
            "text": "The leg stopped: python3 is missing on this host.",
        },
        {
            "entity": 10,
            "kind": "comment",
            "text": "trivy is not installed in the devShell.",
        },
        {
            "entity": 10,
            "kind": "comment",
            "text": "the sandbox lacks gcc for the cgo build",
        },
        {
            "entity": 10,
            "kind": "comment",
            "text": "The output is missing from the log.",
        },
        {
            "entity": 11,
            "kind": "body",
            "text": "Issue 74 stays open as the record of the original plan.",
        },
        {
            "entity": 11,
            "kind": "body",
            "text": "Issue 90 stays open as the tracker of the tool notes.",
        },
        {
            "entity": 11,
            "kind": "body",
            "text": "Issue 74 closed the plan of the campaign.",
        },
        {
            "entity": 20,
            "kind": "comment",
            "text": "Ruling of the owner, 2026-11-15: the weekly cadence.",
        },
        {
            "entity": 21,
            "kind": "comment",
            "text": "The owner ruled: the register keeps the record.",
        },
        {
            "entity": 22,
            "kind": "body",
            "text": "Decision D8 of issue 350: the posture rule.",
        },
    ]
    entities: dict[int, Entity] = {
        10: {"is_pr": False, "state": "open", "title": ""},
        11: {"is_pr": False, "state": "open", "title": ""},
        20: {"is_pr": False, "state": "open", "title": ""},
        21: {"is_pr": False, "state": "open", "title": ""},
        22: {"is_pr": False, "state": "open", "title": ""},
        74: {"is_pr": False, "state": "closed", "title": ""},
        90: {"is_pr": True, "state": "open", "title": ""},
    }
    home_text = "The scan step of the reports job runs trivy over the pinned images.\n"
    open_text = "issue 90: add gcc to the devShell of the runner\n"
    register_text = "The record of the register cites issue 21 for its origin.\n"

    tools = scan_tool_notes(units, home_text, open_text)
    ok = expect(
        [(unit["entity"], tool) for unit, tool in tools],
        [(10, "python3")],
        "class 1 names the homeless tool note alone",
        ok,
    )
    stale = scan_stale_references(units, entities)
    ok = expect(
        [(unit["entity"], ref) for unit, ref in stale],
        [(11, 74)],
        "class 2 names the open claim on the closed entity alone",
        ok,
    )
    decisions = scan_unrecorded_decisions(units, register_text)
    ok = expect(
        [unit["entity"] for unit in decisions],
        [20],
        "class 3 names the decision with no record alone",
        ok,
    )

    counts = {
        "entities": 7,
        "issues": 6,
        "pulls": 1,
        "comments": 4,
        "review comments": 0,
    }
    report = render_report(counts, tools, stale, decisions, entities)
    report_unit: Unit = {"entity": 572, "kind": "comment", "text": report}
    corpus_units = units + [report_unit]
    report_tools = scan_tool_notes(corpus_units, home_text, open_text)
    report_stale = scan_stale_references(corpus_units, entities)
    report_decisions = scan_unrecorded_decisions(corpus_units, register_text)
    flagged = [unit for unit, _ in report_tools]
    flagged += [unit for unit, _ in report_stale]
    flagged += report_decisions
    ok = expect(
        [unit for unit in flagged if unit is report_unit],
        [],
        "the rendered report feeds no finding into the next run",
        ok,
    )
    return 0 if ok else 1


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "brief":
        return brief_mode()
    if mode == "report":
        return report_mode()
    if mode == "selftest":
        return selftest()
    print(__doc__)
    print("usage: entity-sweep.py brief | report | selftest", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
