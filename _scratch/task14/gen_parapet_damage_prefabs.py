"""One-off generator: 天台女儿墙破损变体的 Godot prefab (.tscn) 与 .import。

约定（沿用 prp_rooftop_parapet_5m.tscn / env_rooftop_ref_parapet_top3d.glb.import）：
- .tscn 用 CRLF；.import 用 LF。
- .import 的 dest_files 文件名 = md5("res://<glb 路径>") + ".scn"。
- uid 从 Godot 的 base32 字母表随机取 13 位，并对全工程已用 uid 去重。

跑法：python _scratch/task14/gen_parapet_damage_prefabs.py
"""

from __future__ import annotations

import hashlib
import random
import re
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
GLB_DIR = PROJECT / "assets/art/environments/tower_zones/rooftop/components"
PROP_DIR = PROJECT / "assets/art/props/dungeon_3d"
REF_BLEND = (
    "res://assets/art/environments/tower_zones/rooftop/source/"
    "reference_components/v002/天台区块_参考组件库_v002.blend"
)
AUTHOR_SCRIPT = (
    "res://assets/art/environments/tower_zones/rooftop/source/"
    "author_env_rooftop_parapet_damage_v001.py"
)
PARENT_ASSET_ID = "ENV-ROOFTOP-REF-PARAPET"

VARIANTS = [
    {
        "key": "a",
        "suffix": "A",
        "kind": "crown_spall",
        "label": "崩顶",
        "desc": "压顶顶部被削 3 道豁口、中段崩落，断裂面粗化；下半身与两端头带完整。",
    },
    {
        "key": "b",
        "suffix": "B",
        "kind": "through_breach",
        "label": "贯穿",
        "desc": "墙身中段被打穿 2 个带放射裂纹的贯穿洞，可透视到墙外；洞缘粗化。",
    },
    {
        "key": "c",
        "suffix": "C",
        "kind": "base_collapse",
        "label": "塌脚",
        "desc": "墙身中段整体塌到约 0.5m 残根、基座阳角被啃缺口，是最重的一档破损。",
    },
]

TSCN_TEMPLATE = """[gd_scene load_steps=2 format=3]

; 5m 天台女儿墙直段 · 破损{suffix}（{label}）（天台参考组件库 v002 程序化派生件）
; 正式美术：tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_{key}_top3d.glb
;   5.00m 长 × 1.80m 高 × 0.50m 厚；底面中心原点（几何 Y=0..1.80）。
; 来源：本件不是新造型，而是 intact 件（ENV-ROOFTOP-REF-PARAPET）的程序化破损派生：
;   脚本 author_env_rooftop_parapet_damage_v001.py 把 intact 网格按「积木」（22 块
;   闭合倒角块：基座 + 分隔带 + 10 块墙身 + 10 块压顶）拆开，只对与破损区相交的
;   积木做逐块布尔剔料，再合并；破损面 UV 钳回色盘色块，故不换材质、不掉色。
; 破损口径（{kind} / {label}）：{desc}
; 拼接契约（用户要求「需要能接起来」）：破损只发生在中段，两端头带 |x|>=2.05m 与
;   intact 件逐位相同；包络仍是 5.00×0.50×1.80、原点仍是底面中心。
;   ⇒ 可与 intact 件 / 另两件破损件沿任一边、任意顺序对接，接头无缝且槽位相位不变。
; preserve_authored_palette：破损新面 UV 已钳在色盘色块内（U 0.923..0.977 /
;   V 0.123..0.477），禁止运行时用塔楼暖色 A/B 主题材质覆盖，否则破损面会掉色。
; visual_only：天台边界碰撞由 TowerFloorStage3D 的 OuterBoundaryCollision_* 按
;   0.50m 代理生成。破损只改外观、不改阻挡高度，玩法阻挡与 intact 段完全一致。
; runtime_instantiation=batched_multimesh：与 intact 件同批按 5m 槽位摆放，
;   由 TowerFloorStage3D._build_outer_shell() 用带种子的随机排布选件。

[ext_resource type="PackedScene" path="res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_{key}_top3d.glb" id="1_visual"]

[node name="PrpRooftopParapetDmg{suffix}5m" type="Node3D"]
metadata/asset_id = "ENV-ROOFTOP-REF-PARAPET-DMG-{S}"
metadata/package_id = "ENV-ROOFTOP-REF-PARAPET-DMG-{S}"
metadata/asset_version = "v001"
metadata/source_blend = "{ref_blend}"
metadata/source_glb = "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_{key}_top3d.glb"
metadata/source_authoring_script = "{author_script}"
metadata/derived_from_asset_id = "{parent}"
metadata/damage_kind = "{kind}"
metadata/damage_label = "{label}"
metadata/damage_note = "{desc}"
metadata/grid_unit_m = 5.0
metadata/visual_height_m = 1.8
metadata/origin_contract = "bottom_center"
metadata/forward_axis = "+Z"
metadata/bounds_size_m = Vector3(5, 1.8, 0.5)
metadata/visual_bounds_size_m = Vector3(5, 1.8, 0.5)
metadata/bounds_note = "破损只在中段剔料，两端头带 |x|>=2.05m 未改动，包络与 intact 件逐值相同。"
metadata/visual_node_name = "女儿墙直段破损{suffix}_主体"
metadata/visual_only = true
metadata/collision_owner = "TowerFloorStage3D"
metadata/shadow_policy = "cast_and_receive"
metadata/preserve_authored_palette = true
metadata/runtime_instantiation = "batched_multimesh"
metadata/layout_role = "rooftop_parapet_straight_run"

[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]
"""

IMPORT_TEMPLATE = """[remap]

importer="scene"
importer_version=1
type="PackedScene"
uid="uid://{uid}"
path="res://.godot/imported/{glb_name}-{md5}.scn"

[deps]

source_file="res://assets/art/environments/tower_zones/rooftop/components/{glb_name}"
dest_files=["res://.godot/imported/{glb_name}-{md5}.scn"]

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=1
"""

UID_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxy"


def collect_used_uids() -> set[str]:
    used: set[str] = set()
    for path in PROJECT.rglob("*.import"):
        if ".godot" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        match = re.search(r'uid="uid://([^"]+)"', text)
        if match:
            used.add(match.group(1))
    return used


def main() -> int:
    used = collect_used_uids()
    print("existing uids:", len(used))
    rng = random.Random("parapet-damage-prefabs")
    written: list[str] = []
    for variant in VARIANTS:
        glb_name = "env_rooftop_ref_parapet_dmg_%s_top3d.glb" % variant["key"]
        glb_path = GLB_DIR / glb_name
        if not glb_path.is_file():
            raise SystemExit("missing GLB: %s" % glb_path)

        tscn_path = PROP_DIR / ("prp_rooftop_parapet_dmg_%s_5m.tscn" % variant["key"])
        tscn_text = TSCN_TEMPLATE.format(
            suffix=variant["suffix"],
            S=variant["suffix"],
            key=variant["key"],
            kind=variant["kind"],
            label=variant["label"],
            desc=variant["desc"],
            ref_blend=REF_BLEND,
            author_script=AUTHOR_SCRIPT,
            parent=PARENT_ASSET_ID,
        )
        tscn_path.write_bytes(tscn_text.replace("\n", "\r\n").encode("utf-8"))
        written.append(str(tscn_path))

        uid = None
        for _ in range(10000):
            candidate = "".join(rng.choice(UID_ALPHABET) for _ in range(13))
            if candidate not in used:
                uid = candidate
                used.add(candidate)
                break
        if uid is None:
            raise SystemExit("could not mint a unique uid")
        md5 = hashlib.md5(
            ("res://assets/art/environments/tower_zones/rooftop/components/" + glb_name).encode()
        ).hexdigest()
        import_path = GLB_DIR / (glb_name + ".import")
        if import_path.is_file():
            # 已导入过：保留 Godot 已确认的 uid / dest_files，不重铸（重铸会要求重新导入）。
            print("  %s  .import 已存在，跳过（uid 保持不变）" % glb_name)
            continue
        import_path.write_bytes(
            IMPORT_TEMPLATE.format(uid=uid, glb_name=glb_name, md5=md5).encode("utf-8")
        )
        written.append(str(import_path))
        print("  %s  uid=uid://%s  md5=%s" % (glb_name, uid, md5))

    print("PREFAB_GEN_OK files=%d" % len(written))
    for path in written:
        print("  ->", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
