#!/usr/bin/env python3
"""把远征01 房间的「中央顶灯」与「墙面开关」注入静态布局 TSCN，使其成为可手调真源。

背景
----
房间灯（`WastelandLight3D`）与墙面开关（`RoomLightSwitch3D`）原先一律由
`DungeonRoom3D._build_content()` 在运行时实例化，落在 `RuntimeDetail` 下 ——
静态布局 TSCN 里查不到，美术无法在编辑器里手动调整位置与数值。

本脚本按**运行时实测真值**把这两类节点写进静态布局根下（`parent="."`），
配合 `DungeonRoom3D._adopt_authored_room_devices()` 优先认领，即可：
  · 在编辑器里选中节点、拖动 transform、改 Inspector 里的导出属性；
  · 运行时不再自建，落位与数值以场景文件为唯一真源。

插入位置（重要）
----------------
设备块插在**根节点元数据之后、所有组件实例之前** ⇒ 场景树里它们是
`ExpeditionRoomStaticLayout` 的**第一、第二个子节点**，打开场景即可见。
（早期版本追加在文件末尾，结果前面排着 100+ 个组件实例，要滚到最底才找得到。）

真值来源
--------
`tests/verification/probe_expedition_room_device_dump.gd` 的 `DUMPX` 行 ——
它遍历生成器的 `ROOM_IDS`（13 房）、输出**设备相对艺术根的 transform**。
⚠️ **不要**直接抄 `probe_expedition_room_authored_light_devices` 的 `light.transform`：
未迁移的灯挂在 `RuntimeDetail` 下，那是 `RuntimeDetail` 局部坐标，不是艺术根局部坐标。
（该探针只覆盖已迁移的房间，历史 room_01/room_02 的值就是从它的 DUMP 抄的。）

坐标口径
--------
运行时把静态 TSCN 实例改名成 `AuthoredLayoutArtRoot` / `SafeRoomArtRoot`
（`DungeonRoom3D` 载入静态布局后 `static_layout.name = …`）⇒ **TSCN 根就是艺术根**，
设备在文件里是 `parent="."` 的直挂子节点 ⇒ 写进去的必须是**艺术根局部** transform。
入口安全房 `start` 的艺术根带 yaw −90°，其场景根也带同一旋转，故更要用艺术根局部值。

`light_enabled` 必须写**真值**
------------------------------
`_create_room_light()` 的初始开态 = `authored_room_light_on or room_type in ["STAIR_LOBBY","BOSS"]`
⇒ `start`（STAIR_LOBBY）与 `boss`（BOSS）默认**亮**，其余默认灭。写死 `false` 会让编辑器里
读到的初始态与运行时相反（运行时随后会被 `RoomLightSwitch3D.configure_group()` 纠正，
但文件里留着错值会误导手调）。

幂等
----
已含设备节点的 TSCN 不会重复插入；若发现设备块不在规范位置（例如历史的文件末尾），
会**原样搬移**到顶部 —— 保留原 `unique_id`、导出值一字不改。可反复运行。

行尾
----
按**源文件自身**的行尾写回：纯 LF 文件保持纯 LF，纯 CRLF 文件保持纯 CRLF；
混合行尾直接拒绝处理（先定口径再改，别把两种行尾搅在一起）。
"""

from __future__ import annotations

import random
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ROOM_DIR = (
    REPO
    / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01"
)

LIGHT_SCRIPT = "res://src/world3d/WastelandLight3D.gd"
SWITCH_SCRIPT = "res://src/world3d/RoomLightSwitch3D.gd"
LIGHT_EXT_ID = "900_authored_light"
SWITCH_EXT_ID = "901_authored_switch"

ROOT_NODE_PREFIX = '[node name="ExpeditionRoomStaticLayout'
LIGHT_NODE_PREFIX = '[node name="RoomCeilingLight"'
SWITCH_NODE_PREFIX = '[node name="RoomLightSwitch3D"'

# 每房：顶灯与开关的真值（照 `probe_expedition_room_device_dump` 的 DUMPX 行，逐字照抄）。
#   light.transform / switch.transform = 相对**艺术根**的 Transform3D
#   light.enabled = 初始开态（start/boss 为 true，其余 false）
#   light.energy / range / seed = 运行时算定值
#
# ⚠️ 少数分量带浮点尾数（如 `-14.660004`、`4.995000000000001`）：那是运行时双精度运算的
#    真实结果（`2.7 × 1.85` 就长这样），**照抄不修饰** —— 修饰会让「文件值」与「运行时值」
#    分离，正是这套设备真源要避免的事。房间 02 既有文件里也有 `-8.742278e-08` 这类分量。
ROOMS: dict[str, dict[str, object]] = {
    "start": {
        "note": "入口安全房（STAIR_LOBBY v007，15×15，整房 yaw −90°）；初始灯亮",
        "light": {
            "transform": "Transform3D(1.1924881e-08, 0, 1, 0, 1, 0, -1, 0, 1.1924881e-08, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "14.62",
            "seed": "77001199",
            "enabled": "true",
        },
        "switch": {
            "transform": (
                "Transform3D(-1, 0, -3.1786506e-08, 0, 1, 0, 3.1786506e-08, 0, -1, -3.2999997, 0, -7.16)"
            ),
        },
    },
    "room_01": {
        "note": "L 型走廊房（corridor_45x40 l_turn，40×45）；顶灯落位＝真砖格质心",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5.357143, 9.28, 5.357143)",
            "energy": "4.995",
            "range": "37.6",
            "seed": "77105928",
            "enabled": "false",
        },
        "switch": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 12.5, 0, -22.16)",
        },
    },
    "room_02": {
        "note": "数据库房（db_70x50，40×30）；矩形真砖格中心",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995",
            "range": "28.2",
            "seed": "77210657",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, -4.2, 0, 14.66)"
            ),
        },
    },
    "room_03": {
        "note": "办公室房（office_60x70，实 30×40）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "28.2",
            "seed": "77315386",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-4.371139e-08, 0, -1, 0, 1, 0, 1, 0, -4.371139e-08, -14.660004, 0, 4.200001)"
            ),
        },
    },
    "room_04": {
        "note": "U 型走廊房（corridor_45x40 u_turn，45×40）；顶灯落位＝真砖格质心",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, -7.5)",
            "energy": "4.995000000000001",
            "range": "37.599999999999994",
            "seed": "77420115",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, 22.160004, 0, -7.500002)"
            ),
        },
    },
    "room_05": {
        "note": "桥房（bridge_60x50，30×60）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "28.2",
            "seed": "77524844",
            "enabled": "false",
        },
        "switch": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 4.199997, 0, -29.66)",
        },
    },
    "room_06": {
        "note": "数据库房（db_70x50，30×40）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "28.2",
            "seed": "77629573",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, -4.199997, 0, 19.66)"
            ),
        },
    },
    "room_07": {
        "note": "储物房（STORAGE，25×25）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "23.5",
            "seed": "77734302",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-4.371139e-08, 0, -1, 0, 1, 0, 1, 0, -4.371139e-08, -12.160004, 0, 4.199997)"
            ),
        },
    },
    "room_08": {
        "note": "L 型走廊房（corridor_45x40 l_turn，40×45）；与 room_01 同房型、镜像落位",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -5.357147, 9.28, -5.357147)",
            "energy": "4.995000000000001",
            "range": "37.599999999999994",
            "seed": "77839031",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, 19.660004, 0, -15)"
            ),
        },
    },
    "room_09": {
        "note": "办公室房（office_60x70，实 30×40；EVENT）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "28.2",
            "seed": "77943760",
            "enabled": "false",
        },
        "switch": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 4.199997, 0, -19.660004)",
        },
    },
    "room_10": {
        "note": "数据库房（db_70x50，40×30）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "28.2",
            "seed": "78048489",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, -4.200001, 0, 14.660004)"
            ),
        },
    },
    "boss": {
        "note": "Boss 房（boss_50x40，50×40）；初始灯亮",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "37.599999999999994",
            "seed": "78153218",
            "enabled": "true",
        },
        "switch": {
            "transform": (
                "Transform3D(-4.371139e-08, 0, -1, 0, 1, 0, 1, 0, -4.371139e-08, -24.66, 0, 4.199997)"
            ),
        },
    },
    "extraction": {
        "note": "撤离房（EXTRACTION，25×25）",
        "light": {
            "transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
            "energy": "4.995000000000001",
            "range": "23.5",
            "seed": "78257947",
            "enabled": "false",
        },
        "switch": {
            "transform": (
                "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, 12.16, 0, -4.199997)"
            ),
        },
    },
}

DEVICE_META = "metadata/authored_room_device"
LIGHT_COLOR = "Color(0.59, 0.76, 0.88, 1)"


def _detect_eol(raw: bytes) -> str | None:
    """返回 "\\n" / "\\r\\n"；混合行尾返回 None（拒绝处理）。"""
    crlf = raw.count(b"\r\n")
    lone_lf = raw.count(b"\n") - crlf
    lone_cr = raw.count(b"\r") - crlf
    if lone_cr:
        return None
    if crlf and lone_lf:
        return None
    return "\r\n" if crlf else "\n"


def _used_unique_ids(text: str) -> set[int]:
    return {int(value) for value in re.findall(r"unique_id=(\d+)", text)}


def _fresh_unique_id(used: set[int]) -> int:
    while True:
        candidate = random.randint(100_000_000, 2_000_000_000)
        if candidate not in used:
            used.add(candidate)
            return candidate


def _light_block(room_id: str, spec: dict[str, object], unique_id: int) -> list[str]:
    return [
        f"; 房间中央顶灯（{ROOMS[room_id]['note']}）。",
        "; 真源＝本静态布局；运行时由 DungeonRoom3D._adopt_authored_room_devices() 认领，不再自建。",
        "; 原运行时公式：energy = theme.fixture_energy 2.7 × 1.85（size_class 非 large/arena/floor）；",
        ";   light_range = max(theme.fixture_range 8.5 × 1.72, min(房间短边) × 0.94)；y = FLOOR_HEIGHT_M 12 − 2.72；",
        ";   light_enabled = authored_room_light_on or room_type in [STAIR_LOBBY, BOSS]。",
        f'[node name="RoomCeilingLight" type="Node3D" parent="." unique_id={unique_id}]',
        f"transform = {spec['transform']}",
        f'script = ExtResource("{LIGHT_EXT_ID}")',
        f"light_color = {LIGHT_COLOR}",
        f"energy = {spec['energy']}",
        f"light_range = {spec['range']}",
        "failing = false",
        f"flicker_seed = {spec['seed']}",
        "cast_shadow = true",
        'fixture_style = "ceiling"',
        f"light_enabled = {spec['enabled']}",
        f'{DEVICE_META} = "ceiling_light"',
    ]


def _switch_block(spec: dict[str, object], unique_id: int) -> list[str]:
    return [
        "; 墙面灯开关。真源＝本静态布局；运行时认领后按房间声明的初始灯亮状态配置灯组。",
        f'[node name="RoomLightSwitch3D" type="Area3D" parent="." unique_id={unique_id}]',
        f"transform = {spec['transform']}",
        f'script = ExtResource("{SWITCH_EXT_ID}")',
        f'{DEVICE_META} = "light_switch"',
    ]


def _node_end(lines: list[str], start: int) -> int:
    """从节点声明行起，返回该节点属性块结束下标（不含）。"""
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line.strip() == "" or line.startswith("["):
            break
        end += 1
    return end


def _extract_device_block(lines: list[str]) -> tuple[list[str], int, int] | None:
    """若已存在设备块，返回 (块内容[已去首尾空行], 起始下标, 结束下标)；否则 None。

    块内容原样保留（含原有 `unique_id` 与导出值），搬移不改变任何数值。
    """
    light_index = next(
        (i for i, line in enumerate(lines) if line.startswith(LIGHT_NODE_PREFIX)), None
    )
    if light_index is None:
        return None
    start = light_index
    while start - 1 >= 0 and lines[start - 1].startswith(";"):
        start -= 1
    if start - 1 >= 0 and lines[start - 1].strip() == "":
        start -= 1
    switch_index = next(
        (i for i, line in enumerate(lines) if line.startswith(SWITCH_NODE_PREFIX)), None
    )
    end = _node_end(lines, switch_index if switch_index is not None else light_index)
    block = lines[start:end]
    while block and block[0].strip() == "":
        block.pop(0)
    while block and block[-1].strip() == "":
        block.pop()
    return block, start, end


def _root_meta_insert_at(lines: list[str]) -> int:
    """返回根节点「元数据之后、空行之前」的插入下标。"""
    root_index = next(i for i, line in enumerate(lines) if line.startswith(ROOT_NODE_PREFIX))
    cursor = root_index + 1
    while cursor < len(lines) and lines[cursor].strip() != "":
        cursor += 1
    return cursor


def patch(room_id: str) -> str:
    spec = ROOMS[room_id]
    path = ROOM_DIR / f"f00_{room_id}_static_layout.tscn"
    if not path.exists():
        return f"SKIP {room_id}: 文件不存在 {path}"
    raw = path.read_bytes()
    eol = _detect_eol(raw)
    if eol is None:
        return f"FAIL {room_id}: 行尾混合（或含裸 CR），拒绝处理（请先统一行尾口径）"
    lines = raw.decode("utf-8").replace("\r\n", "\n").rstrip("\n").split("\n")

    # 1) 既有设备块（无论在文件哪个位置）先原样摘出，避免重复插入。
    extracted = _extract_device_block(lines)
    relocated = extracted is not None
    if extracted is not None:
        block, start, end = extracted
        del lines[start:end]
        while lines and lines[-1].strip() == "":
            lines.pop()
    else:
        used = _used_unique_ids("\n".join(lines))
        block = _light_block(room_id, spec["light"], _fresh_unique_id(used))  # type: ignore[arg-type]
        block = block + [""] + _switch_block(spec["switch"], _fresh_unique_id(used))  # type: ignore[arg-type]

    text = "\n".join(lines)

    # 2) ext_resource：缺失才补，接在最后一条 ext_resource 之后。
    if LIGHT_EXT_ID not in text:
        ext_indexes = [i for i, line in enumerate(lines) if line.startswith("[ext_resource")]
        if not ext_indexes:
            return f"FAIL {room_id}: 找不到 ext_resource 段"
        last_ext = ext_indexes[-1]
        lines[last_ext + 1 : last_ext + 1] = [
            f'[ext_resource type="Script" path="{LIGHT_SCRIPT}" id="{LIGHT_EXT_ID}"]',
            f'[ext_resource type="Script" path="{SWITCH_SCRIPT}" id="{SWITCH_EXT_ID}"]',
        ]

    # 3) 根节点 meta：缺失才补（放根段末尾、空行之前）。
    if "metadata/authored_room_devices" not in "\n".join(lines):
        lines.insert(_root_meta_insert_at(lines), "metadata/authored_room_devices = true")

    # 4) 设备块：插到根元数据之后、所有组件实例之前 ⇒ 场景树里排最前，一开场景就看得见。
    insert_at = _root_meta_insert_at(lines)
    lines[insert_at:insert_at] = [""] + block

    out = "\n".join(lines).rstrip("\n") + "\n"
    path.write_bytes(out.replace("\n", eol).encode("utf-8"))
    tag = "MOVED" if relocated else "PATCHED"
    return f"{tag} {room_id}: {path.name}  eol={'CRLF' if eol == chr(13) + chr(10) else 'LF'}"


def main() -> int:
    targets = sys.argv[1:] or list(ROOMS)
    failures = 0
    for room_id in targets:
        if room_id not in ROOMS:
            print(f"SKIP {room_id}: 不在 ROOMS 真值表里")
            failures += 1
            continue
        result = patch(room_id)
        print(result)
        if result.startswith("FAIL"):
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
