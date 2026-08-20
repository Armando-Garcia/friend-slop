#!/usr/bin/env python3
"""Cursor stop hook: run lint, GDScript warnings, and unit tests before the agent finishes."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOG_PATH = Path(__file__).resolve().parent / "last-run.log"
MAX_OUTPUT_CHARS = 4000
MAX_LOOP_COUNT = 5
RUN_CHECKS = ROOT / "tools" / "run_checks.py"


def _log(message: str) -> None:
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"[{stamp}] {message}\n")


def _read_hook_input() -> dict:
    raw = sys.stdin.buffer.read().decode("utf-8-sig")
    _log(f"stdin={raw!r}")
    if not raw.strip():
        return {"status": "completed", "loop_count": 0}
    return json.loads(raw)


def _loop_count(payload: dict) -> int:
    if "loop_count" in payload:
        return int(payload["loop_count"])
    if "loopCount" in payload:
        return int(payload["loopCount"])
    return 0


def _emit(payload: dict) -> None:
    text = json.dumps(payload)
    sys.stdout.write(text)
    sys.stdout.write("\n")
    sys.stdout.flush()


def _run_checks() -> tuple[int, str]:
    python = _project_python()
    proc = subprocess.run(
        [str(python), str(RUN_CHECKS)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, output


def _project_python() -> Path:
    if sys.platform == "win32":
        candidate = ROOT / ".venv" / "Scripts" / "python.exe"
    else:
        candidate = ROOT / ".venv" / "bin" / "python"
    if candidate.is_file():
        return candidate
    return Path(sys.executable)


def main() -> int:
    try:
        payload = _read_hook_input()
        status = str(payload.get("status", "completed"))
        loop_count = _loop_count(payload)

        if status != "completed":
            _log(f"skip status={status}")
            _emit({})
            return 0

        if loop_count >= MAX_LOOP_COUNT:
            _log(f"skip loop_count={loop_count}")
            _emit({})
            return 0

        exit_code, output = _run_checks()
        _log(f"checks exit={exit_code}")

        if exit_code == 0:
            _emit({})
            return 0

        text = output.strip()
        if len(text) > MAX_OUTPUT_CHARS:
            text = text[:MAX_OUTPUT_CHARS] + "\n... (output truncated)"

        followup = (
            f"Heads up: pre-finish checks didn't pass (exit {exit_code}). "
            "If you're wrapping up code changes, you may want to look at "
            "lint, GDScript warning, or unit test output below.\n\n"
            f"{text}"
        )
        _emit({"followup_message": followup})
        return 0
    except Exception as exc:  # noqa: BLE001
        _log(f"error={exc!r}")
        _emit(
            {
                "followup_message": (
                    "Pre-finish hook crashed. See .cursor/hooks/last-run.log "
                    f"for details.\n\n{exc}"
                )
            }
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
