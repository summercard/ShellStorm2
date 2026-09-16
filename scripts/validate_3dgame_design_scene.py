#!/usr/bin/env python3
"""Validate ShellStorm2 whitebox JSON against tools/3Dgame-design v3."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SUPPORTED = {
    "成人角色 · 1.6m / 4头身", "儿童角色 · 1.1m / 2头身", "墙壁", "地板", "门", "窗",
    "桌子", "柜子", "衣柜", "电视柜", "椅子", "沙发", "懒人沙发", "床", "办公桌", "办公椅",
    "显示器", "笔记本电脑", "文件柜", "书架", "打印机", "饮水机", "会议桌", "白板", "路灯", "箱子", "楼梯",
}
DEFAULTS = [
    ROOT / "source/art/whitebox/tower_zones/battle_level01/legacy/v011/data/whitebox_battle_98_95_v011.json",
    ROOT / "source/art/whitebox/tower_zones/stairs/v012/data/whitebox_stairs_v012.json",
]


def vector(value: object, label: str, issues: list[str]) -> None:
    if not isinstance(value, dict) or set(value) != {"x", "y", "z"}:
        issues.append(f"{label}: expected x/y/z object")
        return
    if not all(isinstance(value[key], (int, float)) for key in ("x", "y", "z")):
        issues.append(f"{label}: vector values must be numeric")


def validate(path: Path) -> list[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    issues: list[str] = []
    if data.get("version") != 3:
        issues.append("version must be 3")
    if data.get("coordinateSystem") != "blender-z-up":
        issues.append("coordinateSystem must be blender-z-up")
    if data.get("axes") != {"right": "X", "forward": "-Y", "up": "Z"}:
        issues.append("axes contract mismatch")
    if data.get("units") != {"distance": "m", "rotation": "deg"}:
        issues.append("units contract mismatch")
    groups = data.get("groups")
    components = data.get("components")
    if not isinstance(groups, list) or not isinstance(components, list):
        return issues + ["groups and components must be arrays"]
    group_names = set()
    for index, group in enumerate(groups):
        name = group.get("name") if isinstance(group, dict) else None
        if not isinstance(name, str) or not name or name in group_names:
            issues.append(f"groups[{index}]: missing or duplicate name")
        group_names.add(name)
        for key in ("position", "rotation", "scale"):
            vector(group.get(key), f"groups[{index}].{key}", issues)
    component_names = set()
    for index, component in enumerate(components):
        name = component.get("name") if isinstance(component, dict) else None
        if not isinstance(name, str) or not name or name in component_names:
            issues.append(f"components[{index}]: missing or duplicate name")
        component_names.add(name)
        if component.get("type") not in SUPPORTED:
            issues.append(f"components[{index}]: unsupported type {component.get('type')!r}")
        if component.get("group") is not None and component.get("group") not in group_names:
            issues.append(f"components[{index}]: unknown group {component.get('group')!r}")
        for key in ("position", "rotation", "scale"):
            vector(component.get(key), f"components[{index}].{key}", issues)
        if component.get("type") in {"墙壁", "地板"} and not isinstance(component.get("surfaceSettings"), dict):
            issues.append(f"components[{index}]: surfaceSettings required")
        if component.get("type") == "楼梯" and not isinstance(component.get("stairSettings"), dict):
            issues.append(f"components[{index}]: stairSettings required")
    if not isinstance(data.get("projectMetadata"), dict):
        issues.append("projectMetadata extension is required")
    return issues


def main() -> int:
    paths = [Path(arg).resolve() for arg in sys.argv[1:]] or DEFAULTS
    failed = False
    for path in paths:
        issues = validate(path)
        if issues:
            failed = True
            print(f"3DGAME_DESIGN_SCENE_FAIL {path.relative_to(ROOT)}")
            for issue in issues:
                print(f"- {issue}")
        else:
            data = json.loads(path.read_text(encoding="utf-8"))
            print(f"3DGAME_DESIGN_SCENE_OK {path.relative_to(ROOT)} groups={len(data['groups'])} components={len(data['components'])}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
