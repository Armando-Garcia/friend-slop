#!/usr/bin/env python3
"""Summarize digest briefings via a free OpenAI-compatible chat API (Groq by default)."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

DEFAULT_BASE_URL = "https://api.groq.com/openai/v1"
DEFAULT_MODEL = "qwen/qwen3.6-27b"


def _api_key() -> str:
    return (
        os.environ.get("DISCORD_LLM_API_KEY", "").strip()
        or os.environ.get("GROQ_API_KEY", "").strip()
    )


def _base_url() -> str:
    return (
        os.environ.get("DISCORD_LLM_BASE_URL", "").strip()
        or os.environ.get("LLM_BASE_URL", "").strip()
        or DEFAULT_BASE_URL
    ).rstrip("/")


def _model() -> str:
    return (
        os.environ.get("DISCORD_LLM_MODEL", "").strip()
        or os.environ.get("LLM_MODEL", "").strip()
        or DEFAULT_MODEL
    )


def extract_assistant_text(payload: dict) -> str:
    choices = payload.get("choices") or []
    if not choices:
        raise ValueError("LLM response had no choices")
    message = choices[0].get("message") or {}
    content = message.get("content")
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(str(item.get("text") or ""))
            elif isinstance(item, str):
                parts.append(item)
        text = "\n".join(part for part in parts if part).strip()
    else:
        text = str(content or "").strip()
    if not text:
        raise ValueError("LLM response was empty")
    return text


def _strip_code_fence(text: str) -> str:
    stripped = text.strip()
    match = re.match(r"^```(?:json)?\s*(.*?)\s*```$", stripped, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return stripped


def parse_article(raw: str) -> dict:
    """Parse model JSON into {lede: str, sections: [{title, body}, ...]}."""
    text = _strip_code_fence(raw)
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"LLM did not return JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("LLM JSON root must be an object")
    lede = str(data.get("lede") or "").strip()
    sections_raw = data.get("sections") or []
    if not isinstance(sections_raw, list):
        raise ValueError("LLM JSON sections must be a list")
    sections: list[dict] = []
    for item in sections_raw:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        body = str(item.get("body") or "").strip()
        if title and body:
            sections.append({"title": title, "body": body})
    if not lede and not sections:
        raise ValueError("LLM article had no lede or sections")
    return {"lede": lede, "sections": sections}


def summarize(*, system_prompt: str, briefing: str) -> dict:
    key = _api_key()
    if not key:
        raise SystemExit(
            "Set GROQ_API_KEY (free at https://console.groq.com) or DISCORD_LLM_API_KEY. "
            "GitHub Copilot credits are not required."
        )
    body = {
        "model": _model(),
        "temperature": 0.65,
        "max_tokens": 1200,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": system_prompt},
            {
                "role": "user",
                "content": (
                    "Source material follows. Reply with JSON only.\n\n"
                    f"{briefing}"
                ),
            },
        ],
    }
    request = urllib.request.Request(
        f"{_base_url()}/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "User-Agent": "friend-slop-discord-digest",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"LLM request failed ({exc.code}): {detail}") from exc
    return parse_article(extract_assistant_text(payload))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--briefing-file", required=True)
    parser.add_argument("--output-file", required=True)
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])
    with open(args.prompt_file, encoding="utf-8") as handle:
        prompt = handle.read()
    with open(args.briefing_file, encoding="utf-8") as handle:
        briefing = handle.read()
    article = summarize(system_prompt=prompt, briefing=briefing)
    with open(args.output_file, "w", encoding="utf-8") as handle:
        json.dump(article, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"Wrote article JSON to {args.output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
