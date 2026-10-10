#!/usr/bin/env python3
"""门禁：Label3D 的淡出必须走 transparency，禁止只改 modulate.a。

背景（业主 2026-10-10 实测）
----------------------------
Godot 的 Label3D 把描边（outline）与正文（main text）当作**两条独立的着色路径**
渲染（`scene/3d/label_3d.cpp` → `_generate_glyph_surfaces`）：

    if (outline_modulate.a != 0.0 && outline_size > 0) {
        _generate_glyph_surfaces(glyphs[j], ol_offset, outline_modulate, ...);
    }
    // Main text surfaces.
    _generate_glyph_surfaces(glyphs[j], offset, modulate, ...);

描边吃的是 `outline_modulate`，**与 `modulate` 相乘关系都没有**。所以
`label.modulate.a = 0.0` 只让正文消失，描边原地留下 —— 玩家看到的就是
「物品被捡走了，地上还压着一块黑字」。而 `Label3D` 默认 `outline_size = 12`、
`outline_modulate = (0, 0, 0, 1)`，即**默认自带黑描边**，所以这不是个别配置问题。

正确做法
--------
淡出走 `GeometryInstance3D.transparency`（0 = 不透明，1 = 全透明）。它由渲染器
统一相乘，正文与描边一起走，且是连续值、可插值。本仓 `src/ui/HologramCity3D.gd`
早有先例（`node.transparency = 1.0 - rise`）。

规则
----
`src/**/*.gd` 中，凡创建了 Label3D 的文件，其 Label3D 变量不得出现：
  * `tween_property(<该变量>, "modulate:a", ...)`
  * `<该变量>.modulate.a = ...`
`<该变量>.modulate = Color(...)` 这类整体设色是允许的（不涉及 alpha 通道的单独淡出）。

退出码
------
  0 = 通过
  1 = 存在违规（逐条打印 文件:行号 与修法）

用法：
  python3 scripts/check_label3d_fade.py
  python3 scripts/check_label3d_fade.py --json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SRC_ROOT = PROJECT / "src"

# 1) 收集 Label3D 变量名：`var l := Label3D.new()` / `_label = Label3D.new()` / `var _label: Label3D`
LABEL3D_NEW = re.compile(
    r"([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*Label3D\s*)?:?=\s*Label3D\.new\("
)
LABEL3D_TYPED = re.compile(r"var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Label3D\b")

# 2) 违规写法：只动 alpha 通道
TWEEN_MODULATE_A = re.compile(
    r"tween_property\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*\"modulate:a\""
)
ASSIGN_MODULATE_A = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.modulate\.a\s*=")

PROBE_BYTES = re.compile(rb"\x00")


def label3d_vars(source: str) -> set[str]:
    names: set[str] = set()
    for pattern in (LABEL3D_NEW, LABEL3D_TYPED):
        for match in pattern.finditer(source):
            names.add(match.group(1))
    return names


def scan_file(path: Path) -> tuple[set[str], list[dict]]:
    raw = path.read_bytes()
    if PROBE_BYTES.search(raw):
        return set(), []
    source = raw.decode("utf-8", errors="replace")
    names = label3d_vars(source)
    if not names:
        return names, []
    violations: list[dict] = []
    for lineno, line in enumerate(source.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for pattern in (TWEEN_MODULATE_A, ASSIGN_MODULATE_A):
            match = pattern.search(line)
            if match is not None and match.group(1) in names:
                violations.append(
                    {
                        "file": path.relative_to(PROJECT).as_posix(),
                        "line": lineno,
                        "variable": match.group(1),
                        "code": stripped,
                    }
                )
    return names, violations


def collect() -> tuple[int, int, list[dict]]:
    scanned_files = 0
    label_files = 0
    violations: list[dict] = []
    for path in sorted(SRC_ROOT.rglob("*.gd")):
        scanned_files += 1
        names, found = scan_file(path)
        if names:
            label_files += 1
        violations.extend(found)
    return scanned_files, label_files, violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Label3D 淡出写法门禁")
    parser.add_argument("--json", action="store_true", help="输出机器可读结果")
    parser.add_argument("--quiet", action="store_true", help="通过时不打印")
    args = parser.parse_args()

    scanned_files, label_files, violations = collect()

    if args.json:
        print(
            json.dumps(
                {
                    "scanned_files": scanned_files,
                    "label3d_files": label_files,
                    "violations": violations,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 1 if violations else 0

    if violations:
        print(
            "LABEL3D_FADE_VIOLATION: Label3D 淡出必须走 transparency，"
            "只改 modulate.a 会留下描边残影。",
            file=sys.stderr,
        )
        for item in violations:
            print(
                "  {file}:{line}  ({variable})  {code}".format(**item),
                file=sys.stderr,
            )
        print(
            "  修法：把 tween_property(x, \"modulate:a\", 0.0, t) 换成 "
            "tween_property(x, \"transparency\", 1.0, t)；",
            file=sys.stderr,
        )
        print(
            "        把 x.modulate.a = 0.0 换成 x.transparency = 1.0。"
            "口径见 src/world3d/GroundLootPickup3D.gd 的淡出硬约束。",
            file=sys.stderr,
        )
        return 1

    if not args.quiet:
        print(
            "LABEL3D_FADE_OK scanned={scanned} label3d_files={label}".format(
                scanned=scanned_files, label=label_files
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
