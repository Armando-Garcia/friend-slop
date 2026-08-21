#!/usr/bin/env python3
"""Summarize digest briefings via a free OpenAI-compatible chat API (Groq by default).

Two easy steps for weaker models:
1) Titles only (plain lines)
2) Lede + section bodies for those titles (plain text, no JSON)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

import requests

from discord_digest import prompts_for_edition

DEFAULT_BASE_URL = "https://api.groq.com/openai/v1"
DEFAULT_MODEL = "qwen/qwen3.6-27b"

_TITLE_LINE = re.compile(r"^\s*(?:[-*]|\d+[.)])\s+")
_LEDE_LINE = re.compile(r"^\s*LEDE\s*:\s*(.*)$", re.IGNORECASE)
_SECTION_HEAD = re.compile(r"^\s*===\s*(.+?)\s*===\s*$")


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


def strip_model_noise(text: str) -> str:
    """Drop think-blocks / fences that weak models often prepend."""
    cleaned = text or ""
    # Closed think blocks first, then any unclosed trailing think dump.
    cleaned = re.sub(
        r"<think>.*?</think>",
        "",
        cleaned,
        flags=re.DOTALL | re.IGNORECASE,
    )
    cleaned = re.sub(
        r"<think>.*\Z",
        "",
        cleaned,
        flags=re.DOTALL | re.IGNORECASE,
    )
    cleaned = cleaned.strip()
    fence = re.search(
        r"```(?:\w+)?\s*(.*?)\s*```",
        cleaned,
        re.DOTALL | re.IGNORECASE,
    )
    if fence:
        return fence.group(1).strip()
    # Drop stray fence markers if the model forgot a closer.
    lines = [line for line in cleaned.splitlines() if line.strip() != "```"]
    return "\n".join(lines).strip()


def parse_titles(raw: str) -> list[str]:
    """Parse a plain title list from the model (one title per line)."""
    titles: list[str] = []
    for line in strip_model_noise(raw).splitlines():
        item = _TITLE_LINE.sub("", line).strip()
        item = item.strip("\"'`*")
        if not item:
            continue
        lower = item.lower()
        if lower.startswith(
            (
                "lede:",
                "here",
                "sure",
                "output",
                "title",
                "analyze",
                "constraint",
                "source",
                "role",
                "task",
                "section title",
            )
        ):
            continue
        if item.startswith("=") or item.endswith(":") or "**" in item:
            continue
        if len(item) > 80:
            continue
        if item not in titles:
            titles.append(item)
        if len(titles) >= 5:
            break
    if not titles:
        raise ValueError("LLM returned no section titles")
    return titles


def build_article_user_message(*, titles: list[str], briefing: str) -> str:
    title_block = "\n".join(titles)
    return (
        "Section titles (use these exact strings, same order):\n"
        f"{title_block}\n\n"
        "Source material follows.\n\n"
        f"{briefing}"
    )


def parse_article(raw: str, *, expected_titles: list[str] | None = None) -> dict:
    """Parse lede + === Title === bodies. Falls back to legacy JSON if present."""
    cleaned = strip_model_noise(raw)
    if expected_titles is None and cleaned.lstrip().startswith("{"):
        return _parse_article_json(cleaned)

    lede = ""
    sections: list[dict] = []
    current_title: str | None = None
    body_lines: list[str] = []

    def flush() -> None:
        nonlocal current_title, body_lines
        if current_title is None:
            return
        body = "\n".join(body_lines).strip()
        if body:
            sections.append({"title": current_title, "body": body})
        current_title = None
        body_lines = []

    for line in cleaned.splitlines():
        lede_match = _LEDE_LINE.match(line)
        if lede_match and current_title is None and not sections:
            lede = lede_match.group(1).strip()
            continue
        section_match = _SECTION_HEAD.match(line)
        if section_match:
            flush()
            current_title = section_match.group(1).strip()
            continue
        if current_title is not None:
            body_lines.append(line)
        elif not lede and line.strip() and not line.strip().startswith("="):
            # Tolerant: first prose before any SECTION becomes the lede.
            lede = (lede + " " + line.strip()).strip() if lede else line.strip()

    flush()

    if expected_titles:
        by_title = {s["title"].casefold(): s for s in sections}
        ordered: list[dict] = []
        for title in expected_titles:
            found = by_title.get(title.casefold())
            if found:
                ordered.append({"title": title, "body": found["body"]})
            else:
                # Title present but body missing — keep slot only if we have something.
                pass
        if ordered:
            sections = ordered

    if not lede and not sections:
        # Last resort: legacy JSON buried in noisy text.
        try:
            return _parse_article_json(cleaned)
        except ValueError as exc:
            raise ValueError("LLM article had no lede or sections") from exc
    return {"lede": lede, "sections": sections}


def _parse_article_json(raw: str) -> dict:
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("LLM reply contained no JSON object")
    try:
        data = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as exc:
        raise ValueError(f"LLM did not return JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("LLM JSON root must be an object")
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
        raise ValueError("LLM article had no lede or sections")
    return {"lede": lede, "sections": sections}


def build_chat_request_body(
    *,
    system_prompt: str,
    user_content: str,
    max_tokens: int = 900,
    temperature: float = 0.3,
) -> dict:
    """Request body sent to the chat API (no response_format)."""
    body = {
        "model": _model(),
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
    }
    # Qwen 3.x on Groq defaults to reasoning and can burn the whole token
    # budget inside <think> without emitting the answer. Disable it.
    if "qwen" in _model().lower():
        body["reasoning_effort"] = "none"
    return body


def _chat(*, key: str, system_prompt: str, user_content: str, max_tokens: int) -> str:
    body = build_chat_request_body(
        system_prompt=system_prompt,
        user_content=user_content,
        max_tokens=max_tokens,
    )
    try:
        response = requests.post(
            f"{_base_url()}/chat/completions",
            json=body,
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
                "User-Agent": "friend-slop-discord-digest",
            },
            timeout=90,
        )
    except requests.RequestException as exc:
        raise SystemExit(f"LLM request failed: {exc}") from exc
    if not response.ok:
        raise SystemExit(f"LLM request failed ({response.status_code}): {response.text}")
    return extract_assistant_text(response.json())


def summarize(
    *,
    briefing: str,
    edition: str = "daily",
    system_prompt: str | None = None,
    chat_fn=None,
) -> dict:
    """Two-step summarize: titles, then article bodies.

    chat_fn(system_prompt, user_content) -> str may be called twice in tests.
    system_prompt is accepted for back-compat; edition selects the title/article pair.
    """
    title_prompt, article_prompt = prompts_for_edition(edition)
    if system_prompt and "Special Edition" in system_prompt:
        title_prompt, article_prompt = prompts_for_edition("special")
    elif system_prompt:
        # Caller supplied an article voice prompt; keep title prompt for the edition.
        article_prompt = system_prompt

    def run_chat(prompt: str, user_content: str, max_tokens: int) -> str:
        if chat_fn is not None:
            return chat_fn(prompt, user_content)
        key = _api_key()
        if not key:
            raise SystemExit(
                "Set GROQ_API_KEY (free at https://console.groq.com) or DISCORD_LLM_API_KEY. "
                "GitHub Copilot credits are not required."
            )
        return _chat(
            key=key,
            system_prompt=prompt,
            user_content=user_content,
            max_tokens=max_tokens,
        )

    titles = parse_titles(
        run_chat(
            title_prompt,
            "Source material follows. Reply with section titles only.\n\n" + briefing,
            200,
        )
    )
    article_user = build_article_user_message(titles=titles, briefing=briefing)
    return parse_article(
        run_chat(article_prompt, article_user, 1200),
        expected_titles=titles,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--briefing-file", required=True)
    parser.add_argument("--output-file", required=True)
    parser.add_argument(
        "--edition",
        choices=("daily", "special"),
        default="daily",
        help="daily closing vs Special Edition prompts",
    )
    parser.add_argument(
        "--prompt-file",
        default="",
        help="Optional override for the article-step system prompt",
    )
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])
    with open(args.briefing_file, encoding="utf-8") as handle:
        briefing = handle.read()
    article_prompt = None
    if args.prompt_file:
        with open(args.prompt_file, encoding="utf-8") as handle:
            article_prompt = handle.read()
    article = summarize(
        briefing=briefing,
        edition=args.edition,
        system_prompt=article_prompt,
    )
    with open(args.output_file, "w", encoding="utf-8") as handle:
        json.dump(article, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"Wrote article JSON to {args.output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
