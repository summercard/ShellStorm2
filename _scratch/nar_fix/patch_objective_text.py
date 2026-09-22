# -*- coding: utf-8 -*-
"""HUD 目标文案：门不消耗钥匙的房间不该提示「用钥匙开门选择路线」。

主人截图里那行 `搜索剩余物资，用钥匙开门选择路线` 就贴在钥匙旁边 ——
和钥匙产出是**同一类**「区域声明没接上」：文案只看「我有没有钥匙」，
不看「这扇门要不要钥匙」。
"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\TowerDescent3D.gd"

A_OLD = (
    '\tif _get_total_room_keys() <= 0:\n'
    '\t\treturn "\u533a\u57df\u5df2\u8083\u6e05 \u00b7 \u62fe\u53d6\u6389\u843d\u94a5\u5319\uff0c\u518d\u9009\u62e9\u4e0b\u4e00\u6247\u95e8"\n'
)
A_NEW = (
    '\t# \u95e8\u4e0d\u6d88\u8017\u94a5\u5319\u7684\u623f\u95f4\uff08\u548c\u5e73\u533a\u5982 98F \u533a\u575700\uff09\u4e0d\u8be5\u63d0\u94a5\u5319\uff1a\n'
    '\t# \u5426\u5219 HUD \u4f1a\u4e00\u8fb9\u5199\u300c\u7528\u94a5\u5319\u5f00\u95e8\u300d\u3001\u4e00\u8fb9\u5730\u4e0a\u6ca1\u94a5\u5319\u4e5f\u4e0d\u9700\u8981\u94a5\u5319\u3002\n'
    '\tif not _room_produces_room_key(room):\n'
    '\t\treturn "\u533a\u57df\u5df2\u8083\u6e05 \u00b7 \u76f4\u63a5\u5f00\u542f\u4e0b\u4e00\u6247\u95e8"\n'
    '\tif _get_total_room_keys() <= 0:\n'
    '\t\treturn "\u533a\u57df\u5df2\u8083\u6e05 \u00b7 \u62fe\u53d6\u6389\u843d\u94a5\u5319\uff0c\u518d\u9009\u62e9\u4e0b\u4e00\u6247\u95e8"\n'
)

B_OLD = (
    '\tif _get_total_room_keys() <= 0:\n'
    '\t\treturn "\u623f\u95f4\u5df2\u8083\u6e05 \u00b7 \u62fe\u53d6\u6389\u843d\u94a5\u5319\uff0c\u518d\u9009\u62e9\u4e0b\u4e00\u6247\u95e8"\n'
)
B_NEW = (
    '\tif not _room_produces_room_key(room):\n'
    '\t\treturn "\u623f\u95f4\u5df2\u8083\u6e05 \u00b7 \u76f4\u63a5\u5f00\u542f\u4e0b\u4e00\u6247\u95e8"\n'
    '\tif _get_total_room_keys() <= 0:\n'
    '\t\treturn "\u623f\u95f4\u5df2\u8083\u6e05 \u00b7 \u62fe\u53d6\u6389\u843d\u94a5\u5319\uff0c\u518d\u9009\u62e9\u4e0b\u4e00\u6247\u95e8"\n'
)

A_DOC_OLD = "\u672c\u623f\u8be5\u4e0d\u8be5\u4ea7\u51fa\u300c\u623f\u95f4\u94a5\u5319\u300d\u5956\u52b1\u3002\n"
A_DOC_NEW = (
    "\u672c\u623f\u8be5\u4e0d\u8be5\u4ea7\u51fa\u300c\u623f\u95f4\u94a5\u5319\u300d\u5956\u52b1"
    "\uff08= \u672c\u623f\u7684\u95e8\u662f\u5426\u6d88\u8017\u94a5\u5319\uff09\u3002\n"
    "\uff08\u540c\u4e00\u5224\u636e\u4e5f\u7ed9 HUD \u76ee\u6807\u6587\u6848\u7528\uff1a\u4e0d\u6d88\u8017\u94a5\u5319\u65f6\u4e0d\u63d0\u300c\u7528\u94a5\u5319\u5f00\u95e8\u300d\u3002\uff09\n"
)


def main() -> int:
    # ---- 1) TowerDescent3D 的两处 HUD 文案 ----
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: TowerDescent3D 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if "_room_produces_room_key(room):\n\t\treturn \"\u533a\u57df\u5df2\u8083\u6e05 \u00b7 \u76f4\u63a5" in text:
        print("TowerDescent3D ALREADY PATCHED")
    else:
        for old, new, tag in ((A_OLD, A_NEW, "journey"), (B_OLD, B_NEW, "expedition")):
            n = text.count(old)
            if n != 1:
                print("ABORT %s: 锚点命中 %d" % (tag, n))
                return 3
            text = text.replace(old, new)
        data = text.replace("\n", "\r\n").encode("utf-8")
        if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
            print("ABORT: TowerDescent3D 行尾异常")
            return 4
        open(P, "wb").write(data)
        print("TowerDescent3D OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))

    # ---- 2) Dungeon3D 里那个 helper 的注释顺带说清第二用途 ----
    Q = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\Dungeon3D.gd"
    raw = open(Q, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: Dungeon3D 行尾不纯")
        return 5
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if A_DOC_NEW in text:
        print("Dungeon3D doc ALREADY PATCHED")
    else:
        n = text.count(A_DOC_OLD)
        if n != 1:
            print("ABORT doc: 锚点命中 %d" % n)
            return 6
        text = text.replace(A_DOC_OLD, A_DOC_NEW)
        data = text.replace("\n", "\r\n").encode("utf-8")
        if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
            print("ABORT: Dungeon3D 行尾异常")
            return 7
        open(Q, "wb").write(data)
        print("Dungeon3D OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
