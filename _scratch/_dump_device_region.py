# -*- coding: utf-8 -*-
"""打印 room_01 live 版的头部区域（根 + 设备块 + 紧跟的组件），人工确认块边界。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
INST = os.path.join(ROOT, "assets", "art", "environments", "tower_zones",
                    "expedition", "runtime", "room_instances", "expedition_01")
BAK = os.path.join(ROOT, "_scratch", "_before_move")


def show(path, lo, hi, title):
    with open(path, "r", encoding="utf-8", newline="") as f:
        lines = f.read().split("\n")
    print("===== %s  (%s) 共%d行 =====" % (title, os.path.basename(path), len(lines)))
    for i in range(lo - 1, min(hi, len(lines))):
        print("%4d| %s" % (i + 1, lines[i]))
    print()


n1 = "f00_room_01_static_layout.tscn"
show(os.path.join(INST, n1), 25, 82, "live room_01")
show(os.path.join(BAK, n1), 838, 871, "before_move room_01")
