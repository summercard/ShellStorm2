# -*- coding: utf-8 -*-
"""反向对照：把 _apply_camera_pose 的枢轴写死回玩家 ⇒ C6 的 pivot_m/last_spawn/room_center 必须变红。"""
import hashlib
import os
import shutil
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeAdapter3D.gd"
BAK = P + ".rcbak"
ANCHOR = "\tvar center := _current_camera_pivot(player)\n"
BROKEN = "\tvar center := player.global_position  # RC: 枢轴写死玩家\n"


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]


def load():
    raw = open(P, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(P, "wb").write(data)


mode = sys.argv[1] if len(sys.argv) > 1 else ""
t = load()
if mode == "apply":
    if BROKEN in t:
        print("ALREADY_APPLIED sha=%s" % sha(P))
    elif t.count(ANCHOR) == 1:
        shutil.copy2(P, BAK)
        save(t.replace(ANCHOR, BROKEN))
        print("APPLIED sha=%s" % sha(P))
    else:
        raise SystemExit("锚点命中 %d" % t.count(ANCHOR))
elif mode == "restore":
    if os.path.exists(BAK):
        shutil.copy2(BAK, P)
        os.remove(BAK)
        print("RESTORED sha=%s" % sha(P))
    else:
        raise SystemExit("没有备份")
else:
    raise SystemExit("用法: apply | restore")
