#!/usr/bin/env python3
"""Post merged-PR changelogs and GitHub release notices to a Discord webhook."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

EMBED_DESCRIPTION_LIMIT = 4096
EMBED_TITLE_LIMIT = 256
PR_COLOR = 0x57F287  # Discord green
RELEASE_COLOR = 0xFEE75C  # Discord yellow


def _truncate(text: str, limit: int) -> str:
    stripped = (text or "").strip()
    if len(stripped) <= limit:
        return stripped
    return stripped[: max(limit - 1, 0)].rstrip() + "…"


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
    description = _truncate(body, EMBED_DESCRIPTION_LIMIT) or "_No release notes._"
    embed = {
        "title": _truncate(heading, EMBED_TITLE_LIMIT),
        "description": description,
        "color": RELEASE_COLOR,
        "footer": {"text": "Special Edition"},
    }
    if url:
        embed["url"] = url
    return {
        "username": "FriendSlop",
        "embeds": [embed],
    }


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
