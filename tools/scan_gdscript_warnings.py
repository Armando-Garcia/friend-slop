#!/usr/bin/env python3
"""Static scan for common Godot GDScript analyzer warnings in project scripts."""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_ROOTS = (ROOT / "scripts", ROOT / "tests")
BUILTIN_FUNCS = {
    "seed",
    "range",
    "print",
    "str",
    "int",
    "float",
    "typeof",
    "len",
    "max",
    "min",
    "abs",
    "sign",
    "clamp",
    "lerp",
    "load",
    "preload",
    "assert",
    "is_instance_valid",
}
NODE_BASES = {
    "Node",
    "Control",
    "Node3D",
    "CharacterBody3D",
    "CanvasLayer",
    "CanvasItem",
    "Resource",
}
NODE_MEMBERS = {
    "ready",
    "name",
    "position",
    "rotation",
    "scale",
    "size",
    "visible",
    "process",
    "stop",
    "owner",
    "parent",
    "transform",
    "velocity",
    "theme",
    "tooltip_text",
    "focus_mode",
}


def _class_names() -> dict[str, Path]:
    names: dict[str, Path] = {}
    for base in SCAN_ROOTS:
        for path in base.rglob("*.gd"):
            match = re.search(r"^class_name\s+(\w+)", path.read_text(encoding="utf-8"), re.M)
            if match:
                names[match.group(1)] = path
    return names


def _extends_chain(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^extends\s+(\w+)", text, re.M)
    if not match:
        return []
    chain = [match.group(1)]
    seen = {chain[0]}
    while chain[-1] not in NODE_BASES and chain[-1] != "RefCounted":
        parent = ROOT / "scripts"
        found = None
        for candidate in parent.rglob("*.gd"):
            if re.search(rf"^class_name\s+{re.escape(chain[-1])}\b", candidate.read_text(encoding="utf-8"), re.M):
                found = candidate
                break
        if found is None:
            break
        parent_ext = re.search(r"^extends\s+(\w+)", found.read_text(encoding="utf-8"), re.M)
        if parent_ext is None:
            break
        next_ext = parent_ext.group(1)
        if next_ext in seen:
            break
        chain.append(next_ext)
        seen.add(next_ext)
    return chain


def _node_like(path: Path) -> bool:
    chain = _extends_chain(path)
    return any(base in NODE_BASES for base in chain) or any(
        ext.endswith("Panel") or ext.endswith("Menu") for ext in chain
    )


def _parse_params(params: str) -> list[str]:
    names: list[str] = []
    for part in params.split(","):
        part = part.strip()
        if not part:
            continue
        match = re.match(r"(_?\w+)", part)
        if match:
            names.append(match.group(1))
    return names


def _scan_file(path: Path, class_names: dict[str, Path]) -> list[tuple[int, str, str]]:
    text = path.read_text(encoding="utf-8")
    issues: list[tuple[int, str, str]] = []
    node_like = _node_like(path)

    for match in re.finditer(r"^(\s*)const\s+(\w+)\s*:=\s*preload\(", text, re.M):
        name = match.group(2)
        if name in class_names and not name.endswith("Script"):
            line_no = text[: match.start()].count("\n") + 1
            issues.append((line_no, "SHADOWED_GLOBAL_IDENTIFIER", f"const {name} shadows class_name"))

    for match in re.finditer(
        r"^func\s+(static\s+)?(\w+)\((.*?)\)\s*(?:->[^\n]+)?\s*:",
        text,
        re.M | re.S,
    ):
        is_static = bool(match.group(1))
        func_name = match.group(2)
        line_no = text[: match.start()].count("\n") + 1
        for param in _parse_params(match.group(3)):
            if param in BUILTIN_FUNCS:
                issues.append(
                    (
                        line_no,
                        "SHADOWED_GLOBAL_IDENTIFIER",
                        f'parameter "{param}" in {func_name}()',
                    )
                )
            if node_like and not is_static and param in NODE_MEMBERS:
                issues.append(
                    (
                        line_no,
                        "SHADOWED_VARIABLE_BASE_CLASS",
                        f'parameter "{param}" in {func_name}()',
                    )
                )

    methods = set(re.findall(r"^func\s+(\w+)\(", text, re.M))
    for match in re.finditer(r"\bvar\s+(\w+)\b", text):
        var_name = match.group(1)
        if var_name in methods:
            line_no = text[: match.start()].count("\n") + 1
            issues.append(
                (line_no, "SHADOWED_VARIABLE", f'variable "{var_name}" shadows func {var_name}()')
            )

    header = re.split(r"^func ", text, maxsplit=1)[0]
    for match in re.finditer(r"^(?:@onready\s+)?var\s+(_\w+)", header, re.M):
        name = match.group(1)
        if len(re.findall(r"\b" + re.escape(name) + r"\b", text)) <= 1:
            line_no = text[: match.start()].count("\n") + 1
            issues.append((line_no, "UNUSED_PRIVATE_CLASS_VARIABLE", name))

    for match in re.finditer(r"^signal\s+(\w+)", text, re.M):
        signal_name = match.group(1)
        if not re.search(rf"\b{re.escape(signal_name)}\.emit\b", text):
            line_no = text[: match.start()].count("\n") + 1
            issues.append((line_no, "UNUSED_SIGNAL", signal_name))

    for match in re.finditer(r"^@onready var (\w+) = \$", text, re.M):
        line_no = text[: match.start()].count("\n") + 1
        issues.append((line_no, "UNTYPED_DECLARATION", f"@onready var {match.group(1)}"))

    return issues


def main() -> int:
    class_names = _class_names()
    grouped: dict[str, list[str]] = defaultdict(list)
    total = 0

    for base in SCAN_ROOTS:
        for path in sorted(base.rglob("*.gd")):
            for line_no, code, detail in _scan_file(path, class_names):
                rel = path.relative_to(ROOT).as_posix()
                grouped[code].append(f"{rel}:{line_no}: {detail}")
                total += 1

    if total == 0:
        print("No likely GDScript analyzer issues found under scripts/ and tests/.")
        return 0

    print(f"Found {total} likely issue(s):\n")
    for code in sorted(grouped):
        print(f"=== {code} ({len(grouped[code])}) ===")
        for item in grouped[code]:
            print(f"  {item}")
        print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
