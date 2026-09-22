# -*- coding: utf-8 -*-
"""清掉冗余的 label 行与其「永不失败」的断言。

实测（`_scratch/nar_fix/probe_default_shadow.gd`）：
    Label3D.cast_shadow        = 0 = SHADOW_CASTING_SETTING_OFF   ← 引擎默认就不投影
    MeshInstance3D.cast_shadow = 1 = SHADOW_CASTING_SETTING_ON    ← 元凶
所以真正要关的只有底板；给 Label3D 再写一行 OFF 不但冗余，还会让对应断言永远为绿。
"""

import sys

SRC = r"I:\工作项目\shellstrom2\ShellStorm2\src\ui\bubble\SpeechBubble3D.gd"
TEST = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_speech_bubble_3d.gd"

SRC_OLD = (
    "\t_label.double_sided = true\n"
    "\t_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n"
    "\tadd_child(_label)\n"
)
SRC_NEW = (
    "\t_label.double_sided = true\n"
    "\tadd_child(_label)\n"
)

SRC_DOC_OLD = (
    "\t# 气泡是**贴在角色头上的 UI**，不该在世界里落投影（2026-09-22 主人要求）。\n"
    "\t# ⚠️ 面板与文字**两件都要关**：`Label3D` 也是 `GeometryInstance3D`，默认同样投影 ——\n"
    "\t# 只关 MeshInstance3D 的话，地上仍会留着文字的影子。\n"
)
SRC_DOC_NEW = (
    "\t# 气泡是**贴在角色头上的 UI**，不该在世界里落投影（2026-09-22 主人要求）。\n"
    "\t# ⚠️ 元凶只有**底板**：`MeshInstance3D.cast_shadow` 默认 ON；\n"
    "\t# `Label3D` 的默认值**实测就是 OFF**（`_scratch/nar_fix/probe_default_shadow.gd`，\n"
    "\t# Label3D=0 / MeshInstance3D=1），所以文字那件不需要（写了也是死代码）。\n"
)

TEST_OLD = (
    "\t_expect(label.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,\n"
    "\t\t\"Label3D \u4ecd\u5728\u6295\u5f71\uff08\u6587\u5b57\u4f1a\u5728\u5730\u4e0a\u7559\u4e0b\u5f71\u5b50\uff09\")\n"
)
TEST_NEW = (
    "\t# \u26d0 \u4e0d\u8981\u7ed9 Label3D \u5199\u8fd9\u6761\uff1a\u5b83\u7684 `cast_shadow` **\u9ed8\u8ba4\u5c31\u662f OFF**\n"
    "\t# \uff08\u5b9e\u6d4b Label3D=0 / MeshInstance3D=1\uff09\uff0c\u65ad\u8a00\u6c38\u8fdc\u4e3a\u7eff = \u5047\u7eff\u3002\n"
)


def patch(path: str, subs, label: str) -> None:
    raw = open(path, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE %s: 行尾不纯" % path)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for old, new, tag in subs:
        if old not in text:
            if new in text:
                print("%s/%s already" % (label, tag))
                continue
            raise SystemExit("ABORT %s/%s: 锚点不存在" % (label, tag))
        n = text.count(old)
        if n != 1:
            raise SystemExit("ABORT %s/%s: 锚点命中 %d" % (label, tag, n))
        text = text.replace(old, new)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write %s" % path)
    open(path, "wb").write(data)
    print("%s OK CR=%d LF=%d" % (label, data.count(b"\r"), data.count(b"\n")))


def main() -> int:
    patch(SRC, [(SRC_DOC_OLD, SRC_DOC_NEW, "doc"), (SRC_OLD, SRC_NEW, "line")], "bubble")
    patch(TEST, [(TEST_OLD, TEST_NEW, "assert")], "test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
