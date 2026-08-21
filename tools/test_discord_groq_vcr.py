#!/usr/bin/env python3
"""Groq integration test with VCR cassette replay (two-step titles → article).

Replay (default, offline):
  python tools/test_discord_groq_vcr.py

Record / refresh cassette (needs GROQ_API_KEY):
  set GROQ_API_KEY=...
  set DISCORD_VCR_RECORD=1
  python tools/test_discord_groq_vcr.py
"""

from __future__ import annotations

import os
import unittest
from pathlib import Path

import vcr

from discord_summarize import summarize
from discord_webhook import build_digest_payload, format_discord_preview

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "discord_digest"
CASSETTES = FIXTURES / "cassettes"
CASSETTE = CASSETTES / "groq_qwen_summarize.yaml"
BRIEFING = FIXTURES / "sample_briefing.md"

VCR = vcr.VCR(
    cassette_library_dir=str(CASSETTES),
    path_transformer=vcr.VCR.ensure_suffix(".yaml"),
    filter_headers=[("authorization", "REDACTED")],
    match_on=["method", "scheme", "host", "port", "path", "query"],
    decode_compressed_response=True,
    record_mode="all"
    if os.environ.get("DISCORD_VCR_RECORD", "").strip() in {"1", "true", "yes"}
    else "none",
)


class GroqVcrTests(unittest.TestCase):
    def test_summarize_via_groq_cassette(self) -> None:
        if VCR.record_mode == "all" and not (
            os.environ.get("GROQ_API_KEY", "").strip()
            or os.environ.get("DISCORD_LLM_API_KEY", "").strip()
        ):
            self.fail("DISCORD_VCR_RECORD=1 requires GROQ_API_KEY in the environment")
        if VCR.record_mode == "none" and not CASSETTE.exists():
            self.fail(
                f"Missing cassette {CASSETTE}. Record once with:\n"
                "  GROQ_API_KEY=... DISCORD_VCR_RECORD=1 python tools/test_discord_groq_vcr.py"
            )

        briefing = BRIEFING.read_text(encoding="utf-8")
        with VCR.use_cassette("groq_qwen_summarize"):
            article = summarize(briefing=briefing, edition="daily")

        self.assertTrue(article["lede"])
        self.assertGreaterEqual(len(article["sections"]), 1)
        for section in article["sections"]:
            self.assertTrue(section["title"])
            self.assertTrue(section["body"])
            self.assertNotIn("iamemilio", section["body"].lower())
            self.assertNotIn("cursor", section["body"].lower())

        payload = build_digest_payload(
            date_label="Friday, August 21, 2026",
            article=article,
            pr_count=2,
        )
        preview = format_discord_preview(payload)
        self.assertIn("**The Wand Street Journal", preview)
        print("\n--- Discord preview ---\n" + preview)


if __name__ == "__main__":
    CASSETTES.mkdir(parents=True, exist_ok=True)
    unittest.main(verbosity=2)
