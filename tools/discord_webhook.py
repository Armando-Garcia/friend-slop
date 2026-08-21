#!/usr/bin/env python3
"""Discord webhook helpers for FriendSlop notifications."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

EMBED_DESCRIPTION_LIMIT = 4096
EMBED_TITLE_LIMIT = 256
EMBED_FIELD_NAME_LIMIT = 256
EMBED_FIELD_VALUE_LIMIT = 1024
EMBED_FIELD_LIMIT = 25
PR_COLOR = 0x57F287  # Discord green
RELEASE_COLOR = 0xFEE75C  # Discord yellow
DIGEST_COLOR = 0x1C2833


def _truncate(text: str, limit: int) -> str:
    stripped = (text or "").strip()
    if len(stripped) <= limit:
        return stripped
    return stripped[: max(limit - 1, 0)].rstrip() + "…"


def load_article(raw: str) -> dict:
    """Accept article JSON or plain text (plain text becomes a single-lede article)."""
    text = (raw or "").strip()
    if not text:
        return {"lede": "", "sections": []}
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return {"lede": text, "sections": []}
    if not isinstance(data, dict):
        return {"lede": text, "sections": []}
    lede = str(data.get("lede") or "").strip()
    sections: list[dict] = []
    for item in data.get("sections") or []:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        body = str(item.get("body") or "").strip()
        if title and body:
            sections.append({"title": title, "body": body})
    if not lede and not sections:
        return {"lede": text, "sections": []}
    return {"lede": lede, "sections": sections}


def article_to_embed_parts(article: dict) -> tuple[str, list[dict]]:
    """Turn an article into Discord description + full-width fields."""
    lede = _truncate(str(article.get("lede") or ""), EMBED_DESCRIPTION_LIMIT)
    fields: list[dict] = []
    for section in article.get("sections") or []:
        if len(fields) >= EMBED_FIELD_LIMIT:
            break
        title = _truncate(str(section.get("title") or ""), EMBED_FIELD_NAME_LIMIT)
        body = _truncate(str(section.get("body") or ""), EMBED_FIELD_VALUE_LIMIT)
        if not title or not body:
            continue
        fields.append({"name": title, "value": body, "inline": False})
    return lede, fields


def build_pr_payload(
    *,
    number: str,
    title: str,
    url: str,
    author: str,
    body: str,
) -> dict:
    heading = f"PR #{number} merged: {title}".strip()
    description = _truncate(body, EMBED_DESCRIPTION_LIMIT) or "_No description._"
    embed = {
        "title": _truncate(heading, EMBED_TITLE_LIMIT),
        "url": url,
        "description": description,
        "color": PR_COLOR,
    }
    if author:
        embed["author"] = {"name": author}
    return {
        "username": "FriendSlop",
        "embeds": [embed],
    }


def build_digest_payload(*, date_label: str, article: dict, pr_count: int) -> dict:
    title = f"The Wand Street Journal — {date_label}"
    footer = (
        f"Daily closing · {pr_count} pull request"
        f"{'s' if pr_count != 1 else ''} merged"
    )
    lede, fields = article_to_embed_parts(article)
    embed: dict = {
        "title": _truncate(title, EMBED_TITLE_LIMIT),
        "color": DIGEST_COLOR,
        "footer": {"text": footer},
    }
    if lede:
        embed["description"] = lede
    elif not fields:
        embed["description"] = "_No copy._"
    if fields:
        embed["fields"] = fields
    return {"username": "The Wand Street Journal", "embeds": [embed]}


def build_release_payload(
    *,
    name: str,
    tag: str,
    url: str,
    body: str,
) -> dict:
    release_label = name.strip() or tag.strip() or "New release"
    if tag and tag not in release_label:
        release_label = f"{release_label} ({tag})"
    heading = f"The Wand Street Journal — Special Edition: {release_label}"
    article = load_article(body)
    lede, fields = article_to_embed_parts(article)
    if not lede and not fields:
        lede = "_No release notes._"
    embed: dict = {
        "title": _truncate(heading, EMBED_TITLE_LIMIT),
        "color": RELEASE_COLOR,
        "footer": {"text": "Special Edition"},
    }
    if lede:
        embed["description"] = lede
    if fields:
        embed["fields"] = fields
    if url:
        embed["url"] = url
    return {"username": "The Wand Street Journal", "embeds": [embed]}


def post_webhook(webhook_url: str, payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        webhook_url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "User-Agent": "friend-slop-discord-notify",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Discord webhook failed ({exc.code}): {detail}") from exc


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="kind", required=True)

    pr_cmd = sub.add_parser("pr", help="Notify that a pull request merged")
    pr_cmd.add_argument("--number", default=os.environ.get("PR_NUMBER", ""))
    pr_cmd.add_argument("--title", default=os.environ.get("PR_TITLE", ""))
    pr_cmd.add_argument("--url", default=os.environ.get("PR_URL", ""))
    pr_cmd.add_argument("--author", default=os.environ.get("PR_AUTHOR", ""))
    pr_cmd.add_argument("--body", default=os.environ.get("PR_BODY", ""))

    rel_cmd = sub.add_parser("release", help="Notify that a GitHub release published")
    rel_cmd.add_argument("--name", default=os.environ.get("RELEASE_NAME", ""))
    rel_cmd.add_argument("--tag", default=os.environ.get("RELEASE_TAG", ""))
    rel_cmd.add_argument("--url", default=os.environ.get("RELEASE_URL", ""))
    rel_cmd.add_argument("--body", default=os.environ.get("RELEASE_BODY", ""))

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook_url:
        print("DISCORD_WEBHOOK_URL is not set; skipping Discord notify.")
        return 0

    if args.kind == "pr":
        payload = build_pr_payload(
            number=args.number,
            title=args.title,
            url=args.url,
            author=args.author,
            body=args.body,
        )
    else:
        payload = build_release_payload(
            name=args.name,
            tag=args.tag,
            url=args.url,
            body=args.body,
        )
    post_webhook(webhook_url, payload)
    print(f"Posted Discord {args.kind} notification.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
