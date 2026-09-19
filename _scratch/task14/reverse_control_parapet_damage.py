"""反向对照（必须做一次）：把新断言依赖的行为改坏，确认门禁/探针真的变红。

项目纪律：字段透传 / 行为类新断言必须做一次反向对照 —— 改坏 → 须变红 → 还原。
本脚本对 TowerFloorStage3D.gd 做三次受控破坏，各跑一次对应场景，最后原样还原。

跑法：python _scratch/task14/reverse_control_parapet_damage.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "src/world3d/TowerFloorStage3D.gd"
BACKUP = PROJECT / "_scratch/task14/TowerFloorStage3D.gd.bak"
GODOT = r"I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"

CASES = [
    {
        "name": "A 破损概率改成 0（破损整体下线）",
        "replace": ("const ROOFTOP_PARAPET_DAMAGE_CHANCE := 0.25",
                    "const ROOFTOP_PARAPET_DAMAGE_CHANCE := 0.0"),
        "scene": "res://tests/verification/verify_rooftop_32x32_contract.tscn",
        "expect": "没有任何破损直段",
    },
    {
        "name": "B 破损概率改成 1（每段都破损，破坏「散落」）",
        "replace": ("const ROOFTOP_PARAPET_DAMAGE_CHANCE := 0.25",
                    "const ROOFTOP_PARAPET_DAMAGE_CHANCE := 1.0"),
        "scene": "res://tests/verification/probe_rooftop_parapet_damage_layout.tscn",
        "expect": "全挤成一段连续",
    },
    {
        "name": "C 排布忽略传入种子（随机写成常量）",
        "replace": ("rng.seed = seed_value", "rng.seed = 20260919"),
        "scene": "res://tests/verification/verify_rooftop_32x32_contract.tscn",
        "expect": "种子没接线",
    },
]


def run_scene(scene: str) -> tuple[int, str]:
    result = subprocess.run(
        [GODOT, "--headless", "--path", str(PROJECT), scene],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.returncode, (result.stdout or "") + (result.stderr or "")


def main() -> int:
    shutil.copy2(SOURCE, BACKUP)
    original = BACKUP.read_text(encoding="utf-8")
    failures: list[str] = []
    try:
        for case in CASES:
            old, new = case["replace"]
            if original.count(old) != 1:
                failures.append("%s：锚点不唯一（count=%d）" % (case["name"], original.count(old)))
                continue
            SOURCE.write_text(original.replace(old, new), encoding="utf-8")
            code, output = run_scene(case["scene"])
            hit = case["expect"] in output
            print("---- %s" % case["name"])
            for line in output.splitlines():
                if case["expect"] in line or "_FAIL" in line or "FAILED" in line:
                    print("     %s" % line.strip())
            print("     退出码=%d  命中『%s』=%s" % (code, case["expect"], hit))
            if code == 0 or not hit:
                failures.append(
                    "%s：改坏后没变红（退出码=%d，未命中『%s』）" % (case["name"], code, case["expect"])
                )
            SOURCE.write_text(original, encoding="utf-8")
    finally:
        SOURCE.write_text(original, encoding="utf-8")

    print("================================================================================")
    if failures:
        for failure in failures:
            print("REVERSE_CONTROL_FAIL %s" % failure)
        return 1
    print("REVERSE_CONTROL_OK cases=%d 全部按预期变红并已还原" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
