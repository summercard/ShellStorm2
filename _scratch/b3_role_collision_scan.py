#!/usr/bin/env python3
"""B3 开批前安全扫描：找出「同名收敛后不是同一资产」的组。

背景：deversion_batch 的 collapse 策略假设「同一稳定路径下的多版本 = 同一资产的
不同代，保留最高版本即可」。B3 预备文档把这个假设当成了 A 类（80 组，全部安全）。
但 corner_l_5m 是反例：v004（碰撞载体）与 v005（纯视觉壳）稳定路径相同，却是
**两个不同资产**，删掉任一个都会破运行时契约。

本脚本对 b3 根做穷举：按 stable_path 分组，对 `.tscn` 组比较「结构签名」——
节点名集合 + metadata 键集合 + 归一化后的 ext_resource 目标集合。
签名差异大 → 不是同一资产的代际，而是「同名不同物」，必须人工定代。

用法：python _scratch/b3_role_collision_scan.py
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]

spec = importlib.util.spec_from_file_location(
    "deversion_batch", PROJECT / "tools" / "asset_pipeline" / "deversion_batch.py"
)
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)
db.STRIP_DIR_VERSION = True  # B3 语义

ROOT = PROJECT / "assets" / "art" / "environments" / "base_facility_3d"

NODE_RE = re.compile(r'\[node name="([^"]+)"')
META_RE = re.compile(r"^metadata/([A-Za-z0-9_]+)", re.M)
EXT_RE = re.compile(r'\[ext_resource[^\]]*path="res://([^"]+)"')
SUB_RE = re.compile(r"\[sub_resource type=\"([A-Za-z0-9_]+)\"")


def signature(path: Path, rel: str) -> dict:
    """结构签名：不同资产之间差异明显，同一资产的相邻代之间高度相似。"""
    text = path.read_text(encoding="utf8", errors="replace")
    nodes = set(NODE_RE.findall(text))
    metas = set(META_RE.findall(text))
    exts = set()
    for e in EXT_RE.findall(text):
        exts.add(db.stable_path(e))  # 归一化：忽略被引资产的版本差异
    subs = set(SUB_RE.findall(text))
    body = re.sub(r'\[node name="[^"]+"[^\]]*\]', "", text)
    body = re.sub(r";.*", "", body)
    body = re.sub(r"\s+", " ", body).strip()
    return {
        "nodes": nodes,
        "metas": metas,
        "exts": exts,
        "subs": subs,
        "roles": {text.count('type="StaticBody3D"'), len(subs)},
        "visual_only": "visual_only = true" in text,
        "body_len": len(body),
        "body": body,
    }


def main() -> int:
    groups: dict[str, list[str]] = {}
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(PROJECT).as_posix()
        if "/source/" in rel or db.BACKUP.search(p.name):
            continue
        if not db.RUN_ASSET.search(p.name):
            continue
        groups.setdefault(db.stable_path(rel), []).append(rel)

    multi = {k: v for k, v in groups.items() if len(v) > 1}
    print(f"b3 根下稳定路径组 {len(groups)} 个，其中多成员组 {len(multi)} 个\n")

    suspicious: list[tuple[str, list[str]]] = []
    for stable, members in sorted(multi.items()):
        tscns = [m for m in members if m.endswith(".tscn")]
        if len(tscns) < 2:
            continue
        sigs = {m: signature(PROJECT / m, m) for m in tscns}
        node_sets = {m: frozenset(s["nodes"]) for m, s in sigs.items()}
        # 判据：节点名集合不完全一致，或 metadata 键集合差异 >= 2 个
        base = next(iter(node_sets.values()))
        node_mismatch = any(v != base for v in node_sets.values())
        meta_mismatch = False
        msets = [frozenset(s["metas"]) for s in sigs.values()]
        if msets:
            union = set().union(*msets)
            inter = msets[0].intersection(*msets[1:])
            if len(union) - len(inter) >= 2:
                meta_mismatch = True
        if node_mismatch or meta_mismatch:
            suspicious.append((stable, tscns))

    if not suspicious:
        print("未发现「同名不同物」可疑组 —— collapse 保留最高版本安全。")
        return 0

    print(f"⚠️ 可疑「同名不同物」组 {len(suspicious)} 个：\n")
    for stable, members in suspicious:
        print(f"--- {stable}")
        for m in members:
            s = signature(PROJECT / m, m)
            print(f"    成员 {m}")
            print(f"      节点: {sorted(s['nodes'])}")
            print(f"      元数据键: {sorted(s['metas'])}")
            print(f"      子资源: {sorted(s['subs'])}  visual_only={s['visual_only']}")
        print()

    # 附：GLB 多成员组（一般就是代际，列出仅供核对）
    glb_groups = {
        k: v for k, v in multi.items() if sum(1 for m in v if m.endswith(".glb")) > 1
    }
    print(f"（参考）GLB 多代并存组 {len(glb_groups)} 个：")
    for k, v in sorted(glb_groups.items()):
        print(f"    {k}\n        {[x.split('/')[-1] for x in v]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
