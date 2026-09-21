# -*- coding: utf-8 -*-
"""补：复位存档→导演 的接线面守卫（断了只会表现为"复位档后不播开场"，运行时零报错）。"""
import os

TEST = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_narrative_timeline.gd"
DOC = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"

TEST_ANCHOR = "\t_check(_dungeon_binding_wired(), \"room_entered 信号节点入树即被导演绑定（触发链接线面）\")\n"
TEST_NEW = TEST_ANCHOR + (
    "\t# 第三处" + "\"断了也不报错\"" + "的接线：复位存档 = 新档，本局内存态必须归零。\n"
    "\t# 这条断了只表现为「复位存档 → 重新开始后开场剧本不播」，运行时没有任何报错。\n"
    "\t_check(\n"
    "\t\tBaseManager != null\n"
    "\t\tand BaseManager.game_save_reset_completed.is_connected(\n"
    "\t\t\tCallable(NarrativeDirector, \"_on_game_save_reset_completed\")\n"
    "\t\t),\n"
    "\t\t\"复位存档信号已接入导演（否则复位档后冷启动开场不再播，运行时零报错）\",\n"
    "\t)\n"
)

DOC_OLD = "三层 **90 项**检查"
DOC_NEW = "三层 **91 项**检查"


def patch(path, pairs):
    raw = open(path, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s CRLF=%d LF=%d" % (path, crlf, lf)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for label, a, b in pairs:
        n = text.count(a)
        assert n == 1, "锚点『%s』命中 %d 次" % (label, n)
        text = text.replace(a, b)
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(path, "wb").write(data)
    print("patched %s CR=%d LF=%d" % (os.path.basename(path), data.count(b"\r"), data.count(b"\n")))


patch(TEST, [("wiring-guard", TEST_ANCHOR, TEST_NEW)])
patch(DOC, [("doc-count", DOC_OLD, DOC_NEW)])
print("DONE")
