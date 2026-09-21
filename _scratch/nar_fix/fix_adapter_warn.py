# -*- coding: utf-8 -*-
"""修两处：① 适配器补自己的 _warn；② 从 Dictionary 取 Variant 回 Vector3 必须显式定型。"""
import os

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeAdapter3D.gd"


def load():
    raw = open(P, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(P, "wb").write(data)
    print("wrote CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))


t = load()

# ① 补 _warn
A1 = "static func _ok() -> Dictionary:\n"
B1 = (
    "## 适配器自己的告警口。与导演的 _warn 同义：**只用于错用/接线缺口**\n"
    "## （例如 camera.pivot 写错），不影响时间轴照走；正常路径一声不响。\n"
    "func _warn(message: String) -> void:\n"
    "\tpush_warning(\"[NarrativeAdapter3D] %s\" % message)\n"
    "\n"
    "\n"
    + A1
)
assert t.count(A1) == 1, "锚点 _ok 命中 %d" % t.count(A1)
t = t.replace(A1, B1)

# ② 显式定型
A2 = (
    "\tif not _camera_pivot_channel.is_empty():\n"
    "\t\treturn _camera_pivot_channel.get(\"value\", player.global_position)\n"
    "\treturn _resolve_camera_pivot(player)\n"
)
B2 = (
    "\tif not _camera_pivot_channel.is_empty():\n"
    "\t\t# 显式定型：Dictionary.get 返回 Variant，直接 return 会撞「警告即错误」。\n"
    "\t\tvar value: Vector3 = _camera_pivot_channel.get(\"value\", player.global_position)\n"
    "\t\treturn value\n"
    "\treturn _resolve_camera_pivot(player)\n"
)
assert t.count(A2) == 1, "锚点 pivot-value 命中 %d" % t.count(A2)
t = t.replace(A2, B2)

save(t)
print("FIX_DONE")
