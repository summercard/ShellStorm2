"""Generate the repetitive independent Godot wrapper scenes from the import manifest."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import godot_runtime_naming as grn  # noqa: E402


PROJECT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = PROJECT / "assets/art/asset_import_manifest_v001.json"

FACILITY_DATA = {
    "locker_station": ("", "赛博储物站", "未开放设施资产；已入库，暂不绑定基地功能"),
    "weapon_workshop": ("weapon_workshop", "枪械工坊", "制作、升级与调整枪械"),
    "retro_tv_station": ("", "复古游戏电视站", "未开放设施资产；已入库，暂不绑定基地功能"),
    "mission_operations": ("mission_operations", "远征情报终端", "查看本轮楼层、任务与下行规则"),
    "vending_machine": ("base_vending", "自动贩卖机", "购买基础装备与药水；出售保险柜物品"),
}

WEAPON_LOGIC_IDS = {
    "hair_dryer": "bp_pistol",
    "double_barrel_cannon": "bp_shotgun",
    "broom_rifle": "bp_rifle",
    "water_tank_blaster": "bp_machinegun",
    "candy_sniper": "bp_sniper",
    "toaster_launcher": "bp_launcher",
    "gumball_cannon": "bp_charge",
}


def vec(values: list[float]) -> str:
    return "Vector3(%s)" % ", ".join(f"{value:.6f}" for value in values)


def write_facility(slug: str, data: dict) -> None:
    facility_id, display_name, description = FACILITY_DATA[slug]
    minimum = data["bounds_min"]
    maximum = data["bounds_max"]
    size = [maximum[i] - minimum[i] for i in range(3)]
    center = [(maximum[i] + minimum[i]) * 0.5 for i in range(3)]
    interaction_size = [max(size[0] + 1.4, 3.4), max(size[1] + 0.8, 3.0), max(size[2] + 1.8, 3.2)]
    interaction_center = [0.0, size[1] * 0.48, -max(0.45, size[2] * 0.48)]
    root_filename = grn.root_scene_name(f"prp_base_{slug}")
    # 清单里的 GLB 路径（可能仍带 `_vNNN`）归一为稳定路径 + 源版本号：
    # 版本号进入节点 metadata，路径进入场景引用。
    glb_rel, glb_version = grn.require_stable_glb(PROJECT, data["glb"], script=Path(__file__).name)
    runtime_dir = PROJECT / "assets/art/props/base_world_3d/runtime" / slug
    runtime_dir.mkdir(parents=True, exist_ok=True)
    menu = "res://scenes/BaseVendingMenu.tscn" if slug == "vending_machine" else (
        "res://scenes/WorkshopMenu.tscn" if slug == "weapon_workshop" else ""
    )
    menu_line = f'menu_scene_path = "{menu}"\n' if menu else ""
    text = f'''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://src/base3d/BaseFacility3D.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://{glb_rel}" id="2_visual"]

[sub_resource type="BoxShape3D" id="ShapeInteraction"]
size = {vec(interaction_size)}

[sub_resource type="BoxShape3D" id="ShapeBody"]
size = {vec(size)}

[node name="{display_name}" type="Area3D"]
collision_layer = 0
collision_mask = 1
script = ExtResource("1_script")
facility_id = "{facility_id}"
display_name = "{display_name}"
description = "{description}"
{menu_line}metadata/asset_name_cn = "{data['name_cn']}"
metadata/asset_source = "res://{data['source']}"
metadata/asset_version = "{glb_version or ''}"
metadata/forward_axis = "-Z"

[node name="InteractionShape" type="CollisionShape3D" parent="."]
position = {vec(interaction_center)}
shape = SubResource("ShapeInteraction")

[node name="StaticBody3D" type="StaticBody3D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="StaticBody3D"]
position = {vec(center)}
shape = SubResource("ShapeBody")

[node name="Visual" type="Node3D" parent="."]

[node name="ImportedModel" parent="Visual" instance=ExtResource("2_visual")]

[node name="NameLabel" type="Label3D" parent="."]
position = Vector3(0, {maximum[1] + 0.45:.6f}, 0)
billboard = 1
text = "{display_name}"
font_size = 32
outline_size = 8
modulate = Color(0.82, 0.96, 1, 1)

[node name="PromptLabel" type="Label3D" parent="."]
visible = false
position = Vector3(0, {maximum[1] + 0.16:.6f}, -0.2)
billboard = 1
text = "[E] 使用 {display_name}"
font_size = 26
outline_size = 8
modulate = Color(1, 0.82, 0.28, 1)
'''
    (runtime_dir / root_filename).write_text(text, encoding="utf-8")


def write_weapon(slug: str, data: dict) -> None:
    sockets = data["sockets"]
    glb_rel, glb_version = grn.require_stable_glb(PROJECT, data["glb"], script=Path(__file__).name)
    runtime_dir = PROJECT / "assets/art/weapons/weapon_3d/runtime" / slug
    runtime_dir.mkdir(parents=True, exist_ok=True)
    logic_id = WEAPON_LOGIC_IDS.get(slug, "")
    marker_names = {
        "grip": "GripSocket",
        "support_hand": "SupportHandSocket",
        "muzzle": "MuzzleSocket",
        "muzzle_attachment": "MuzzleAttachmentSocket",
        "scope": "ScopeSocket",
        "magazine": "MagazineSocket",
        "stock": "StockSocket",
        "tactical": "TacticalSocket",
        "mutator": "MutatorSocket",
    }
    markers = []
    for key, node_name in marker_names.items():
        markers.append(f'''[node name="{node_name}" type="Marker3D" parent="."]
position = {vec(sockets[key])}
''')
    text = f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://{glb_rel}" id="1_visual"]

[node name="{data['name_cn']}" type="Node3D"]
metadata/asset_name_cn = "{data['name_cn']}"
metadata/logic_id = "{logic_id}"
metadata/source_blend = "res://{data['source']}"
metadata/asset_version = "{glb_version or ''}"
metadata/grip_contract = "root origin"
metadata/forward_axis = "-Z"

[node name="VisualRoot" parent="." instance=ExtResource("1_visual")]

{''.join(markers)}
[node name="GroundPivot" type="Marker3D" parent="."]
position = Vector3(0, {data['bounds_min'][1]:.6f}, 0)

[node name="IconPivot" type="Marker3D" parent="."]
position = Vector3(0, {(data['bounds_min'][1] + data['bounds_max'][1]) * 0.5:.6f}, {(data['bounds_min'][2] + data['bounds_max'][2]) * 0.5:.6f})
'''
    (runtime_dir / grn.root_scene_name(f"wpn_{slug}")).write_text(text, encoding="utf-8")


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    for slug, data in manifest["facilities"].items():
        write_facility(slug, data)
    for slug, data in manifest["weapons"].items():
        write_weapon(slug, data)
    print(f"Generated {len(manifest['facilities'])} facility and {len(manifest['weapons'])} weapon scenes")


if __name__ == "__main__":
    main()
