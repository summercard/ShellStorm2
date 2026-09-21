# -*- coding: utf-8 -*-
"""反向对照开关：apply 让 reset_run_state() 变成"没复位"（不 clear _armed），restore 还原。

用法：python rc_toggle.py apply | restore
"""
import os
import shutil
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeDirector3D.gd"
BAK = P + ".rcbak"

ANCHOR = (
    "\t# 先清空再重挂：arm() 会从既有登记里**继承** fired_count，不清空等于没复位。\n"
    "\t_armed.clear()\n"
)
BROKEN = (
    "\t# 先清空再重挂：arm() 会从既有登记里**继承** fired_count，不清空等于没复位。\n"
    "\t# _armed.clear()  # RC: 故意不复位，C5 必须变红\n"
)


def write(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(path, "wb").write(data)


def load(path):
    raw = open(path, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
    return raw.decode("utf-8").replace("\r\n", "\n")


mode = sys.argv[1] if len(sys.argv) > 1 else ""

if mode == "apply":
    if os.path.exists(BAK):
        raise SystemExit("备份已存在，先 restore")
    shutil.copy2(P, BAK)
    text = load(P)
    assert text.count(ANCHOR) == 1, "锚点命中 %d 次" % text.count(ANCHOR)
    write(P, text.replace(ANCHOR, BROKEN))
    print("RC_APPLIED（reset_run_state 不再复位）")
elif mode == "restore":
    if not os.path.exists(BAK):
        raise SystemExit("没有备份")
    shutil.copy2(BAK, P)
    os.remove(BAK)
    text = load(P)
    assert text.count(ANCHOR) == 1, "还原后锚点异常"
    print("RC_RESTORED")
else:
    raise SystemExit("用法: apply | restore")
