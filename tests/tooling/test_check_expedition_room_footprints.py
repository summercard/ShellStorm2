#!/usr/bin/env python3
"""自测：check_expedition_room_footprints.py 必须真的会对「轮廓 / 多层几何 / 取向唯一表达 /
level_plan 契约」不一致报红。

一个对照组 + 12 类不一致，每类各报红一次。用真实模板目录的**临时副本**改坏，
仓库文件只读（自测绝不改真源）。
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/check_expedition_room_footprints.py"
TEMPLATES = ROOT / "source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates"

DB = "db_70x50.json"
CORRIDOR = "corridor_45x40.json"
BRIDGE = "bridge_60x50.json"


def run(mutate) -> int:
    with tempfile.TemporaryDirectory() as temp_dir:
        work = Path(temp_dir) / "room_templates"
        shutil.copytree(TEMPLATES, work)
        mutate(work)
        return subprocess.run(
            [sys.executable, str(CHECKER), "--quiet", "--templates-dir", str(work)],
            capture_output=True,
        ).returncode


def patch(path: Path, edit) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    edit(data)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def noop(_work: Path) -> None:
    return


# 对照：原样必须通过
assert run(noop) == 0, "原样模板被误判为不一致"


# 1｜顶点掉出 5 m 网格（1 号顶点落在轮廓内，但 x=12 不在 5 m 网格上）
def break_grid(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_01"]["vertices_m"][1] = [12, 0]

    patch(work / DB, edit)


assert run(break_grid) == 1, "1 类（顶点不在 5 m 网格）没有报红"


# 2｜轮廓自交（尺寸仍是 40×30，但 v3→v4 竖边拉到 x=20 ⇒ 与 y=25 的横边交叉）
def break_self_intersect(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_01"]["vertices_m"] = [
            [0, 0], [40, 0], [40, 30], [20, 30], [20, 10], [30, 10], [30, 25], [0, 25],
        ]

    patch(work / DB, edit)


assert run(break_self_intersect) == 1, "2 类（轮廓自交）没有报红"


# 3｜variant_footprints 缺一个变体
def break_missing_variant(work: Path) -> None:
    def edit(data):
        del data["variant_footprints"]["u_turn"]

    patch(work / CORRIDOR, edit)


assert run(break_missing_variant) == 1, "3 类（轮廓缺变体）没有报红"


# 4｜坐标系 frame 写错（会把 x/z 镜像，运行时裁切全错）
def break_frame(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_02"]["frame"] = "bbox_sw_x_east_y_north"

    patch(work / DB, edit)


assert run(break_frame) == 1, "4 类（frame 不符）没有报红"


# 5｜坑深被写成 0
def break_pit_depth(work: Path) -> None:
    def edit(data):
        data["sunken_pit"]["depth_m"] = 0.0

    patch(work / BRIDGE, edit)


assert run(break_pit_depth) == 1, "5 类（坑深非法）没有报红"


# 6｜下层被标成可达（业主裁决：下层下不去、纯装饰）
def break_pit_accessible(work: Path) -> None:
    def edit(data):
        data["sunken_pit"]["lower_platform"]["accessible"] = True

    patch(work / BRIDGE, edit)


assert run(break_pit_accessible) == 1, "6 类（下层可达）没有报红"


# 7｜openable_walls 声明的某向在轮廓上没有任何可开槽
#    南边界只留 x∈[0,5]，与最西槽区间 [5,10] 恰好不重叠；包围盒仍 = size_m（40×30）。
def break_no_openable(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_01"]["vertices_m"] = [
            [0, 0], [40, 0], [40, 25], [5, 25], [5, 30], [0, 30],
        ]

    patch(work / DB, edit)


assert run(break_no_openable) == 1, "7 类（openable_walls 某向无可开槽）没有报红"


# ----------------------------------------------------------------- 8~11：取向唯一表达 + level_plan 契约

ALL_TEMPLATES = [
    "boss_50x40", "bridge_60x50", "corridor_45x40", "db_70x50",
    "extraction_25x25", "office_60x70", "safe_15x15", "std_25x25",
]


def write_plan(work: Path, pool, registered) -> None:
    (work.parent / "level_plan.json").write_text(
        json.dumps(
            {"generation_policy": {"content_template_pool": pool}, "room_templates": registered},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )


# 8｜任何模板声明 `axis_pose_of` 都报红（转置姿态只许用 template_rotation_deg 表达）
#     业主裁定 2026-09-25：「不要两批代号」—— 同一房型在模板目录里只能有一个 id。
#     这条专防有人把第二个 id（如曾经的 bridge_50x60）加回来。
def break_axis_alias(work: Path) -> None:
    def edit(data):
        data["axis_pose_of"] = "bridge_50x60"

    patch(work / BRIDGE, edit)


assert run(break_axis_alias) == 1, "8 类（模板声明 axis_pose_of）没有报红"


# 9｜桥跨宽写成 y 跨（30）而不是窄边宽（5）
def break_span_width(work: Path) -> None:
    def edit(data):
        data["bridge_span"]["width_m"] = 30.0

    patch(work / BRIDGE, edit)


assert run(break_span_width) == 1, "9 类（桥跨宽未取窄边）没有报红"


# 10｜level_plan 的房型池引用了不存在的模板
def break_pool_missing_template(work: Path) -> None:
    write_plan(work, ["bridge_999x999"], ALL_TEMPLATES)


assert run(break_pool_missing_template) == 1, "10 类（池引用不存在模板）没有报红"


# 11｜level_plan.room_templates 漏登记模板文件（未登记 ⇒ 门槽表不被加载）
def break_unregistered_template(work: Path) -> None:
    write_plan(work, ["bridge_60x50"], ["bridge_60x50"])


assert run(break_unregistered_template) == 1, "11 类（room_templates 未登记模板文件）没有报红"

# 12｜正方形坑（工字型桥房 30×30 下沉区）上，桥长边必须等于坑边长
#     坑两轴等长 ⇒ 无「长轴」可言、桥可沿任一轴跨；但桥长边 25 ≠ 坑边 30 仍必须报红。
def break_square_pit_bridge_short(work: Path) -> None:
    def edit(data):
        data["bridge_span"]["rect_m"]["y"] = [15.0, 40.0]

    patch(work / BRIDGE, edit)


assert run(break_square_pit_bridge_short) == 1, "12 类（正方形坑上桥长边 ≠ 坑边长）没有报红"

print("EXPEDITION_FOOTPRINT_CHECKER_OK: 对照 + 12 类不一致均按预期判定")
