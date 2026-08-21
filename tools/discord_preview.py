#!/usr/bin/env python3
"""Local dry-run for Wand Street Journal Discord digests (no network)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures" / "discord_digest"

from discord_summarize import extract_assistant_text, summarize  # noqa: E402
from discord_webhook import (  # noqa: E402
    build_digest_payload,
    format_discord_preview,
)


def _load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--briefing",
        type=Path,
        default=FIXTURES / "sample_briefing.md",
        help="Merged-PR briefing text",
    )
    parser.add_argument(
        "--titles-response",
        type=Path,
        default=FIXTURES / "sample_llm_titles.json",
        help="Fixture chat-completions JSON for the titles step",
    )
    parser.add_argument(
        "--article-response",
        type=Path,
        default=FIXTURES / "sample_llm_article.json",
        help="Fixture chat-completions JSON for the article step",
    )
    parser.add_argument(
        "--date-label",
        default="Friday, August 21, 2026",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=2,
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        default=None,
        help="Optional path to write the Discord webhook payload JSON",
    )
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    briefing = _load_text(args.briefing)
    titles_payload = json.loads(_load_text(args.titles_response))
    article_payload = json.loads(_load_text(args.article_response))
    calls = {"n": 0}

    def chat_fn(_prompt: str, _user: str) -> str:
        calls["n"] += 1
        if calls["n"] == 1:
            return extract_assistant_text(titles_payload)
        return extract_assistant_text(article_payload)

    article = summarize(briefing=briefing, edition="daily", chat_fn=chat_fn)
    payload = build_digest_payload(
        date_label=args.date_label,
        article=article,
        pr_count=args.count,
    )
    preview = format_discord_preview(payload)
    print(preview)
    if args.json_out is not None:
        args.json_out.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote webhook payload to {args.json_out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
