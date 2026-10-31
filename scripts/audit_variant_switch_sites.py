#!/usr/bin/env python3
"""把「运行时材质开关」的赋值点逐条列出来，并标出**可能落在热路径**的那些。

## 为什么需要这个脚本

`emission_enabled` 这类属性在 Godot 里是 **shader define** 而不是 uniform：翻一次要
重建 GPU 管线。实测（2026-10-31，RTX 3060 / Forward+ / `--disable-vsync`）：

| 属性 | 单次翻转 |
|---|---:|
| emission_enabled | +107 ms |
| vertex_color_use_as_albedo | +109 ms |
| transparency | +107 ms |
| no_depth_test | +105 ms |
| billboard_mode | +94 ms |
| depth_draw_mode | +86 ms |
| disable_receive_shadows | +77 ms |
| shading_mode | +19 ms |

建材质时设一次**完全没问题**（那时还没有管线可重建）；问题只在「渲染过之后又翻」。
所以这个脚本按**所在函数**分类，把「建材质时设置」和「运行时翻转」分开 ——
人工 review 80 个赋值点必然漏，脚本不会。

## 它不是门禁

函数名只能猜，猜不准（`_apply_formal_tint()` 名字像热路径，实际只跑一次）。
真正的判据是 `tools/_material_variant_cost_probe` + `_runtime_switch_cost_probe` +
`_hit_flash_binding_probe` 三个运行期探针。本脚本负责**穷举**，探针负责**定罪**。

用法：
    python3 scripts/audit_variant_switch_sites.py            # 全部
    python3 scripts/audit_variant_switch_sites.py --hot      # 只看疑似热路径
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 代价 > 3 ms 的（实测），也就是"值得看一眼"的那批。
EXPENSIVE_PROPS = (
    "emission_enabled",
    "transparency",
    "vertex_color_use_as_albedo",
    "no_depth_test",
    "billboard_mode",
    "depth_draw_mode",
    "disable_receive_shadows",
    "shading_mode",
)
# 实测 ≈0 的，列出来只是为了让"查过了"这件事可核对，不参与告警。
FREE_PROPS = ("cull_mode", "emission_energy_multiplier", "albedo_color", "roughness")

# 名字像"每帧 / 每次命中 / 每次状态切换都会跑"的函数。
HOT_HINTS = (
    "_process",
    "_physics_process",
    "_tick",
    "flash",
    "_hit",
    "take_damage",
    "take_projectile_damage",
    "on_hit",
    "apply_",
    "set_runtime",
    "set_light",
    "set_emission",
    "update",
    "_apply",
    "sync_",
    "refresh",
    "toggle",
)

SCAN_DIRS = ("src", "scenes", "assets/art")
## 这些目录里的赋值点不算数：探针自己会故意翻开关来量代价，测试夹具也常故意造脏材质。
## ⚠ 用 `Path.parts` 比较，别拼字符串 —— Windows 上是反斜杠，用 "/tests/" 永远匹配不上，
## 会让统计把 tools/ 里的探针也数进去（第一版就是这个 bug，报出 150 处虚高）。
SKIP_DIR_PARTS = ("tests", "tools", "docs")


def enclosing_functions(lines: list[str]) -> list[str]:
    """每行所属的函数名。GDScript 顶格 `func` 开启新函数。"""
    current = "<top-level>"
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if line.startswith("func ") or line.startswith("static func "):
            name = stripped.split("func ", 1)[1].split("(", 1)[0].strip()
            current = name
        out.append(current)
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hot", action="store_true", help="只打印疑似热路径的赋值点")
    args = parser.parse_args()

    rows: list[tuple[str, int, str, str, str, bool]] = []
    for base in SCAN_DIRS:
        for path in (ROOT / base).rglob("*.gd"):
            if any(part in SKIP_DIR_PARTS for part in path.relative_to(ROOT).parts):
                continue
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except OSError:
                continue
            owners = enclosing_functions(lines)
            for index, line in enumerate(lines):
                for prop in EXPENSIVE_PROPS:
                    # 只认 `<something>.<prop> =`，跳过注释行。
                    if not re.search(rf"\.{prop}\s*=", line):
                        continue
                    if line.lstrip().startswith("#"):
                        continue
                    owner = owners[index]
                    lowered = owner.lower()
                    hot = any(hint in lowered for hint in HOT_HINTS)
                    rows.append((str(path.relative_to(ROOT)), index + 1, prop, owner, line.strip(), hot))
                    break

    hot_rows = [row for row in rows if row[5]]
    print(f"变体属性赋值点：{len(rows)} 处（其中疑似运行时翻转 {len(hot_rows)} 处）")
    print(f"扫描范围：{', '.join(SCAN_DIRS)}（跳过 docs/tests/tools）")
    print()

    if args.hot:
        target = hot_rows
    else:
        target = rows
    current_file = ""
    for rel, line_no, prop, owner, text, hot in target:
        if rel != current_file:
            current_file = rel
            print(f"{rel}")
        flag = "HOT " if hot else "    "
        print(f"  {flag}{line_no:>5}  {prop:<28} in {owner}()")
        if hot:
            print(f"        {text}")
    print()
    print("判据提示：建材质时设一次 = 安全（那时没有管线）；渲染过之后再翻 = 每次都要重建。")
    print("真正的定罪用运行期探针：_material_variant_cost_probe / _runtime_switch_cost_probe /")
    print("_hit_flash_binding_probe。本脚本只负责穷举，不负责判罪。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
