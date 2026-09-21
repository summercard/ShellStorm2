"""把 99F 剩余设施的手工摆位固化成可重放的坐标记录。

背景（为什么会需要这个文件）
----------------------------
`env_base99_remaining_facilities_root_top3d.tscn` 里 45 个顶层子节点，
理论上应全部保持 identity（位置由组件 GLB 自己烘死 / 由 facility 包装包的
pivot 决定）。业主在 Godot 编辑器里手工微调后，位移量只活在这个 .tscn 上，
而所有重生成通道（import_base_facility_*.py / deversion_batch.py /
export_base_facility_latest.py）都会覆盖它，反向固化通道
（build_base_facility_runtime_layout_v002.py）又只吃 8 个交互设施 + 结构件、
不含这 45 个包。于是手改随时会被下一次重导静默抹掉。

结论与口径（业主 2026-09-21 决定）
----------------------------------
**不写回 Blender。** 把坐标记下来，下次改 Blender 母版时按这份记录换位置即可。

两个必须记住的机制（都是本脚本依赖的实测事实，不是推断）
--------------------------------------------------------
1. `.tscn` 里 `Transform3D` 的 12 个数是 **行主序**：
   `(m00,m01,m02, m10,m11,m12, m20,m21,m22, ox,oy,oz)`。
   绕 Y 的偏航角因此是 `atan2(m02, m00)`。
   （反证：`rotation_degrees.y=+90` 的 basis.x=(0,0,-1)，行主序首三位是 (0,0,1)。）
2. 父场景节点上的 `transform` 对**实例根节点**是**覆盖**，不是叠加。
   - 普通包（`*_root_top3d.tscn`）：预制体根在原点是 identity ⇒ 覆盖值 = 纯位移量。
   - facility 包装包（`*_facility_top3d.tscn`）：预制体根自带 pivot（件心绝对坐标）
     ⇒ 覆盖值 = **新的绝对 pivot**，实际位移量 = 覆盖值 − 原 pivot。
   （反证：武器工作台原 pivot z=3.4、覆盖为 5.3589，探针实测几何中心 z=5.3589；
     若为叠加应是 8.7589。）

坐标换算（Godot ←→ Blender，glTF 契约）
---------------------------------------
    Godot (gx, gy, gz)  =  Blender (bx, bz, -by)
    Blender (bx, by, bz) =  Godot  (gx, -gz, gy)
    Godot 绕 +Y 的偏航角 ≡ Blender 绕 +Z 的同值欧拉角
（仅在本批资产「只有偏航、无缩放」时成立；当前 45 件全部满足。）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

PROJECT_DEFAULT = Path(__file__).resolve().parents[2]
SCENE_REL = ("assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/"
             "env_base99_remaining_facilities_root_top3d.tscn")
MANIFEST_REL = "assets/art/environments/base_facility_3d/source/env_base99_remaining_facilities_v021_manifest.json"
OUT_BASENAME = "env_base99_remaining_facilities_v021_placement"

# 本批资产的已知机制说明，写进记录里给下一个改 .blend 的人看。
MECHANISM = {
    "plain_root": "预制体根在原点保持 identity，几何在组件 GLB 内部烘成绝对坐标 ⇒ 覆盖值即纯位移量。",
    "facility_wrapper": "预制体根 Area3D 自带 pivot（= 件心绝对坐标），SourcePackage 子节点用 −pivot 抵消 ⇒ 覆盖值即新的绝对 pivot，实际位移 = 覆盖值 − 原 pivot。",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_scene_nodes(text: str) -> list[dict]:
    """按出现顺序返回全部节点；顶层节点 parent == '.'。"""
    nodes: list[dict] = []
    current: dict | None = None
    for line in text.split("\n"):
        if line.startswith("[node "):
            name = re.search(r'name="([^"]+)"', line)
            parent = re.search(r'parent="([^"]*)"', line)
            inst = re.search(r'instance=ExtResource\("([^"]+)"\)', line)
            current = {
                "name": name.group(1) if name else "",
                "parent": parent.group(1) if parent else None,
                "instance": inst.group(1) if inst else None,
                "transform": None,
                "position": None,
                "rotation": None,
            }
            nodes.append(current)
            continue
        if current is None:
            continue
        for key in ("transform", "position", "rotation"):
            match = re.match(r"^%s = (.+)$" % key, line)
            if match:
                current[key] = match.group(1)
    return nodes


def parse_ext_resources(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for match in re.finditer(r"\[ext_resource[^\]]*\]", text):
        chunk = match.group(0)
        rid = re.search(r'id="([^"]+)"', chunk)
        path = re.search(r'path="([^"]+)"', chunk)
        if rid and path:
            out[rid.group(1)] = path.group(1)
    return out


def parse_vec3(text: str | None) -> list[float] | None:
    if not text:
        return None
    match = re.search(r"Vector3\(([^)]*)\)", text)
    if not match:
        return None
    return [float(x) for x in match.group(1).split(",")]


def parse_transform(text: str | None) -> dict | None:
    """行主序 12 数 → 原点 + 偏航角 + 各轴（用于核对是否存在缩放/俯仰）。"""
    if not text:
        return None
    body = re.search(r"Transform3D\(([^)]*)\)", text)
    if not body:
        return None
    nums = [float(x) for x in body.group(1).split(",")]
    if len(nums) != 12:
        raise ValueError("Transform3D 参数个数异常: %d" % len(nums))
    m = [nums[0:3], nums[3:6], nums[6:9]]
    origin = nums[9:12]
    yaw = math.degrees(math.atan2(m[0][2], m[0][0]))
    col = [[m[r][c] for r in range(3)] for c in range(3)]
    lengths = [math.sqrt(sum(v * v for v in col[k])) for k in range(3)]
    return {
        "origin": origin,
        "yaw_deg": yaw,
        "basis_rows": m,
        "column_lengths": lengths,
        "orthonormal_unscaled": all(abs(x - 1.0) < 1e-4 for x in lengths),
    }


def head_version(root: Path, rel: str) -> str | None:
    proc = subprocess.run(["git", "show", "HEAD:" + rel], cwd=root, capture_output=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8")


def parse_probe_log(path: Path) -> dict[str, dict]:
    """读探针的 ROW / DUP_OWN 行 → {节点名: {T, yaw, center, size, meshes}}。

    `DUP_OWN` 优先：它是「该顶层节点**自持**几何（排除同名嵌套份）」的世界 AABB，
    而 `ROW` 对带嵌套份的节点是**整棵子树并集**（水缸会被并成 6 个那么宽）。
    """
    rows: dict[str, dict] = {}

    def vec(text: str | None):
        if not text or text == "n/a":
            return None
        match = re.search(r"\(([^)]*)\)", text)
        return [float(x) for x in match.group(1).split(",")] if match else None

    for line in path.read_text(encoding="utf-8", errors="replace").split("\n"):
        parts = line.split("\t")
        if line.startswith("DUP_OWN\t"):
            record = rows.setdefault(parts[1], {"name": parts[1], "own_geometry": True})
            for part in parts[2:]:
                if part.startswith("world_center="):
                    record["envelope_center"] = vec(part[13:])
                elif part.startswith("world_size="):
                    record["envelope_size"] = vec(part[11:])
            continue
        if not line.startswith("ROW\t"):
            continue
        record = rows.setdefault(parts[1], {"name": parts[1]})
        for part in parts[2:]:
            if part.startswith("T="):
                record["probe_T"] = vec(part[2:])
            elif part.startswith("yaw="):
                record["probe_yaw_deg"] = float(part[4:])
            elif part.startswith("center="):
                if not record.get("own_geometry"):
                    record["envelope_center"] = vec(part[7:])
            elif part.startswith("size="):
                if not record.get("own_geometry"):
                    record["envelope_size"] = vec(part[5:])
            elif part.startswith("meshes="):
                record["mesh_count"] = int(part[7:])
    return rows


def parse_probe_dups(path: Path) -> list[dict]:
    """读探针的 DUP 行 → 顶层节点内部的多份同名实例清单。

    探针口径：`DUP` 行同时给
      `world_center/world_size` = **该份自身**几何的世界 AABB（排除更深的同名份）
      `subtree_center/size`    = 含更深同名份的整棵子树并集
      `world_origin`           = 该份节点原点的世界坐标
    ⚠️ 几何件心才是可靠落位：部分包的 GLB 顶点直接烘了绝对坐标，
    节点原点与几何位置可以差十几米（蓄电池/水箱都是这样）。
    """
    dups: list[dict] = []

    def vec(text: str | None):
        if not text:
            return None
        match = re.search(r"\(([^)]*)\)", text)
        return [float(x) for x in match.group(1).split(",")] if match else None

    for line in path.read_text(encoding="utf-8", errors="replace").split("\n"):
        if not line.startswith("DUP\t"):
            continue
        record: dict = {"node_name": line.split("\t")[1]}
        for part in line.split("\t")[2:]:
            if part.startswith("depth="):
                record["nest_depth"] = int(part[6:])
            elif part.startswith("dup_local="):
                record["dup_local_godot"] = vec(part[10:])
            elif part.startswith("world_origin="):
                record["world_origin_godot"] = vec(part[13:])
            elif part.startswith("yaw="):
                record["yaw_deg"] = float(part[4:])
            elif part.startswith("world_center="):
                record["world_center_godot"] = vec(part[13:])
            elif part.startswith("world_size="):
                record["world_size_godot"] = vec(part[11:])
            elif part.startswith("meshes="):
                record["mesh_count"] = int(part[7:])
            elif part.startswith("subtree_center="):
                record["subtree_center_godot"] = vec(part[15:])
            elif part.startswith("subtree_size="):
                record["subtree_size_godot"] = vec(part[13:])
        record["world_center_blender"] = to_blender(record.get("world_center_godot"))
        record["world_origin_blender"] = to_blender(record.get("world_origin_godot"))
        dups.append(record)
    return dups


def to_blender(godot: list[float] | None) -> list[float] | None:
    if godot is None:
        return None
    gx, gy, gz = godot
    return [gx, -gz, gy]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=PROJECT_DEFAULT)
    parser.add_argument("--probe-log", type=Path, required=True,
                        help="探针 dump（tests/verification/probe_base99_remaining_placement）的输出文件")
    args = parser.parse_args()
    root = args.project.resolve()

    scene_path = root / SCENE_REL
    scene_text = scene_path.read_text(encoding="utf-8")
    head_text = head_version(root, SCENE_REL)
    ext = parse_ext_resources(scene_text)
    nodes = parse_scene_nodes(scene_text)
    top = [n for n in nodes if n["parent"] == "."]
    head_top = {n["name"]: n for n in parse_scene_nodes(head_text) if n["parent"] == "."} if head_text else {}

    probe = parse_probe_log(args.probe_log)
    manifest = json.loads((root / MANIFEST_REL).read_text(encoding="utf-8"))
    by_slug = {p["slug"]: p for p in manifest["packages"]}

    items: list[dict] = []
    for index, node in enumerate(top, 1):
        prefab = ext.get(node["instance"] or "", "")
        slug = prefab.replace("res://", "").split("/")[-2] if prefab else ""
        is_wrapper = "_facility_top3d" in prefab
        tf = parse_transform(node["transform"])
        pivot_prefab = None
        if is_wrapper and prefab:
            prefab_path = root / prefab.replace("res://", "")
            if prefab_path.is_file():
                sub = parse_scene_nodes(prefab_path.read_text(encoding="utf-8"))
                root_node = next((n for n in sub if n["parent"] is None), None)
                pivot_prefab = parse_vec3(root_node["position"]) if root_node else None

        head_node = head_top.get(node["name"])
        head_tf = parse_transform(head_node["transform"]) if head_node else None
        # 只在 HEAD **真的声明了**变换时才合成 head_tf。
        # 否则「HEAD 无变换」会被当成「HEAD 有 identity 变换」，于是 tf 为 None 的节点
        # 被误判成 override_removed、本期新增覆盖被误判成 edited_existing。
        head_declares_tf = head_node is not None and bool(
            head_node["transform"] or head_node["position"] or head_node["rotation"])
        if head_tf is None and head_declares_tf:
            head_pos = parse_vec3(head_node["position"]) or [0.0, 0.0, 0.0]
            head_rot = parse_vec3(head_node["rotation"]) or [0.0, 0.0, 0.0]
            head_tf = {"origin": head_pos, "yaw_deg": math.degrees(head_rot[1]),
                       "basis_rows": None, "column_lengths": None, "orthonormal_unscaled": True}

        if tf is None and head_tf is None:
            status = "identity"
        elif tf is not None and head_tf is None:
            status = "new_override"
        elif tf is not None and head_tf is not None:
            same_pos = all(abs(a - b) < 1e-6 for a, b in zip(tf["origin"], head_tf["origin"]))
            same_yaw = abs(tf["yaw_deg"] - head_tf["yaw_deg"]) < 1e-4
            status = "unchanged_serialization_only" if (same_pos and same_yaw) else "edited_existing"
        else:
            status = "override_removed"

        # 实际位移量：普通包 = 覆盖值；facility 包装包 = 覆盖值 − 预制体 pivot。
        delta = None
        note = MECHANISM["plain_root"]
        if tf is not None:
            if is_wrapper:
                note = MECHANISM["facility_wrapper"]
                if pivot_prefab is not None:
                    delta = [tf["origin"][k] - pivot_prefab[k] for k in range(3)]
                else:
                    delta = list(tf["origin"])
            else:
                delta = list(tf["origin"])

        probe_row = probe.get(node["name"], {})
        # 两个不同口径，别混：
        #   delta           = 相对**预制体基准姿态**的绝对位移（改 Blender 母版时按这个换位置）
        #   revision_delta  = 相对 **HEAD** 的本次修订位移（判别「这一版谁动了」）
        # 关键：HEAD 没有覆盖记录时，基准是「预制体自然姿态」即位移 0，
        # 不是 origin=(0,0,0) —— 对自带 pivot 的 facility 包装包这两者差一个 pivot，
        # 直接相减会把「空操作覆盖」误报成「本次挪了一个 pivot 那么远」。
        if head_tf is None:
            head_delta = None
        elif is_wrapper and pivot_prefab is not None:
            head_delta = [head_tf["origin"][k] - pivot_prefab[k] for k in range(3)]
        else:
            head_delta = list(head_tf["origin"])
        if delta is None:
            revision_delta = None
        elif head_delta is None:
            revision_delta = list(delta)
        else:
            revision_delta = [delta[k] - head_delta[k] for k in range(3)]
        moved = revision_delta is not None and any(abs(v) > 1e-6 for v in revision_delta)

        items.append({
            "index": index,
            "node_name": node["name"],
            "package_slug": slug,
            "bpk_asset_id": by_slug.get(slug, {}).get("display_name") and
                            ("BPK-BASE99-" + slug.upper().replace("_", "-")) or None,
            "blender_source_collection": by_slug.get(slug, {}).get("source_collection"),
            "prefab": prefab,
            "wrapper_kind": "facility_wrapper" if is_wrapper else "plain_root",
            "mechanism": note,
            "status": status,
            "moved_in_this_revision": moved,
            "scene_node_transform_godot": tf["origin"] if tf else [0.0, 0.0, 0.0],
            "scene_node_yaw_deg": tf["yaw_deg"] if tf else 0.0,
            "prefab_root_pivot_godot": pivot_prefab,
            "delta_godot": delta,
            "delta_blender": to_blender(delta),
            "revision_delta_godot": revision_delta,
            "revision_delta_blender": to_blender(revision_delta),
            "delta_yaw_deg": (tf["yaw_deg"] - head_tf["yaw_deg"]) if (tf and head_tf) else (tf["yaw_deg"] if tf else 0.0),
            "envelope_center_godot": probe_row.get("envelope_center"),
            "envelope_size_godot": probe_row.get("envelope_size"),
            "envelope_center_blender": to_blender(probe_row.get("envelope_center")),
            "mesh_count": probe_row.get("mesh_count"),
            "scale_uniform_one": (tf["orthonormal_unscaled"] if tf else True),
        })

    moved_items = [i for i in items if i["moved_in_this_revision"]]
    noop_items = [i for i in items if i["status"] == "new_override" and not i["moved_in_this_revision"]]
    # 顶层节点内部的**多份实例**。业主 2026-09-21 明确：这些是有意摆位，不是误复制。
    nested = parse_probe_dups(args.probe_log)
    nested_groups: dict[str, list[dict]] = {}
    for record in nested:
        nested_groups.setdefault(record["node_name"], []).append(record)
    envelope_by_name = {i["node_name"]: i for i in items}
    nested_summary = [
        {
            "node_name": name,
            "extra_instance_count": len(group),
            "original_center_godot": envelope_by_name.get(name, {}).get("envelope_center_godot"),
            "extra_instances": sorted(group, key=lambda r: r.get("nest_depth") or 0),
        }
        for name, group in nested_groups.items()
    ]
    payload = {
        "record_id": "ENV-BASE99-REMAINING-FACILITIES-V021::placement_authority",
        "asset_id": manifest["asset_id"],
        "asset_version": manifest["version"],
        "authority": "runtime .tscn 手工摆位为布局真源；本文件是它的机器可读固化。不写回 Blender。",
        "reason": "该 .tscn 被所有重生成通道覆盖，而反向固化通道不含这 45 个包 ⇒ 手改会静默丢失。",
        "revision": {
            "date": "2026-09-21",
            "author": "业主（编辑器内手工调整）",
            "recorded_by": "摩斯拉",
        },
        "scene_file": SCENE_REL,
        "scene_sha256": sha256(scene_path),
        "scene_sha256_at_head": hashlib.sha256(head_text.encode("utf-8")).hexdigest() if head_text else None,
        "scene_node_line_count": scene_text.count("\n[node "),
        "probe_log": str(args.probe_log),
        "coordinate_convention": {
            "godot_to_blender": "bx = gx ; by = -gz ; bz = gy",
            "blender_to_godot": "gx = bx ; gy = bz ; gz = -by",
            "yaw": "Godot 绕 +Y 的偏航角 ≡ Blender 绕 +Z 的同值欧拉角（本批仅偏航、无缩放）",
        },
        "totals": {
            "top_level_nodes": len(items),
            "identity": sum(1 for i in items if i["status"] == "identity"),
            "new_override": sum(1 for i in items if i["status"] == "new_override"),
            "edited_existing": sum(1 for i in items if i["status"] == "edited_existing"),
            "unchanged_serialization_only": sum(1 for i in items if i["status"] == "unchanged_serialization_only"),
            "override_removed": sum(1 for i in items if i["status"] == "override_removed"),
            "moved_in_this_revision": len(moved_items),
            "noop_override": len(noop_items),
            "extra_nested_instances": len(nested),
        },
        "nested_instances": nested_summary,
        "items": items,
    }

    out_json = root / "assets/art/environments/base_facility_3d/source" / (OUT_BASENAME + ".json")
    out_md = root / "assets/art/environments/base_facility_3d/source" / (OUT_BASENAME + ".md")

    text = json.dumps(payload, ensure_ascii=False, indent=1).replace("\n", "\r\n") + "\r\n"
    out_json.write_bytes(text.encode("utf-8"))

    lines: list[str] = []
    lines.append("# 99F 基地 · 剩余非门非墙设施 —— 手工摆位坐标记录")
    lines.append("")
    lines.append("> 真源：`%s`（%d 个顶层子节点，全文 %d 个 `[node ` 行）。"
                 % (SCENE_REL, len(items), payload["scene_node_line_count"]))
    lines.append("> 该文件的 SHA-256：`%s`" % payload["scene_sha256"])
    lines.append("> 记录日期：%s ｜ 记录人：摩斯拉 ｜ 改动者：业主（编辑器内手工调整）" % payload["revision"]["date"])
    lines.append("")
    lines.append("**这是一份快照，不是活引用。** 记录时该 .tscn 正被 Godot 编辑器打开着，"
                 "SHA 只对上面这一版成立；文件再被保存一次（哪怕只挪 1 cm）"
                 "本记录就不再逐字对应，需要重跑 "
                 "`tools/asset_pipeline/record_base99_remaining_facility_placement.py`。")
    lines.append("")
    lines.append("**为什么不写回 Blender**：这个 .tscn 会被所有重生成通道覆盖"
                 "（`import_base_facility_*.py` / `deversion_batch.py` / `export_base_facility_latest.py`），"
                 "而反向固化通道 `build_base_facility_runtime_layout_v002.py` 只吃 8 个交互设施 + 结构件、"
                 "不含这 45 个包。所以手改的唯一保命方式就是**把坐标记下来**，"
                 "下次改 Blender 母版时按本表换位置。")
    lines.append("")
    lines.append("## 两条必须记住的机制（实测，非推断）")
    lines.append("")
    lines.append("1. `.tscn` 里 `Transform3D` 的 12 个数是**行主序** "
                 "`(m00,m01,m02, m10,m11,m12, m20,m21,m22, ox,oy,oz)`，绕 Y 的偏航角是 `atan2(m02, m00)`。")
    lines.append("2. 父场景节点上的 `transform` 对实例根节点是**覆盖**而非叠加：")
    lines.append("   - 普通包（`*_root_top3d.tscn`）：预制体根为 identity ⇒ 覆盖值就是纯位移量。")
    lines.append("   - facility 包装包（`*_facility_top3d.tscn`）：预制体根自带 pivot"
                 "（= 件心绝对坐标）⇒ 覆盖值是**新的绝对 pivot**，实际位移 = 覆盖值 − 原 pivot。")
    lines.append("")
    lines.append("## 坐标换算")
    lines.append("")
    lines.append("```")
    lines.append("Godot  (gx, gy, gz)  ←  Blender (bx, bz, -by)")
    lines.append("Blender(bx, by, bz)  ←  Godot   (gx, -gz, gy)")
    lines.append("Godot 绕 +Y 偏航角  ≡  Blender 绕 +Z 同值欧拉角")
    lines.append("```")
    lines.append("")
    lines.append("## 本次修订有实际位移的 %d 件" % len(moved_items))
    lines.append("")
    lines.append("两列 Δ 是两个不同口径，别混：")
    lines.append("")
    lines.append("- **相对预制体基准 Δ**：这件相对 Blender 母版原位置整体挪了多少。"
                 "「在 Blender 里把它挪到运行时现在的位置」用这一列。")
    lines.append("- **本次修订 Δ**：相对 HEAD 这一版新挪了多少（HEAD 未覆盖时基准为 (0,0,0)）。"
                 "只想知道「刚才动了什么」看这一列。")
    lines.append("")
    lines.append("| # | 节点名 | 组件 slug | Blender 源集合 | 相对预制体基准 Δ（Godot） | 同左（Blender） | 本次修订 Δ（Godot） | 偏航 Δ° | 件心（Godot 实测） | 件心（Blender） |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for item in moved_items:
        lines.append("| %d | %s | `%s` | `%s` | `%s` | `%s` | `%s` | %+.3f | `%s` | `%s` |" % (
            item["index"], item["node_name"], item["package_slug"],
            item["blender_source_collection"] or "",
            _fmt(item["delta_godot"]), _fmt(item["delta_blender"]),
            _fmt(item["revision_delta_godot"]), item["delta_yaw_deg"],
            _fmt(item["envelope_center_godot"]), _fmt(item["envelope_center_blender"])))
    lines.append("")
    if nested_summary:
        lines.append("## 有意多份实例：同一资产在同一节点下被摆了多份（%d 份）" % len(nested))
        lines.append("")
        lines.append("这些是**自嵌套的同名子节点**（父名 = 节点名，即 `parent=\"X/X\"` 形式），"
                     "顶层的逐子节点循环看不到它们，只有专门的 DUP 扫描能发现。"
                     "全项目 257 个 `.tscn` 里只有本文件有这种结构。")
        lines.append("")
        lines.append("**业主 2026-09-21 确认：这是有意摆位，不是误复制。** "
                     "因此 Blender 侧要按同样的份数与位置落地 —— 把同一源件复制 N 份，"
                     "按下面每份的坐标摆放，而**不要**当成多余实例清理掉。")
        lines.append("")
        lines.append("⚠ 落位口径：**以「该份件心（Godot 实测）」为准**。部分包的 GLB 顶点直接烘了"
                     "绝对坐标，节点原点与几何位置能差十几米（蓄电池/水箱都是这样），"
                     "所以「世界原点」一列只能当参考，不能当摆放坐标。")
        lines.append("")
        lines.append("| 节点名 | 原件件心（Godot） | 多出份数 | 深度 | 局部增量（Godot） | 世界原点（Godot） | 偏航° | 该份件心（Godot） | 该份件心（Blender） | 网格数 |")
        lines.append("|---|---|---|---|---|---|---|---|---|---|")
        for group in nested_summary:
            for record in group["extra_instances"]:
                lines.append("| %s | `%s` | %d | %d | `%s` | `%s` | %+.3f | `%s` | `%s` | %s |" % (
                    group["node_name"], _fmt(group["original_center_godot"]),
                    group["extra_instance_count"], record.get("nest_depth") or 0,
                    _fmt(record.get("dup_local_godot")), _fmt(record.get("world_origin_godot")),
                    record.get("yaw_deg") or 0.0,
                    _fmt(record.get("world_center_godot")), _fmt(record.get("world_center_blender")),
                    record.get("mesh_count")))
        lines.append("")
    if noop_items:
        lines.append("## 覆盖值与预制体 pivot 等值的 %d 件（空操作，但有副作用）" % len(noop_items))
        lines.append("")
        lines.append("位移量为 0，画面不变。**但副作用是真的**：父场景从此硬覆盖该 pivot，"
                     "以后改包装包预制体的 pivot 不会再传导到这些件。")
        lines.append("")
        lines.append("| # | 节点名 | 组件 slug | 覆盖值 / 原 pivot（Godot） |")
        lines.append("|---|---|---|---|")
        for item in noop_items:
            lines.append("| %d | %s | `%s` | `%s` |" % (
                item["index"], item["node_name"], item["package_slug"],
                _fmt(item["scene_node_transform_godot"])))
        lines.append("")
    lines.append("## 全部 %d 个顶层子节点" % len(items))
    lines.append("")
    lines.append("| # | 节点名 | 组件 slug | 状态 | 节点变换 T（Godot） | 偏航° | Δ（Godot） | 件心（Godot 实测） |")
    lines.append("|---|---|---|---|---|---|---|---|")
    status_label = {
        "identity": "无变换",
        "new_override": "本期新增覆盖",
        "unchanged_serialization_only": "本期未变（仅格式）",
        "edited_existing": "本期改动",
        "override_removed": "覆盖被移除",
    }
    for item in items:
        lines.append("| %d | %s | `%s` | %s | `%s` | %+.3f | `%s` | `%s` |" % (
            item["index"], item["node_name"], item["package_slug"],
            status_label.get(item["status"], item["status"]),
            _fmt(item["scene_node_transform_godot"]), item["scene_node_yaw_deg"],
            _fmt(item["delta_godot"]) if item["delta_godot"] else "—",
            _fmt(item["envelope_center_godot"])))
    lines.append("")

    out_md.write_bytes(("\r\n".join(lines) + "\r\n").encode("utf-8"))

    print("PLACEMENT_RECORD_OK")
    print("  json      :", out_json.relative_to(root))
    print("  md        :", out_md.relative_to(root))
    print("  scene_sha :", payload["scene_sha256"])
    print("  node_lines:", payload["scene_node_line_count"])
    print("  totals    :", json.dumps(payload["totals"], ensure_ascii=False))
    for item in moved_items:
        print("   MOVED  %-34s Δ自基准=%s  本次Δ=%s  yawΔ=%+.3f  → %s" % (
            item["node_name"], _fmt(item["delta_godot"]),
            _fmt(item["revision_delta_godot"]), item["delta_yaw_deg"],
            _fmt(item["envelope_center_godot"])))
    for item in noop_items:
        print("   NOOP   %-34s 覆盖值 == 预制体 pivot %s" % (
            item["node_name"], _fmt(item["scene_node_transform_godot"])))
    for group in nested_summary:
        print("   NESTED %-28s 多出 %d 份 原件件心=%s" % (
            group["node_name"], group["extra_instance_count"],
            _fmt(group["original_center_godot"])))
        for record in group["extra_instances"]:
            print("            depth=%d 该份件心=%s yaw=%+.3f 网格数=%s" % (
                record.get("nest_depth") or 0, _fmt(record.get("world_center_godot")),
                record.get("yaw_deg") or 0.0, record.get("mesh_count")))
    return 0


def _fmt(vec: list[float] | None) -> str:
    if vec is None:
        return "—"
    return "(%.4f, %.4f, %.4f)" % (vec[0], vec[1], vec[2])


if __name__ == "__main__":
    sys.exit(main())
