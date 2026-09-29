"""离线核对远征01 不规则房中「中央顶灯 / 墙面开关」的落位是否还在房内地砖上。

判据复刻运行时 `DungeonRoom3D._inside_authored_footprint`：
点落在某个真砖格心附近（|dx|、|dz| <= 2.5 + 0.01）即算房内。
砖格心来自房间静态 TSCN 里 TILE_* 组件的摆位（运行时 `_authored_tile_cells` 的来源）。
"""

import re
import sys
from pathlib import Path

ROOT = Path(
    r"I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/"
    r"expedition/runtime/room_instances/expedition_01"
)

HALF = 2.5
TOL = 0.01

# 房间 ID -> (房间尺寸 x/z, 运行时实测的开关 local 位置, 说明)
CASES = {
    "room_01": ((40.0, 45.0), (4.2, -22.16), "corridor_45x40 l_turn（L 形）"),
    "room_04": ((45.0, 40.0), (22.16, -4.2), "corridor_45x40 u_turn（凹字形）"),
    "room_08": ((40.0, 45.0), (19.66, -4.2), "corridor_45x40 l_turn（L 形）"),
    "room_03": ((30.0, 40.0), (-14.66, 4.2), "office_60x70（矩形对照）"),
}

NODE_RE = re.compile(
    r'^\[node name="(?P<name>[^"]*TILE_[^"]*)"(?P<body>[^\n]*)\]\n'
    r'(?P<attrs>(?:^[a-z_/]+ = .*\n)*)',
    re.MULTILINE,
)
TRANSFORM_RE = re.compile(r"Transform3D\((?P<vals>[^)]*)\)")


def parse_tiles(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    tiles = []
    for match in NODE_RE.finditer(text):
        body = match.group("body") + "\n" + match.group("attrs")
        tf = TRANSFORM_RE.search(body)
        if tf is None:
            continue
        vals = [float(v) for v in tf.group("vals").split(",")]
        if len(vals) < 12:
            continue
        tiles.append((match.group("name"), vals[9], vals[11]))
    return tiles


def inside(tiles, x: float, z: float) -> bool:
    for _name, tx, tz in tiles:
        if abs(x - tx) <= HALF + TOL and abs(z - tz) <= HALF + TOL:
            return True
    return False


def nearest(tiles, x: float, z: float):
    best = None
    for _name, tx, tz in tiles:
        d = ((x - tx) ** 2 + (z - tz) ** 2) ** 0.5
        if best is None or d < best[0]:
            best = (d, tx, tz)
    return best


def main() -> int:
    print("房间       砖数  包围盒中心在房内  开关落点      开关在房内  开关到最近砖心")
    for room_id, (dims, switch_local, note) in CASES.items():
        path = ROOT / f"f00_{room_id}_static_layout.tscn"
        if not path.exists():
            print(f"{room_id}: 缺文件 {path}")
            continue
        tiles = parse_tiles(path)
        center_ok = inside(tiles, 0.0, 0.0)
        sw_ok = inside(tiles, switch_local[0], switch_local[1])
        near = nearest(tiles, switch_local[0], switch_local[1])
        reach = "可达" if sw_ok else "★不可达（悬空/凹口）"
        nb = f"{near[0]:.2f}m → 最近砖心 ({near[1]:.1f},{near[2]:.1f})" if near else "无砖"
        print(
            f"{room_id:<11}{len(tiles):<6}{str(center_ok):<18}"
            f"{str(switch_local):<14}{reach:<18}{nb}   {note}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
