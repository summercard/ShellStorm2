#!/usr/bin/env python3
"""远征03 门套件白盒（门扇 + 策略表）。

## 为什么门是独立对象而不是房间模板的一部分

这是抄《挺进地牢》最关键的一条结构：

- **房间模板只声明"我这面能接"**（预定义出口坐标），不带门；
- **门由运行时按规则落上去** —— 这一局是普通门、上锁门还是隐藏门，由**规则层**决定；
- 若把门烘进模板，同一间房就只能有一种开门方式，加一种锁就要重做一份模板。

本工程已有的落点是 `RoomDoor3D`：

```
configure(direction, target_room_id, accent, panel_visual_scene)   # 几何与朝向
set_access_policy({requires_key, requires_clear, triggers_fate})   # 规则
```

门扇视觉是**可注入**的（`panel_visual_scene`），所以"五种门"不必是五套几何 ——
它们是**同一套 2.2×2.5 门洞上的五种门扇 + 五种策略**。本脚本产出这个组合。

## 五种门的依据

| 门型 | 挺进地牢对应 | 本工程落点 |
|---|---|---|
| `normal` | 战斗门（进房关门，清完开） | `requires_clear = true` |
| `locked` | 上锁门（要钥匙） | + `requires_key = true` |
| `boss` | 首领门前（常闭，清前厅才开） | `requires_key + requires_clear + triggers_fate` |
| `secret` | 隐藏门（**可破坏的墙**，不是门） | `SecretDoor3D`（有 HP，被打碎） |
| `cell` | 牢房门（清怪给钥匙） | `requires_key = true`，产生 Cell Key |

**`secret` 刻意不复用 `RoomDoor3D`。** 本工程已有 `SecretDoor3D`（带 `max_hp`/`hp`、
被击打后 `BROKE`），它的语义是"墙"而不是"会升降的门板"。把隐藏门做成门板会丢掉
"能打碎"这个核心行为 —— 那正是它区别于普通锁门的地方。

## 坐标契约（与既有门扇一致）

- 原点 = **门洞底面中心**（`RoomDoor3D._build()` 实例化后按 `-clear_height/2` 回挂）
- 朝向 = **-Z**，门宽沿 X、厚度沿 Z
- 尺寸 = 门洞宽 2.2 × 净高 2.5 × 厚 0.18

运行：
    python3 scripts/build_whitebox_door_kit.py            # 生成门扇 + 策略表
    python3 scripts/build_whitebox_door_kit.py --preview  # 另出正视预览 PNG
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/common_components/whitebox_doors"
)
CATALOG = ROOT / "data/level_plans/expedition_03/door_catalog.json"
PREVIEW_DIR = ROOT / "docs/art/expedition03_door_kit"

# 门洞尺寸：全部取自 room_templates 的 door_contract（8 份模板一致）。
OPENING_W = 2.2
OPENING_H = 2.5
PANEL_T = 0.18

# 五种门：策略字段与 RoomDoor3D.set_access_policy 一一对应。
# `egt` 只是溯源说明，不参与任何判定。
DOORS: list[dict] = [
    {
        "kind": "normal",
        "display_name_zh": "普通门（战斗门）",
        "runtime_class": "RoomDoor3D",
        "access_policy": {"requires_key": False, "requires_clear": True, "triggers_fate": False},
        "egt": {
            "door_type": "combat door",
            "behaviour": "玩家进房后门自动关上，清完怪再开",
            "mapped_by": "requires_clear = true",
        },
        "used_in_room_kinds": ["NORMAL", "HUB", "CONNECTOR", "REWARD", "SHOP", "BOSS_FOYER", "ENTRANCE", "EXIT"],
        "panel": {"color": [0.30, 0.33, 0.36], "inset": 0.0, "marker": "none"},
    },
    {
        "kind": "locked",
        "display_name_zh": "上锁门",
        "runtime_class": "RoomDoor3D",
        "access_policy": {"requires_key": True, "requires_clear": False, "triggers_fate": False},
        "egt": {
            "door_type": "locked door",
            "behaviour": "需要消耗一把钥匙",
            "mapped_by": "requires_key = true",
            "note": "挺进地牢用 chanceToLock 在注入阶段配概率；本工程按房间位显式指定。",
        },
        "used_in_room_kinds": ["REWARD", "SHOP"],
        "panel": {"color": [0.62, 0.44, 0.16], "inset": 0.02, "marker": "keyhole"},
    },
    {
        "kind": "boss",
        "display_name_zh": "首领门",
        "runtime_class": "RoomDoor3D",
        "access_policy": {"requires_key": True, "requires_clear": True, "triggers_fate": True},
        "egt": {
            "door_type": "boss door",
            "behaviour": "首领房唯一入口，常闭且带仪式演出",
            "mapped_by": "requires_key + requires_clear + triggers_fate",
        },
        "used_in_room_kinds": ["BOSS"],
        "panel": {"color": [0.55, 0.18, 0.18], "inset": 0.03, "marker": "pillars"},
    },
    {
        "kind": "secret",
        "display_name_zh": "隐藏门（可打碎的墙）",
        "runtime_class": "SecretDoor3D",
        "access_policy": None,
        "egt": {
            "door_type": "secret door / breakable wall",
            "behaviour": "外观与墙无异，用爆炸或特定手段打碎后进入",
            "mapped_by": "SecretDoor3D 的 max_hp / BROKE 状态",
            "note": "不复用 RoomDoor3D：隐藏门的核心行为是「被打碎」，门板的升降语义表达不了。",
        },
        "used_in_room_kinds": ["REWARD"],
        "panel": {"color": [0.52, 0.55, 0.60], "inset": 0.0, "marker": "none"},
        "note": "此型门扇与墙板同色同面 —— 这是**故意**的：隐藏门必须看起来不像门。",
    },
    {
        "kind": "cell",
        "display_name_zh": "牢房门",
        "runtime_class": "RoomDoor3D",
        "access_policy": {"requires_key": True, "requires_clear": False, "triggers_fate": False},
        "egt": {
            "door_type": "cell door",
            "behaviour": "本层出现牢房锁时，系统必定给某个敌人分配一把 Cell Key",
            "mapped_by": "requires_key = true",
            "note": "挺进地牢里这是唯一「门反向影响刷怪」的依赖；本工程刷怪侧尚未消费，只声明策略。",
        },
        "used_in_room_kinds": ["REWARD"],
        "panel": {"color": [0.26, 0.29, 0.32], "inset": 0.01, "marker": "bars"},
    },
]


def build_panel(door: dict) -> str:
    kind = door["kind"]
    color = door["panel"]["color"]
    inset = float(door["panel"]["inset"])
    marker = door["panel"]["marker"]

    subs: list[str] = []
    nodes: list[str] = []
    subs.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_panel"]\n'
        f"albedo_color = Color({color[0]:g}, {color[1]:g}, {color[2]:g}, 1)\n"
        "roughness = 0.85\n"
    )
    subs.append(
        '[sub_resource type="BoxMesh" id="BoxMesh_panel"]\n'
        f"size = Vector3({OPENING_W - inset * 2:g}, {OPENING_H:g}, {PANEL_T:g})\n"
    )
    nodes.append(
        '[node name="DoorPanel" type="MeshInstance3D" parent="."]\n'
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {OPENING_H / 2:g}, 0)\n"
        'mesh = SubResource("BoxMesh_panel")\n'
        'material_override = SubResource("Mat_panel")\n'
    )
    extra = 0

    def marker_mat(mid: str, c: tuple[float, float, float]) -> None:
        subs.append(
            f'[sub_resource type="StandardMaterial3D" id="{mid}"]\n'
            f"albedo_color = Color({c[0]:g}, {c[1]:g}, {c[2]:g}, 1)\nroughness = 0.7\n"
        )

    if marker == "keyhole":
        marker_mat("Mat_key", (0.95, 0.78, 0.35))
        subs.append(
            '[sub_resource type="BoxMesh" id="BoxMesh_key"]\n'
            "size = Vector3(0.22, 0.42, 0.05)\n"
        )
        nodes.append(
            '[node name="KeyholePlate" type="MeshInstance3D" parent="."]\n'
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {OPENING_H * 0.52:g}, "
            f"{(PANEL_T + 0.05) / 2:g})\n"
            'mesh = SubResource("BoxMesh_key")\n'
            'material_override = SubResource("Mat_key")\n'
        )
        extra += 1
    elif marker == "pillars":
        marker_mat("Mat_pillar", (0.20, 0.14, 0.14))
        subs.append(
            '[sub_resource type="BoxMesh" id="BoxMesh_pillar"]\n'
            f"size = Vector3(0.30, {OPENING_H:g}, {PANEL_T + 0.10:g})\n"
        )
        for i, x in enumerate((-OPENING_W / 2 + 0.15, OPENING_W / 2 - 0.15)):
            nodes.append(
                f'[node name="BossPillar_{i}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {OPENING_H / 2:g}, 0)\n"
                'mesh = SubResource("BoxMesh_pillar")\n'
                'material_override = SubResource("Mat_pillar")\n'
            )
            extra += 1
    elif marker == "bars":
        marker_mat("Mat_bars", (0.55, 0.58, 0.62))
        subs.append(
            '[sub_resource type="BoxMesh" id="BoxMesh_bar"]\n'
            f"size = Vector3(0.10, {OPENING_H:g}, {PANEL_T + 0.08:g})\n"
        )
        for i in range(5):
            x = -OPENING_W / 2 + OPENING_W * (i + 1) / 6.0
            nodes.append(
                f'[node name="CellBar_{i}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {OPENING_H / 2:g}, 0)\n"
                'mesh = SubResource("BoxMesh_bar")\n'
                'material_override = SubResource("Mat_bars")\n'
            )
            extra += 1

    asset_id = f"ENV-EXPEDITION-WB-DOOR-{kind.upper()}"
    header = (
        '[node name="WhiteboxDoorPanel" type="Node3D"]\n'
        'metadata/schema = "shellstorm2.expedition.door_panel.whitebox.v001"\n'
        f'metadata/asset_id = "{asset_id}"\n'
        f'metadata/door_kind = "{kind}"\n'
        f'metadata/display_name_zh = "{door["display_name_zh"]}"\n'
        f"metadata/bounds_size_m = Vector3({OPENING_W:g}, {OPENING_H:g}, {PANEL_T:g})\n"
        'metadata/origin_contract = "bottom_center"\n'
        'metadata/forward_axis = "-Z"\n'
        'metadata/up_axis = "+Y"\n'
        'metadata/whitebox = true\n'
        f'metadata/panel_marker = "{marker}"\n'
        'metadata/whitebox_excludes = ["final_art","materials","sfx_hooks","vfx"]\n'
        'metadata/source = "scripts/build_whitebox_door_kit.py"\n'
    )
    return '[gd_scene format=3]\n\n' + "\n".join(subs) + "\n" + header + "\n".join(nodes)


def preview(door: dict, out: Path) -> None:
    from PIL import Image, ImageDraw
    S = 110
    pad = 44
    W = int(OPENING_W * S) + pad * 2
    H = int(OPENING_H * S) + pad * 2
    im = Image.new("RGB", (W, H), (238, 240, 242))
    dr = ImageDraw.Draw(im)
    c = door["panel"]["color"]
    rgb = tuple(int(v * 255) for v in c)
    x0, y0 = pad, pad
    x1, y1 = x0 + OPENING_W * S, y0 + OPENING_H * S
    dr.rectangle([x0, y0, x1, y1], fill=rgb, outline=(40, 44, 48), width=2)
    marker = door["panel"]["marker"]
    if marker == "keyhole":
        cx = (x0 + x1) / 2
        cy = y0 + OPENING_H * S * 0.48
        dr.rectangle([cx - 12, cy - 24, cx + 12, cy + 24], fill=(242, 199, 89))
    elif marker == "pillars":
        dr.rectangle([x0 + 2, y0 + 2, x0 + 34, y1 - 2], fill=(51, 36, 36))
        dr.rectangle([x1 - 34, y0 + 2, x1 - 2, y1 - 2], fill=(51, 36, 36))
    elif marker == "bars":
        for i in range(5):
            bx = x0 + (x1 - x0) * (i + 1) / 6.0
            dr.rectangle([bx - 5, y0 + 2, bx + 5, y1 - 2], fill=(140, 148, 158))
    dr.text((pad, 14), f"{door['kind']}  {OPENING_W:g}x{OPENING_H:g}m  {door['display_name_zh']}",
            fill=(30, 34, 38))
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def main(argv: list[str]) -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    want_preview = "--preview" in argv

    catalog = {
        "schema": "shellstorm2.expedition.door_catalog.v001",
        "schema_version": 1,
        "level_id": "expedition_03",
        "shared_opening": {
            "width_m": OPENING_W,
            "clear_height_m": OPENING_H,
            "panel_thickness_m": PANEL_T,
            "grid_unit_m": 5.0,
            "note": "门洞尺寸取自 room_templates 的 door_contract，8 份模板一致；门扇原点为门洞底面中心。",
        },
        "design_rule": (
            "房间模板只声明可接的出口槽（ConnectionPorts），门由运行时落上去。"
            "加一种门只改本表与一条装配规则，不改任何房间 TSCN —— "
            "把门烘进模板会让「同一间房只能有一种开门方式」。"
        ),
        "kinds": {},
    }

    for door in DOORS:
        name = f"wb_door_{door['kind']}_panel.tscn"
        (OUT_DIR / name).write_text(build_panel(door) + "\n", encoding="utf-8")
        entry = {k: v for k, v in door.items() if k != "panel"}
        entry["panel_scene"] = (
            "res://assets/art/environments/tower_zones/expedition/runtime/"
            f"common_components/whitebox_doors/{name}"
        )
        entry["panel_marker"] = door["panel"]["marker"]
        entry["panel_color"] = door["panel"]["color"]
        catalog["kinds"][door["kind"]] = entry
        print(f"written {name:34s} runtime={door['runtime_class']:14s} marker={door['panel']['marker']}")
        if want_preview:
            preview(door, PREVIEW_DIR / f"wb_door_{door['kind']}.png")

    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n{len(DOORS)} 种门 -> {OUT_DIR.relative_to(ROOT)}")
    print(f"策略表 -> {CATALOG.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
