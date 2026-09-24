#!/usr/bin/env python3
"""自测：check_expedition_room_footprints.py 必须真的会对「轮廓 / 多层几何」不一致报红。

一个对照组 + 7 类不一致，每类各报红一次。用真实模板目录的**临时副本**改坏，
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


# 1｜顶点掉出 5 m 网格
def break_grid(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_01"]["vertices_m"][3] = [42, 40]

    patch(work / DB, edit)


assert run(break_grid) == 1, "1 类（顶点不在 5 m 网格）没有报红"


# 2｜轮廓自交（南中段外凸的两个顶点前后颠倒 ⇒ 边穿越）
def break_self_intersect(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_01"]["vertices_m"] = [
            [0, 0], [70, 0], [70, 40], [45, 50], [45, 40], [25, 50], [25, 40], [0, 40],
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
#    南边界只留 x∈[0,5]，与最西槽区间 [5,10] 恰好不重叠；包围盒仍 = size_m。
def break_no_openable(work: Path) -> None:
    def edit(data):
        data["variant_footprints"]["db_01"]["vertices_m"] = [
            [0, 0], [70, 0], [70, 40], [5, 40], [5, 50], [0, 50],
        ]

    patch(work / DB, edit)


assert run(break_no_openable) == 1, "7 类（openable_walls 某向无可开槽）没有报红"

print("EXPEDITION_FOOTPRINT_CHECKER_OK: 对照 + 7 类不一致均按预期判定")
