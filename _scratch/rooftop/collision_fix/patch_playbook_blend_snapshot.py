"""把「res:// 内 .blend 快照会被 Godot 自动导入并注册 uid」这条坑补进
MEMORY-playbooks.md 的「环境 · 脚本快照纪律」小节。CRLF 安全（二进制读写）。
"""

import sys

PATH = r"I:/工作项目/shellstrom2/.workbuddy/memory/MEMORY-playbooks.md"

ANCHOR = (
    "- \u26d4 \u811a\u672c\u5feb\u7167 / `.before.gd` \u7981\u6b62\u843d\u5728 res:// \u5185"
)

NEW_BULLET = (
    "\r\n- \u26a0\ufe0f **`.blend` \u5feb\u7167\u4e5f\u522b\u843d res:// \u5185**\uff1aGodot \u626b\u5230 `*.blend` \u4f1a\u81ea\u52a8\u8d70 scene \u5bfc\u5165\u5668\uff0c\u751f\u6210 `*.blend.import` \u4e0d\u8bf4\uff0c"
    "\u8fd8\u4f1a\u5728 `.godot/imported/` \u843d\u4e00\u4efd `.scn` \u5e76\u6ce8\u518c\u4e00\u4e2a\u5168\u5c40 uid\uff08\u5728 `_scratch/` \u4e0b\u5b9e\u6d4b\u5230 8 \u5904\uff09\u3002"
    "\u5feb\u7167\u8bf7\u6539\u540d\u6210\u975e\u53ef\u5bfc\u5165\u540e\u7f00\uff08\u5982 `.blend.bak` / `*.blend.before`\uff09\uff1b\u7eaf `.before` \u540e\u7f00\u4e0d\u4f1a\u88ab\u5bfc\u5165\u3002"
)

with open(PATH, "rb") as f:
    raw = f.read()

n_crlf = raw.count(b"\r\n")
n_lone_lf = raw.count(b"\n") - n_crlf
if n_lone_lf != 0:
    sys.exit("ABORT: %s has %d lone LF (expect CRLF-pure)" % (PATH, n_lone_lf))

anchor_bytes = ANCHOR.encode("utf-8")

# 找「环境 · 脚本快照纪律」小节里那条 bullet 所在行的行尾，把新 bullet 插在它后面。
head = "\u73af\u5883 \u00b7 \u811a\u672c\u5feb\u7167\u7eaa\u5f8b".encode("utf-8")
sec = raw.find(head)
if sec < 0:
    sys.exit("ABORT: section heading not found")

pos = raw.find(anchor_bytes, sec)
if pos < 0:
    sys.exit("ABORT: anchor bullet not found inside section")

line_end = raw.find(b"\r\n", pos)
if line_end < 0:
    sys.exit("ABORT: no CRLF after anchor line")

if NEW_BULLET.encode("utf-8").strip() in raw:
    sys.exit("ABORT: bullet already present (idempotent guard)")

out = raw[: line_end] + NEW_BULLET.encode("utf-8") + raw[line_end:]

with open(PATH, "wb") as f:
    f.write(out)

with open(PATH, "rb") as f:
    chk = f.read()
assert chk.count(b"\n") - chk.count(b"\r\n") == 0, "post-write lone LF introduced"
print("PATCH_OK bytes %d -> %d; crlf=%d" % (len(raw), len(chk), chk.count(b"\r\n")))
