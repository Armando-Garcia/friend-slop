#!/usr/bin/env python3
"""Unit checks for Discord digest and webhook payload shaping."""

from __future__ import annotations

import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

from discord_digest import (
    build_digest_payload,
    digest_window,
    format_briefing,
    format_release_briefing,
    scheduled_cron_matches_eastern,
)
from discord_webhook import (
    EMBED_DESCRIPTION_LIMIT,
    build_release_payload,
)

EASTERN = ZoneInfo("America/New_York")


class DiscordWebhookTests(unittest.TestCase):
    def test_release_payload_is_special_edition(self) -> None:
        payload = build_release_payload(
            name="Playtest",
            tag="v0.2.0",
            url="https://github.com/iamemilio/friend-slop/releases/tag/v0.2.0",
            body="Windows and Linux builds.",
        )
        embed = payload["embeds"][0]
        self.assertEqual(
            embed["title"],
            "The Wand Street Journal — Special Edition: Playtest (v0.2.0)",
        )
        self.assertEqual(embed["footer"]["text"], "Special Edition")
        self.assertIn("Windows and Linux", embed["description"])

    def test_digest_payload_names_the_desk(self) -> None:
        payload = build_digest_payload(
            date_label="Friday, August 21, 2026",
            summary="Wards found a bid after the morning shatter.",
            pr_count=2,
        )
        embed = payload["embeds"][0]
        self.assertIn("The Wand Street Journal", embed["title"])
        self.assertIn("August 21, 2026", embed["title"])
        self.assertIn("Wards found a bid", embed["description"])
        self.assertEqual(
            embed["footer"]["text"],
            "Daily closing · 2 pull requests merged",
        )

    def test_long_digest_is_truncated(self) -> None:
        payload = build_digest_payload(
            date_label="Friday",
            summary="x" * (EMBED_DESCRIPTION_LIMIT + 50),
            pr_count=1,
        )
        description = payload["embeds"][0]["description"]
        self.assertEqual(len(description), EMBED_DESCRIPTION_LIMIT)
        self.assertTrue(description.endswith("…"))


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

    def test_empty_briefing_still_reports_count(self) -> None:
        now = datetime(2026, 8, 21, 15, 45, tzinfo=EASTERN)
        text = format_briefing([], since=now, until=now)
        self.assertIn("Merged PR count: 0", text)

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


if __name__ == "__main__":
    unittest.main()
