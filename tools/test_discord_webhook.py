#!/usr/bin/env python3
"""Unit checks for Discord digest and webhook payload shaping."""

from __future__ import annotations

import json
import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

from discord_summarize import extract_assistant_text, parse_article
from discord_digest import (
    digest_window,
    format_briefing,
    format_release_briefing,
    scheduled_cron_matches_eastern,
)
from discord_webhook import (
    EMBED_DESCRIPTION_LIMIT,
    EMBED_FIELD_VALUE_LIMIT,
    article_to_embed_parts,
    build_digest_payload,
    build_release_payload,
    load_article,
)

EASTERN = ZoneInfo("America/New_York")


class DiscordWebhookTests(unittest.TestCase):
    def test_release_payload_uses_article_fields(self) -> None:
        article = {
            "lede": "Playtest ships for Windows and Linux.",
            "sections": [
                {"title": "Distribution", "body": "Archives land on the release page."}
            ],
        }
        payload = build_release_payload(
            name="Playtest",
            tag="v0.2.0",
            url="https://github.com/iamemilio/friend-slop/releases/tag/v0.2.0",
            body=json.dumps(article),
        )
        embed = payload["embeds"][0]
        self.assertEqual(
            embed["title"],
            "The Wand Street Journal — Special Edition: Playtest (v0.2.0)",
        )
        self.assertEqual(embed["footer"]["text"], "Special Edition")
        self.assertIn("Playtest ships", embed["description"])
        self.assertEqual(embed["fields"][0]["name"], "Distribution")
        self.assertFalse(embed["fields"][0]["inline"])

    def test_digest_payload_uses_section_fields(self) -> None:
        payload = build_digest_payload(
            date_label="Friday, August 21, 2026",
            article={
                "lede": "Wards found their footing after the morning shatter.",
                "sections": [
                    {
                        "title": "Combat",
                        "body": "Ward shields now regenerate after a brief delay.",
                    }
                ],
            },
            pr_count=2,
        )
        embed = payload["embeds"][0]
        self.assertIn("The Wand Street Journal", embed["title"])
        self.assertIn("August 21, 2026", embed["title"])
        self.assertIn("Wards found their footing", embed["description"])
        self.assertEqual(embed["fields"][0]["name"], "Combat")
        self.assertEqual(
            embed["footer"]["text"],
            "Daily closing · 2 pull requests merged",
        )

    def test_long_field_body_is_truncated(self) -> None:
        lede, fields = article_to_embed_parts(
            {
                "lede": "x" * (EMBED_DESCRIPTION_LIMIT + 50),
                "sections": [
                    {"title": "Tooling", "body": "y" * (EMBED_FIELD_VALUE_LIMIT + 40)}
                ],
            }
        )
        self.assertEqual(len(lede), EMBED_DESCRIPTION_LIMIT)
        self.assertTrue(lede.endswith("…"))
        self.assertEqual(len(fields[0]["value"]), EMBED_FIELD_VALUE_LIMIT)
        self.assertTrue(fields[0]["value"].endswith("…"))


class DiscordDigestTests(unittest.TestCase):
    def test_dst_picks_the_345pm_eastern_cron(self) -> None:
        edt = datetime(2026, 8, 21, 15, 45, tzinfo=EASTERN)
        est = datetime(2026, 1, 15, 15, 45, tzinfo=EASTERN)
        self.assertTrue(scheduled_cron_matches_eastern("45 19 * * *", edt))
        self.assertFalse(scheduled_cron_matches_eastern("45 20 * * *", edt))
        self.assertTrue(scheduled_cron_matches_eastern("45 20 * * *", est))
        self.assertFalse(scheduled_cron_matches_eastern("45 19 * * *", est))

    def test_window_is_trailing_24_hours(self) -> None:
        now = datetime(2026, 8, 21, 15, 45, tzinfo=EASTERN)
        since, until = digest_window(now)
        self.assertEqual(until, now)
        self.assertEqual((until - since).total_seconds(), 24 * 60 * 60)

    def test_briefing_omits_authors(self) -> None:
        now = datetime(2026, 8, 21, 15, 45, tzinfo=EASTERN)
        text = format_briefing(
            [
                {
                    "number": 42,
                    "title": "Ward regen",
                    "author": "iamemilio",
                    "url": "https://example.com",
                    "body": "Wards heal.",
                    "merged_at": now.isoformat(),
                }
            ],
            since=now,
            until=now,
        )
        self.assertNotIn("iamemilio", text)
        self.assertIn("Ignore authors", text)

    def test_release_briefing_marks_special_edition(self) -> None:
        text = format_release_briefing(
            name="Playtest",
            tag="v0.2.0",
            url="https://example.com",
            body="Ships Windows builds.",
        )
        self.assertIn("Special Edition", text)
        self.assertIn("v0.2.0", text)
        self.assertIn("Ships Windows builds.", text)

    def test_extract_and_parse_article(self) -> None:
        text = extract_assistant_text(
            {
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "lede": "Wards closed higher.",
                                    "sections": [
                                        {
                                            "title": "Combat",
                                            "body": "Regen delay doubled after shatter.",
                                        }
                                    ],
                                }
                            )
                        }
                    }
                ]
            }
        )
        article = parse_article(text)
        self.assertEqual(article["lede"], "Wards closed higher.")
        self.assertEqual(article["sections"][0]["title"], "Combat")

    def test_load_article_accepts_plain_text(self) -> None:
        article = load_article("Just a dek.")
        self.assertEqual(article["lede"], "Just a dek.")
        self.assertEqual(article["sections"], [])


if __name__ == "__main__":
    unittest.main()
