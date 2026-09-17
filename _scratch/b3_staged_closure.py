# -*- coding: utf-8 -*-
"""B3 暂存树引用闭合检查。

判据：以 INDEX（暂存区）为准，收集 B3 根内所有文本文件里出现的 res:// 路径，
逐个检查其目标是否也存在于 INDEX 中（或属于已知豁免）。任何悬空引用都必须在提交前解决。

与 validate_b2_index.py 的差别：那份校验的是"索引 blob 是否等于工作树"，
这份校验的是"索引内容自洽"——即改名后引用是否指向存在的目标。
"""
from __future__ import annotations

import re
import subprocess
import sys

REPO = r"I:\工作项目\shellstrom2\ShellStorm2"
B3_ROOT = "assets/art/environments/base_facility_3d/"
TEXT_EXT = (".tscn", ".tres", ".gd", ".json", ".md", ".cfg", ".import")
RES_RE = re.compile(r'res://([^"\'\)\s]+)')

# 批次外豁免：这些路径的版本号由后续批次（B4+）处理，属已知在账
EXEMPT_PREFIX = (
    "assets/art/vfx/",
    "assets/art/weapons/",
    "assets/art/characters/",
    "assets/art/props/",
)

# 已知历史死引用（退役架构），与去版本化无关
KNOWN_DEAD = {
    "scenes/BaseFacility.tscn",
    "scenes/Container.tscn",
    "scenes/DemoRoomChain.tscn",
    "scenes/RoomBoss.tscn",
    "scenes/ThemedNPC.tscn",
}

# 生成物 / 源资产 / 文档：不入版本或有版本豁免，不参与闭合判定
SKIP_PREFIX = (".godot/", "source/", "addons/")
SKIP_EXT = (".blend", ".png", ".jpg", ".svg", ".ttf", ".wav", ".ogg")
TRIM = "`\"')]},;: "


def normalize(rel: str) -> str:
    """解析 res:// 路径中的 .. / . 段。"""
    parts: list[str] = []
    for seg in rel.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if parts:
                parts.pop()
            continue
        parts.append(seg)
    return "/".join(parts)


def run(args) -> str:
    p = subprocess.run(args, cwd=REPO, capture_output=True)
    return p.stdout.decode("utf-8", "replace")


def main() -> int:
    # 1) INDEX 中的全部路径
    staged = set(run(["git", "ls-files", "--cached", "-z"]).split("\0"))
    staged.discard("")

    # 2) B3 根内的暂存文本文件
    targets = sorted(
        p for p in staged
        if p.startswith(B3_ROOT) and p.endswith(TEXT_EXT)
    )
    print(f"[i] INDEX 路径总数 = {len(staged)}")
    print(f"[i] B3 根内暂存文本文件 = {len(targets)}")

    danglers: dict[str, list[str]] = {}
    exempt_hits: dict[str, int] = {}
    for path in targets:
        blob = run(["git", "show", f":{path}"])
        if not blob:
            continue
        for m in RES_RE.finditer(blob):
            rel = m.group(1).strip(TRIM)
            if rel.startswith(SKIP_PREFIX) or rel.endswith(SKIP_EXT):
                continue
            rel = normalize(rel)
            if rel in staged:
                continue
            if rel in KNOWN_DEAD:
                exempt_hits["known_dead"] = exempt_hits.get("known_dead", 0) + 1
                continue
            if any(rel.startswith(px) for px in EXEMPT_PREFIX):
                key = rel.split("/")[2] if rel.count("/") > 2 else rel
                exempt_hits[key] = exempt_hits.get(key, 0) + 1
                continue
            danglers.setdefault(path, []).append(rel)

    print()
    print("=== 悬空引用（目标不存在于 INDEX） ===")
    if not danglers:
        print("  (无)")
    for path, refs in sorted(danglers.items()):
        for r in sorted(set(refs)):
            print(f"  {path}  ->  res://{r}")
    print()
    print("=== 豁免命中（批次外，非本批责任） ===")
    for k, v in sorted(exempt_hits.items()):
        print(f"  {k}: {v}")

    return 0 if not danglers else 1


if __name__ == "__main__":
    sys.exit(main())
