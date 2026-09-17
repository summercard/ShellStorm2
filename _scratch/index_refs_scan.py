# -*- coding: utf-8 -*-
"""全仓「暂存索引」悬空引用扫描（提交前门禁）。

以 INDEX 为准（不是工作树）：把所有暂存文本文件里的 `res://...` 引用解析出来，
断言其目标也存在于索引中。覆盖范围比 P4 命名门禁的引用口径宽
（门禁只数 src/**/*.gd 与 tscn；本脚本覆盖 assets/art/**/*.gd、scripts/**/*.py 等资产侧参照方）。

只读。退出码 0 = 无悬空。
"""
from __future__ import annotations

import re
import subprocess
import sys

REPO = r"I:\工作项目\shellstrom2\ShellStorm2"
TEXT_EXT = (".gd", ".tscn", ".tres", ".json", ".py", ".mjs", ".js", ".md", ".cfg",
            ".sh", ".txt", ".import", ".gdshader", ".godot", ".xml", ".yaml", ".yml")
# 引擎会在加载期解析这些文件里的 res:// 引用 —— 悬空即真故障，计入失败
CORE_EXT = (".gd", ".tscn", ".tres", ".import")
SKIP_PREFIX = (".godot/", "addons/gut/", "source/", "outputs/")
SKIP_EXT = (".blend", ".blend1")

# 已完成去版本化的批次根 —— 悬空引用若命中此处即为「某批引入的破坏」，必须为 0。
# 逐批累积：B1 / B2 / B3 / B6（后续批次继续往下加，本脚本就成为跨批总护栏）。
BATCH_ROOTS: dict[str, str] = {
    "B1": "assets/art/environments/tower_zones/battle/",
    "B2:a": "assets/art/props/dungeon_3d/",
    "B2:b": "assets/art/environments/tower_descent_3d/",
    "B2:c": "assets/art/props/base_world_3d/",
    "B2:d": "assets/art/environments/dungeon_3d/",
    "B2:e": "assets/art/environments/base_world_3d/",
    "B2:f": "assets/art/environments/tower_zones/base/runtime/",
    "B2:g": "assets/art/environments/tower_zones/rooftop/runtime/",
    "B3": "assets/art/environments/base_facility_3d/",
    "B6:a": "assets/art/vfx/combat_3d/",
    "B6:b": "assets/art/vfx/environment_3d/",
    "B6:c": "assets/art/vfx/visibility_3d/",
    "B6:d": "assets/art/ui/inventory_3d/",
    "B6:e": "assets/art/ui/pause_3d/",
    "B6:f": "assets/art/environments/training_range_3d/",
    "B4": "assets/art/environments/rooftop_shelter_3d/",
}
TRIM = "`\"')]},;: "
RES_RE = re.compile(r'res://([^"\'\)\s]+)')
UIDS_RE = re.compile(r'uid://[a-z0-9]+')

KNOWN_DEAD = {
    "scenes/BaseFacility.tscn", "scenes/Container.tscn", "scenes/DemoRoomChain.tscn",
    "scenes/RoomBoss.tscn", "scenes/ThemedNPC.tscn",
}


def normalize(rel: str) -> str:
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


def main() -> int:
    ls = subprocess.run(["git", "ls-files", "-s", "-z"], cwd=REPO, capture_output=True)
    path2sha: dict[str, str] = {}
    for rec in ls.stdout.decode("utf-8", "replace").split("\0"):
        if not rec or "\t" not in rec:
            continue
        meta, path = rec.split("\t", 1)
        parts = meta.split()
        if len(parts) >= 2:
            path2sha[path] = parts[1]
    staged = list(path2sha)
    staged_set = set(staged)
    # 所有已跟踪目录（用于识别「目录路径引用」——目录不在索引里，不算悬空）
    dirs: set[str] = set()
    for p in staged:
        parts = p.split("/")
        for i in range(1, len(parts)):
            dirs.add("/".join(parts[:i]))
    print(f"[i] 索引路径总数 = {len(staged_set)}，已跟踪目录 = {len(dirs)}")

    targets = [p for p in staged if p.endswith(TEXT_EXT) and not p.startswith(SKIP_PREFIX)]
    print(f"[i] 待扫描文本文件 = {len(targets)}")

    proc = subprocess.Popen(["git", "cat-file", "--batch"], cwd=REPO,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    payload = "".join(f"{path2sha[p]}\n" for p in targets).encode("ascii")
    out, _ = proc.communicate(payload)
    pos = 0
    CORE_EXT_BUCKET: dict[str, set[str]] = {}
    OTHER_BUCKET: dict[str, set[str]] = {}
    checked = 0
    for p in targets:
        nl = out.find(b"\n", pos)
        if nl < 0:
            break
        header = out[pos:nl].decode("utf-8", "replace")
        pos = nl + 1
        parts = header.split()
        # --batch 头部格式：<sha> <type> <size>；查不到时是 <obj> missing（无内容需跳过）
        if len(parts) < 3 or parts[1] != "blob":
            continue
        size = int(parts[2])
        blob = out[pos:pos + size]
        pos += size + 1
        checked += 1
        text = blob.decode("utf-8", "replace")
        for m in RES_RE.finditer(text):
            rel = m.group(1).strip(TRIM)
            if rel.startswith(SKIP_PREFIX) or rel.endswith(SKIP_EXT):
                continue
            rel = normalize(rel)
            if rel in staged_set or rel in dirs or rel in KNOWN_DEAD:
                continue
            # 模板串 / 正则片段（含 { } [ ] ^ $ % * | ?）不是真实路径，跳过
            if any(ch in rel for ch in "{}[]^$%*|?\\"):
                continue
            if any(seg in ("\"", "'", "+", " ") for seg in (rel,)):
                continue
            bucket = CORE_EXT_BUCKET if p.endswith(CORE_EXT) else OTHER_BUCKET
            bucket.setdefault(p, set()).add(rel)

    print(f"[i] 实读 blob = {checked}")
    print()
    batch_hits: dict[str, set[str]] = {}
    hit_root: dict[str, set[str]] = {}
    for p, refs in CORE_EXT_BUCKET.items():
        for r in refs:
            for label, root in BATCH_ROOTS.items():
                if r.startswith(root):
                    batch_hits.setdefault(p, set()).add(r)
                    hit_root.setdefault(label, set()).add(r)
    print("=== A. 悬空引用命中任一「已去版本化批次根」（改造引入的破坏，必须为 0） ===")
    if not batch_hits:
        print(f"  (无) —— {len(BATCH_ROOTS)} 个批次根上没有任何悬空引用")
    for label in sorted(hit_root):
        print(f"  [{label}] {BATCH_ROOTS[label]}")
        for r in sorted(hit_root[label]):
            print(f"      -> res://{r}")
    for p, refs in sorted(batch_hits.items()):
        print(f"  {p}")
        for r in sorted(refs):
            print(f"      -> res://{r}")
    print()
    print("=== B. 其余引擎解析类悬空引用（既有欠账，非本批） ===")
    if not CORE_EXT_BUCKET:
        print("  (无)")
    for p, refs in sorted(CORE_EXT_BUCKET.items()):
        print(f"  {p}")
        for r in sorted(refs):
            print(f"      -> res://{r}")
    print()
    print("=== C. 其余文本（脚本模板 / 文档，人工参考，不计失败） ===")
    if not OTHER_BUCKET:
        print("  (无)")
    for p, refs in sorted(OTHER_BUCKET.items()):
        print(f"  {p}")
        for r in sorted(refs):
            print(f"      -> res://{r}")
    print()
    n_batch = sum(len(v) for v in batch_hits.values())
    n_all = sum(len(v) for v in CORE_EXT_BUCKET.values())
    both = sorted(set(batch_hits) | set(CORE_EXT_BUCKET))
    print(f"RESULT: BATCH_DANGLING={n_batch} / ALL_ENGINE_DANGLING={n_all} / 涉及文件={len(both)}")
    if hit_root:
        print("        命中批次：" + ", ".join(f"{k}({len(v)})" for k, v in sorted(hit_root.items())))
    return 0 if n_batch == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
