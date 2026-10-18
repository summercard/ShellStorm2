#!/usr/bin/env python3
"""Gate: 通用机制容器里不得出现按关卡 ID 分支的活代码。

背景（2026-10-18）：``Dungeon3D.configure_expedition_fate_economy`` 曾写
``if level_id != "expedition_01": return``，而四处消费方写
``if map_id == "expedition_01" and is_configured()``。新增关卡永远不被配置，
消费方永远为假 —— 一条谁都没跑到的死分支，且全部既有测试都是绿的。

这类缺陷靠用例防不住（没有用例会跑「未接入关卡的未来行为」），只能靠静态门禁。
规范见 ``docs/v0.1/关卡接入规范.md`` §3。

判据：只扫「通用机制容器」文件，注释行与字符串字面量不算。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# 通用机制容器：这些文件里的能力对所有关卡共享，不得按关卡 ID 分支。
# 新增文件前想清楚 —— 加进来是承诺「这里不写关卡 ID」。
SHARED_MECHANISM_FILES = (
    "src/world3d/Dungeon3D.gd",
    "src/game/FateEconomyService.gd",
    "src/game/InventoryModule.gd",
    "src/game/EquipmentTransactionService.gd",
    "src/rewards/RuntimeRewardCoordinator.gd",
    "src/rewards/RewardService.gd",
    "src/world3d/RunPersistenceService.gd",
)

LEVEL_ID_LITERAL = re.compile(r'["\']expedition_\d+["\']')
COMMENT_PREFIXES = ("#", "##")


def _strip_trailing_comment(line: str) -> str:
    """去掉行尾注释，但不动字符串内的 #。

    足够应付 GDScript 常见写法；命中不确定时宁可误报，由人复核。
    """
    in_single = False
    in_double = False
    for index, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:index]
    return line


def scan_file(path: Path) -> list[dict]:
    findings: list[dict] = []
    if not path.is_file():
        return findings
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = raw.lstrip()
        if not stripped or stripped.startswith(COMMENT_PREFIXES):
            continue
        code = _strip_trailing_comment(raw)
        if not LEVEL_ID_LITERAL.search(code):
            continue
        findings.append(
            {
                "file": str(path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                "line": line_number,
                "code": stripped[:180],
            }
        )
    return findings


def main() -> int:
    findings: list[dict] = []
    for relative in SHARED_MECHANISM_FILES:
        findings.extend(scan_file(PROJECT_ROOT / relative))

    report = {
        "shared_mechanism_files": len(SHARED_MECHANISM_FILES),
        "violations": len(findings),
        "rule": "通用机制按能力分支，关卡专属内容按 ID 分支 —— 见 docs/v0.1/关卡接入规范.md §3",
        "details": findings,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if findings:
        print(
            "FAIL: 通用机制容器里出现关卡 ID 分支。\n"
            "改法：换成能力判据（如 uses_dynamic_fate_economy()），或让数据段留空。\n"
            "不要在这里补 == \"expedition_0N\"。",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
