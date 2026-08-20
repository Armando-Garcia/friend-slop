#!/usr/bin/env python3
import re
from pathlib import Path

issues = []

def scan(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(
        r"^func\s+(?:static\s+)?(\w+)\(([^)]*)\)\s*(?:->[^\n]+)?\s*:",
        text,
        re.M,
    ):
        fname = m.group(1)
        params_raw = m.group(2)
        if not params_raw.strip():
            continue
        body_start = m.end()
        next_func = re.search(r"^func\s+", text[body_start:], re.M)
        body = text[body_start : body_start + next_func.start()] if next_func else text[body_start:]
        for part in params_raw.split(","):
            part = part.strip()
            pm = re.match(r"(_?\w+)", part)
            if not pm:
                continue
            param = pm.group(1)
            if param.startswith("_"):
                continue
            if len(re.findall(r"\b" + re.escape(param) + r"\b", body)) == 0:
                line = text[: m.start()].count("\n") + 1
                issues.append(f"{path.as_posix()}:{line} {fname}({param})")

for base in [Path("scripts"), Path("tests")]:
    for p in sorted(base.rglob("*.gd")):
        scan(p)

print(len(issues))
for item in issues:
    print(item)
