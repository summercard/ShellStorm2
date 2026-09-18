"""为入口安全房 v007 的 17 个房间自有资产包生成范式 B 的 runtime PackedScene。

范式 B（自包含可替换资产包）= 视觉 GLB + 稳定根节点 + 元数据，逐实例化：

  <slug>_root_top3d.tscn
    ├─ Node3D 根（承载全部 metadata 契约与房间摆位）
    └─ ImportedModel  ← 实例化 <slug>_visual_top3d.glb

**本包不含碰撞**，这是 asset_manifest.json 已声明的契约，不是遗漏：
  structural_geometry : "none: no wall/floor module, no collision shape"
  collision_status    : "未制作；玩法碰撞由 Godot 0.30m 结构代理负责"
  replacement_contract: "decoration only; must not change room size, 5m grid,
                         collision layer or navigation"
墙体/地面的通行与阻挡由引擎的 0.30m 结构代理持有（见 DungeonRoom3D 的槽位声明），
设施包若各自内嵌碰撞会与代理重复。摆位所需的包围盒与放置点已写进 metadata，
运行时需要障碍代理时可据此生成，不必回头改 GLB。

坐标与朝向：
  GLB 以「包并集包围盒的底面中心」为原点导出，世界朝向已烘进顶点。因此实例化时
  position 用 metadata/room_placement_position、rotation 保持 identity 即正位。
  不声明 forward_axis 这类需要额外推理的字段，只记录实际契约。

幂等：目标 tscn 已存在且内容一致则跳过；不同则覆盖（历史由 git 承担，不再产生 `*.bak_*`）。

运行：
  python build_package_prefabs_v007.py --version v007

版本参数：本脚本是入口安全房全部版本的**唯一 prefab 构建脚本**；版本号只写进
`metadata/asset_version` 与摘要，**Godot 侧 runtime 路径恒定、不含版本号**。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SUITE_DIR = HERE.parent.parent                  # .../entry_safe_room
SOURCE_DIR = SUITE_DIR.parent                   # .../source
BATTLE = SOURCE_DIR.parent                      # .../battle
ROOT = BATTLE.parents[4]                        # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

VERSION = grn.version_from_argv(HERE.parent.name)
VERSION_DIR = SUITE_DIR / VERSION
PACKAGES_DIR = VERSION_DIR / f"component_packages_{VERSION}"
RUNTIME_DIR = BATTLE / "runtime" / "entry_safe_room"
CATEGORY_DIRS = ("facilities", "decor", "support")

ASSET_ID = "ENV-BATTLE-L01-SAFE-ENTRY"
BLOCK_ID = "battle"
ROOM_ROOT = "res://assets/art/environments/tower_zones/battle"
SOURCE_BLEND = f"{ROOM_ROOT}/source/room_instances/entry_safe_room/{VERSION}/局内关卡01_入口安全房_15x15m_正式美术_{VERSION}.blend"

COLLISION_OWNER = "godot_0p30m_structural_proxy"


def fmt_vector(values) -> str:
    return "Vector3(%s)" % ", ".join(
        str(int(v)) if float(v).is_integer() else repr(round(float(v), 6)) for v in values
    )


def fmt_scalar(value) -> str:
    """Godot .tscn 字面量：字符串必须带引号，Vector3(...) 构造式不能带引号。"""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else repr(value)
    text = str(value)
    if text.startswith("Vector3("):
        return text
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def node_name(slug: str) -> str:
    return "Esr" + "".join(part.capitalize() for part in slug.split("_"))


def build_scene(pkg: dict, manifest: dict, category: str) -> str:
    slug = pkg["slug"]
    visual = f"{ROOM_ROOT}/components/entry_safe_room/{slug}/{grn.visual_glb_name(slug)}"
    manifest_path = (f"{ROOM_ROOT}/source/room_instances/entry_safe_room/{VERSION}/component_packages_{VERSION}"
                     f"/{category}/{slug}/asset_manifest.json")
    lo, hi = manifest["bounds"]
    origin = [(lo[i] + hi[i]) * 0.5 for i in range(2)] + [lo[2]]
    placement = [round(origin[0], 4), round(origin[2], 4), round(-origin[1], 4)]
    size = [round(hi[i] - lo[i], 4) for i in range(3)]
    godot_size = [size[0], size[2], size[1]]

    lines = ["[gd_scene load_steps=2 format=3]", ""]
    lines.append(f"; Stable AssetID: {ASSET_ID} · package {slug}")
    lines.append(f"; 入口安全房 {VERSION} · {category} · {manifest['name']}")
    lines.append("; 范式 B：视觉 GLB + 稳定根；房间摆位与契约写在 metadata。")
    lines.append("; 本包不含碰撞——玩法阻挡由引擎 0.30m 结构代理持有（见 asset_manifest.json 的")
    lines.append("; structural_geometry / collision_status / replacement_contract）。视觉资产不注册玩法组。")
    lines.append("")
    lines.append(f'[ext_resource type="PackedScene" path="{visual}" id="1_visual"]')
    lines.append("")
    lines.append(f'[node name="{node_name(slug)}" type="Node3D"]')

    meta = [
        ("asset_id", ASSET_ID),
        ("package_id", pkg["package_id"]),
        ("asset_version", VERSION),
        ("block_id", BLOCK_ID),
        ("category", "room_" + category),
        ("slug", slug),
        ("logic_id", slug),
        ("display_name_zh", manifest["name"]),
        ("source_blend", SOURCE_BLEND),
        ("source_collection", manifest["blender_collection"]),
        ("source_manifest", manifest_path),
        ("origin_contract", "bottom_center"),
        ("orientation_contract",
         "geometry authored in room-world orientation; instance with identity rotation"),
        ("bounds_size_m", fmt_vector(godot_size)),
        ("room_placement_position", fmt_vector(placement)),
        ("room_placement_note", "实例化时 position 用本值、rotation 保持 identity。"),
        ("preserve_authored_palette", True),
        ("visual_only", True),
        ("geometry_ownership", manifest["geometry_ownership"]),
        ("replacement_contract", manifest["replacement_contract"]),
        ("collision_owner", COLLISION_OWNER),
        ("collision_policy", "none_in_package"),
        ("collision_shape_count", 0),
        ("runtime_instantiation", "per_instance_prefab"),
        ("emission", bool(manifest["emission"])),
        ("animation", bool(manifest["animation"])),
        ("design_scope", manifest["design_scope"]),
        ("asset_ledger", manifest["asset_ledger"]),
    ]
    for key, value in meta:
        lines.append(f"metadata/{key} = {fmt_scalar(value)}")
    grn.require_version_metadata(meta, VERSION, script=Path(__file__).name)
    lines.append("")
    lines.append('[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]')
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    grn.guard_no_legacy_versioned(
        RUNTIME_DIR, script=Path(__file__).name, allow=grn.allow_legacy_from_argv()
    )
    summary = json.loads((HERE / f"export_packages_{VERSION}_summary.json").read_text(encoding="utf8"))
    results = {}
    written = 0
    for category in CATEGORY_DIRS:
        cat_dir = PACKAGES_DIR / category
        if not cat_dir.is_dir():
            continue
        for pkg_dir in sorted(cat_dir.iterdir()):
            if not pkg_dir.is_dir():
                continue
            manifest = json.loads((pkg_dir / "asset_manifest.json").read_text(encoding="utf8"))
            slug = manifest["slug"]
            if slug not in summary:
                raise SystemExit(f"{slug}: 不在 export_packages_{VERSION}_summary.json 里，先跑导出")
            out_dir = RUNTIME_DIR / slug
            out_dir.mkdir(parents=True, exist_ok=True)
            target = out_dir / grn.root_scene_name(slug)
            content = build_scene(manifest, manifest, category)
            if target.is_file() and target.read_text(encoding="utf-8") == content:
                print(f"SKIP  {slug}: 内容已一致（幂等）")
                results[slug] = {"status": "unchanged"}
                continue
            target.write_text(content, encoding="utf-8")
            written += 1
            print(f"WROTE {slug:24s} -> {target.name}")
            results[slug] = {"status": "written", "path": str(target), "shapes": 0}

    report = HERE / "package_prefab_report.json"
    report.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"PREFAB_REPORT_WRITTEN {report}")
    print(f"PREFAB_OK total={len(results)} written={written}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
