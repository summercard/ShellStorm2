# -*- coding: utf-8 -*-
"""气泡验收加两条：面板与文字都不许投影。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_speech_bubble_3d.gd"

ANCHOR = (
    "\t_expect(label.alpha_cut == Label3D.ALPHA_CUT_DISCARD,\n"
    "\t\t\"Label3D \u672a\u542f\u7528 alpha \u88c1\u526a\uff08\u79fb\u52a8\u65f6 TAA \u4f1a\u5728\u6587\u5b57\u4e0a\u62d6\u51fa\u6b8b\u5f71\uff09\")\n"
)
ADD = (
    "\t# \u6c14\u6ce1\u662f\u8d34\u5728\u89d2\u8272\u5934\u4e0a\u7684 UI\uff0c**\u4e0d\u8bb8\u5728\u4e16\u754c\u91cc\u6295\u5f71**"
    "\uff082026-09-22 \u4e3b\u4eba\uff1a\u300c\u5934\u4e0a\u7684\u5bf9\u8bdd\u6846\u4f1a\u6295\u5c04\u6295\u5f71\u300d\uff09\u3002\n"
    "\t# \u9762\u677f\u4e0e\u6587\u5b57**\u4e24\u4ef6\u90fd\u8981\u5173**\uff1a`Label3D` \u4e5f\u662f `GeometryInstance3D`\uff0c"
    "\u9ed8\u8ba4\u540c\u6837\u6295\u5f71\u3002\n"
    "\t_expect(panel.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,\n"
    "\t\t\"\u5e95\u677f\u4ecd\u5728\u6295\u5f71\uff08\u5934\u9876\u7684\u5bf9\u8bdd\u6846\u4f1a\u5728\u5730\u9762/\u5899\u4e0a\u7559\u4e0b\u5f71\u5b50\uff09\")\n"
    "\t_expect(label.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,\n"
    "\t\t\"Label3D \u4ecd\u5728\u6295\u5f71\uff08\u6587\u5b57\u4f1a\u5728\u5730\u4e0a\u7559\u4e0b\u5f71\u5b50\uff09\")\n"
)


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if "\u5e95\u677f\u4ecd\u5728\u6295\u5f71" in text:
        print("ALREADY PATCHED")
        return 0
    n = text.count(ANCHOR)
    if n != 1:
        print("ABORT: 锚点命中 %d" % n)
        return 3
    text = text.replace(ANCHOR, ANCHOR + ADD)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
