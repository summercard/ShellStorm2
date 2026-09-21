# -*- coding: utf-8 -*-
"""反向对照（幂等/状态感知）：临时断开 BaseManager 复位信号订阅。

apply   : 文件处于正常态 → 快照到 .rcbak2 并断开；已断开 → 不重复动作
restore : 有备份 → 还原并删备份；无备份且文件已正常 → no-op
同时打印 sha256，便于确认还原到同一内容。
"""
import hashlib
import os
import shutil
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeDirector3D.gd"
BAK = P + ".rcbak2"

ANCHOR = "\t\tBaseManager.game_save_reset_completed.connect(_on_game_save_reset_completed)\n"
BROKEN = "\t\tpass  # RC: 故意不接，接线守卫必须变红\n"


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


def write(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(path, "wb").write(data)


def load(path):
    raw = open(path, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
    return raw.decode("utf-8").replace("\r\n", "\n")


mode = sys.argv[1] if len(sys.argv) > 1 else ""
text = load(P)

if mode == "apply":
    if BROKEN in text:
        print("ALREADY_APPLIED sha=%s" % sha(P))
    elif ANCHOR in text:
        shutil.copy2(P, BAK)
        write(P, text.replace(ANCHOR, BROKEN))
        print("APPLIED sha=%s" % sha(P))
    else:
        raise SystemExit("状态未知，人工检查")
elif mode == "restore":
    if os.path.exists(BAK):
        shutil.copy2(BAK, P)
        os.remove(BAK)
        print("RESTORED sha=%s" % sha(P))
    elif ANCHOR in text:
        print("ALREADY_NORMAL sha=%s" % sha(P))
    else:
        raise SystemExit("无备份且文件非正常态，人工检查")
else:
    raise SystemExit("用法: apply | restore")
