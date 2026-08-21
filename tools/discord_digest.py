#!/usr/bin/env python3
"""Collect merged PRs and post Discord digest/release payloads."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from discord_webhook import (
    build_digest_payload,
    build_release_payload,
    load_article,
    post_webhook,
)

EASTERN = ZoneInfo("America/New_York")
GITHUB_API = "https://api.github.com"
_ARTICLE_RULES = (
    "You are a correspondent for The Wand Street Journal — a serious newspaper for "
    "magical wizards covering the FriendSlop codebase as if it were an enchanted market. "
    "Tone: dry, specific, slightly wry, and whimsical without tipping into parody. "
    "Take the subject seriously the way a real paper would.\n\n"
    "Write a newspaper article, not a changelog. Aggregate related changes into a few "
    "thematic sections (for example Combat, Spells, Tooling). Do not emit a markdown "
    "bullet list of pull requests. Do not walk PR-by-PR unless a single PR is the whole "
    "story. You may mention a PR number inline once if it helps, but the story is the "
    "substance of the changes.\n\n"
    "Use only facts from the source material. Do not invent features, metrics, market "
    "moves, or spells that are not in the source.\n\n"
    "Hard bans — never include any of these:\n"
    "- GitHub authors, usernames, or committers\n"
    "- Cursor, Copilot, or other AI/tooling attribution\n"
    "- Fake finance (bids, spreads, market stability, undisclosed metrics)\n"
    "- Meta commentary about the briefing itself\n\n"
    "Return JSON only with this shape:\n"
    '{"lede":"1-2 sentence opening dek","sections":[{"title":"Section head","body":"1-3 short paragraphs"}]}\n'
    "Use 2-5 sections when the source supports it. Keep titles short. Keep each body "
    "under 900 characters. Plain prose only inside strings — no markdown headings or "
    "bullet lists. Do not wrap the JSON in code fences."
)
VOICE_PROMPT = (
    _ARTICLE_RULES
    + "\nThis is the daily closing edition covering pull requests merged into FriendSlop "
    "in the last day."
)
SPECIAL_EDITION_PROMPT = (
    _ARTICLE_RULES
    + "\nThis is an off-schedule Special Edition covering a newly published FriendSlop "
    "GitHub release. Mention the release name and tag in the lede."
)


def now_eastern(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(EASTERN)
    if now.tzinfo is None:
        return now.replace(tzinfo=EASTERN)
    return now.astimezone(EASTERN)


def scheduled_cron_matches_eastern(
    cron: str, now: datetime | None = None
) -> bool:
    """Pick the UTC cron that is 3:45pm America/New_York for today's DST."""
    stamp = now_eastern(now)
    offset = stamp.utcoffset()
    if offset is None:
        return False
    offset_hours = int(offset.total_seconds() // 3600)
    expression = cron.strip()
    if offset_hours == -4:
        return expression == "45 19 * * *"
    if offset_hours == -5:
        return expression == "45 20 * * *"
    return False


def digest_window(now: datetime | None = None) -> tuple[datetime, datetime]:
    end = now_eastern(now)
    return end - timedelta(hours=24), end


def format_briefing(prs: list[dict], *, since: datetime, until: datetime) -> str:
    lines = [
        f"Window (America/New_York): {since.isoformat()} to {until.isoformat()}",
        f"Merged PR count: {len(prs)}",
        "",
        "Summarize the substance of these changes for readers. Group related work.",
        "Ignore authors and tooling attribution.",
        "",
    ]
    for pr in prs:
        lines.append(f"#{pr['number']} {pr['title']}")
        lines.append(f"Merged: {pr['merged_at']}")
        lines.append(f"URL: {pr['url']}")
        body = (pr.get("body") or "").strip() or "(no description)"
        lines.append("Description:")
        lines.append(body)
        lines.append("")
    return "\n".join(lines).strip() + "\n"


def _github_headers() -> dict[str, str]:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "friend-slop-discord-digest",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _github_get(url: str) -> dict | list:
    request = urllib.request.Request(url, headers=_github_headers(), method="GET")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GitHub API failed ({exc.code}): {detail}") from exc


def fetch_merged_prs(
    repo: str,
    *,
    since: datetime,
    until: datetime,
) -> list[dict]:
    since_utc = since.astimezone(timezone.utc)
    query = (
        f"repo:{repo} is:pr is:merged merged:>={since_utc.date().isoformat()}"
    )
    encoded = urllib.parse.urlencode({"q": query, "per_page": "50", "sort": "updated"})
    payload = _github_get(f"{GITHUB_API}/search/issues?{encoded}")
    items = payload.get("items", []) if isinstance(payload, dict) else []
    prs: list[dict] = []
    for item in items:
        merged_raw = str(item.get("pull_request", {}).get("merged_at") or "")
        if not merged_raw:
            continue
        merged_at = datetime.fromisoformat(merged_raw.replace("Z", "+00:00"))
        if merged_at < since.astimezone(timezone.utc):
            continue
        if merged_at > until.astimezone(timezone.utc):
            continue
        prs.append(
            {
                "number": int(item.get("number") or 0),
                "title": str(item.get("title") or ""),
                "author": str((item.get("user") or {}).get("login") or ""),
                "url": str(item.get("html_url") or ""),
                "body": str(item.get("body") or ""),
                "merged_at": merged_at.isoformat(),
            }
        )
    prs.sort(key=lambda row: int(row["number"]))
    return prs


def _write_output(path: str, text: str) -> None:
    if not path:
        return
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def _cmd_collect(args: argparse.Namespace) -> int:
    if args.schedule_cron and not scheduled_cron_matches_eastern(args.schedule_cron):
        print("Off-DST cron slot; skipping digest.")
        _write_output(args.github_output, "skip=true\ncount=0\n")
        return 0
    repo = args.repo or os.environ.get("GITHUB_REPOSITORY", "")
    if not repo:
        raise SystemExit("GITHUB_REPOSITORY is required.")
    since, until = digest_window()
    prs = fetch_merged_prs(repo, since=since, until=until)
    briefing = format_briefing(prs, since=since, until=until)
    _write_output(args.briefing_path, briefing)
    _write_output(args.prompt_path, VOICE_PROMPT)
    date_label = until.strftime("%A %B %d %Y")
    skip = "true" if not prs else "false"
    output = f"skip={skip}\ncount={len(prs)}\ndate_label={date_label}\n"
    _write_output(args.github_output, output)
    print(f"Collected {len(prs)} merged PR(s); skip={skip}.")
    return 0


def _cmd_post_digest(args: argparse.Namespace) -> int:
    webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook_url:
        print("DISCORD_WEBHOOK_URL is not set; skipping Discord notify.")
        return 0
    summary = args.summary
    if args.summary_file:
        with open(args.summary_file, encoding="utf-8") as handle:
            summary = handle.read()
    payload = build_digest_payload(
        date_label=args.date_label,
        article=load_article(summary or ""),
        pr_count=args.count,
    )
    post_webhook(webhook_url, payload)
    print("Posted Discord daily digest.")
    return 0


def format_release_briefing(*, name: str, tag: str, url: str, body: str) -> str:
    lines = [
        "Kind: FriendSlop GitHub release (Wand Street Journal Special Edition)",
        f"Name: {name.strip() or '(untitled)'}",
        f"Tag: {tag.strip() or '(untagged)'}",
        f"URL: {url.strip() or '(none)'}",
        "Release notes:",
        (body or "").strip() or "(no release notes)",
        "",
    ]
    return "\n".join(lines)


def _cmd_prepare_release(args: argparse.Namespace) -> int:
    briefing = format_release_briefing(
        name=args.name,
        tag=args.tag,
        url=args.url,
        body=args.body,
    )
    _write_output(args.briefing_path, briefing)
    _write_output(args.prompt_path, SPECIAL_EDITION_PROMPT)
    label = args.name.strip() or args.tag.strip() or "New release"
    if args.tag and args.tag not in label:
        label = f"{label} ({args.tag})"
    _write_output(
        args.github_output,
        f"release_label={label}\n",
    )
    print(f"Prepared Special Edition briefing for {label}.")
    return 0


def _cmd_post_release(args: argparse.Namespace) -> int:
    webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook_url:
        print("DISCORD_WEBHOOK_URL is not set; skipping Discord notify.")
        return 0
    summary = args.summary
    if args.summary_file:
        with open(args.summary_file, encoding="utf-8") as handle:
            summary = handle.read()
    if not (summary or "").strip():
        summary = args.body
    payload = build_release_payload(
        name=args.name,
        tag=args.tag,
        url=args.url,
        body=summary or "",
    )
    post_webhook(webhook_url, payload)
    print("Posted Discord Special Edition.")
    return 0


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="kind", required=True)

    collect = sub.add_parser("collect", help="Find PRs merged in the last 24 hours")
    collect.add_argument("--repo", default="")
    collect.add_argument("--briefing-path", default="")
    collect.add_argument("--prompt-path", default="")
    collect.add_argument("--github-output", default="")
    collect.add_argument(
        "--schedule-cron",
        default="",
        help="github.event.schedule cron expression; empty means always collect",
    )

    digest = sub.add_parser("post-digest", help="Post the daily wizard digest")
    digest.add_argument("--date-label", default="")
    digest.add_argument("--count", type=int, default=0)
    digest.add_argument("--summary", default="")
    digest.add_argument("--summary-file", default="")

    prepare = sub.add_parser(
        "prepare-release", help="Write Special Edition briefing + prompt files"
    )
    prepare.add_argument("--name", default=os.environ.get("RELEASE_NAME", ""))
    prepare.add_argument("--tag", default=os.environ.get("RELEASE_TAG", ""))
    prepare.add_argument("--url", default=os.environ.get("RELEASE_URL", ""))
    prepare.add_argument("--body", default=os.environ.get("RELEASE_BODY", ""))
    prepare.add_argument("--briefing-path", default="")
    prepare.add_argument("--prompt-path", default="")
    prepare.add_argument("--github-output", default="")

    release = sub.add_parser("post-release", help="Post a Special Edition release notice")
    release.add_argument("--name", default=os.environ.get("RELEASE_NAME", ""))
    release.add_argument("--tag", default=os.environ.get("RELEASE_TAG", ""))
    release.add_argument("--url", default=os.environ.get("RELEASE_URL", ""))
    release.add_argument("--body", default=os.environ.get("RELEASE_BODY", ""))
    release.add_argument("--summary", default="")
    release.add_argument("--summary-file", default="")

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    if args.kind == "collect":
        return _cmd_collect(args)
    if args.kind == "post-digest":
        return _cmd_post_digest(args)
    if args.kind == "prepare-release":
        return _cmd_prepare_release(args)
    return _cmd_post_release(args)


if __name__ == "__main__":
    raise SystemExit(main())
