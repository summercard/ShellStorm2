# -*- coding: utf-8 -*-
"""修：src/narrative/** 禁节点路径字面量 ⇒ 改用 autoload 全局标识引用 BaseManager。

（验收 `_no_path_literals` 禁止 `get_node("` / `get_node_or_null("` / `NodePath("` / `"../`）
本文件既有的 `if DialogueUI != null ...` 就是同一种写法。
"""
import os

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeDirector3D.gd"

OLD = (
    "\tvar save_service := get_node_or_null(\"/root/BaseManager\")\n"
    "\tif save_service != null and save_service.has_signal(\"game_save_reset_completed\"):\n"
    "\t\tsave_service.game_save_reset_completed.connect(_on_game_save_reset_completed)\n"
    "\telse:\n"
)
NEW = (
    "\t# \u26d4 不可用节点路径取 autoload（src/narrative/** 禁路径字面量，唯一耦合点是适配器）：\n"
    "\t#    autoload 全局标识是既有写法（本文件的 DialogueUI 同款）。\n"
    "\tif BaseManager != null and BaseManager.has_signal(\"game_save_reset_completed\"):\n"
    "\t\tBaseManager.game_save_reset_completed.connect(_on_game_save_reset_completed)\n"
    "\telse:\n"
)

raw = open(P, "rb").read()
crlf = raw.count(b"\r\n")
lf = raw.count(b"\n")
assert crlf and crlf == lf, "行尾不纯 CRLF=%d LF=%d" % (crlf, lf)
text = raw.decode("utf-8").replace("\r\n", "\n")

assert text.count(OLD) == 1, "旧片段命中 %d 次" % text.count(OLD)
text = text.replace(OLD, NEW)

data = text.replace("\n", "\r\n").encode("utf-8")
open(P, "wb").write(data)
print("fixed CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))

# 自检：确认禁用 token 不再出现在非注释行
forbidden = ["get_node(\"", "get_node_or_null(\"", "NodePath(\"", "\"../"]
bad = []
for i, line in enumerate(text.split("\n"), 1):
    s = line.strip()
    if s.startswith("#"):
        continue
    for tok in forbidden:
        if tok in s:
            bad.append((i, tok))
print("forbidden_hits", bad if bad else "none")
