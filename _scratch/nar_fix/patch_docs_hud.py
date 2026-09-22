# -*- coding: utf-8 -*-
"""把「HUD 文案」这项补进 08 文档 §13.6 / 事务文件 / playbooks。幂等。"""

import os
import sys

DOC = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"
TXN = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-22\1352_98F和平区钥匙产出闸口.md"
PB = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY-playbooks.md"

ROW3_ANCHOR = "\u95f8\u53e3\u81ea\u68c0\u3001\u4e0d\u4fe1\u8c03\u7528\u65b9\u5f62\u53c2** |\n"
ROW3 = (
    "| 3 | \u95e8\u4e0d\u8981\u94a5\u5319\u3001\u5730\u4e0a\u4e5f\u6ca1\u94a5\u5319\uff0c"
    "HUD \u5374\u5199\u7740\u300c\u641c\u7d22\u5269\u4f59\u7269\u8d44\uff0c**\u7528\u94a5\u5319\u5f00\u95e8**\u9009\u62e9\u8def\u7ebf\u300d | "
    "`_journey_objective()` / `_expedition_objective()` \u53ea\u770b\u300c\u6211\u6709\u6ca1\u6709\u94a5\u5319\u300d"
    "\uff08`_get_total_room_keys() <= 0`\uff09\uff0c**\u4e0d\u770b\u8fd9\u6247\u95e8\u8981\u4e0d\u8981\u94a5\u5319** | "
    "\u540c\u4e00\u58f0\u660e `_room_produces_room_key(room)` \u524d\u7f6e\u4e00\u6863\uff1a"
    "\u4e0d\u6d88\u8017\u94a5\u5319\u7684\u623f\u95f4\u8fd4\u56de\u300c\u533a\u57df\u5df2\u8083\u6e05 \u00b7 \u76f4\u63a5\u5f00\u542f\u4e0b\u4e00\u6248\u95e8\u300d |\n"
)

DOC_EXTRA_ANCHOR = "(\u5b9e\u6d4b\u56db\u623f\u5404\u95e8\u63d0\u793a\u8bed\u662f `[E] \u5f00\u542f\u901a\u9053`\uff0c\u4e0d\u662f `[E] \u4f7f\u7528\u623f\u95f4\u94a5\u5319`\u3002)\n"
DOC_EXTRA = (
    "\u53e6\u5916 H \u6bb5\u628a **HUD \u76ee\u6807\u6587\u6848**\u4e5f\u76ef\u4f4f\u4e86\uff1a\u548c\u5e73\u533a\u7684 `_journey_objective()` "
    "\u5b9e\u6d4b\u8fd4\u56de\u300c\u533a\u57df\u5df2\u8083\u6e05 \u00b7 \u76f4\u63a5\u5f00\u542f\u4e0b\u4e00\u6248\u95e8\u300d\uff0c\u4e0d\u518d\u63d0\u94a5\u5319\u3002\n"
)

TXN_ANCHOR = "## \u9a8c\u6536\n"
TXN_ADD = """## \u7b2c\u4e09\u9762\uff1aHUD \u76ee\u6807\u6587\u6848\uff08\u540c\u4e00\u7c7b\u300c\u6ca1\u63a5\u4e0a\u7684\u7ebf\u300d\uff09

\u4e3b\u4eba\u622a\u56fe\u91cc\u94a5\u5319\u65c1\u8fb9\u5c31\u662f\u90a3\u884c
`\u641c\u7d22\u5269\u4f59\u7269\u8d44\uff0c\u7528\u94a5\u5319\u5f00\u95e8\u9009\u62e9\u8def\u7ebf`\u3002
`_journey_objective()` / `_expedition_objective()` \u53ea\u770b\u300c\u6211\u6709\u6ca1\u6709\u94a5\u5319\u300d
\uff08`_get_total_room_keys() <= 0`\uff09\uff0c**\u770b\u4e0d\u770b\u8fd9\u6247\u95e8\u8981\u4e0d\u8981\u94a5\u5319** \u2014\u2014
\u6240\u4ee5\u5730\u4e0a\u6ca1\u94a5\u5319\u65f6\u5b83\u5199\u300c\u62fe\u53d6\u6389\u843d\u94a5\u5319\u300d\uff0c\u6709\u94a5\u5319\u65f6\u5199\u300c\u7528\u94a5\u5319\u5f00\u95e8\u300d\uff0c
\u4e24\u53e5\u5728\u548c\u5e73\u533a\u90fd\u662f\u5047\u7684\u3002\u73b0\u7528\u540c\u4e00\u58f0\u660e `_room_produces_room_key(room)` \u524d\u7f6e\u4e00\u6863\u3002

\u26a0\ufe0f \u8fd9\u6b21\u6539\u52a8\u81ea\u5df1\u8e29\u4e86\u4e00\u4e2a\u5751\uff08\u503c\u5f97\u8bb0\uff09\uff1a\u7ed9\u6ce8\u91ca\u5757\u63d2\u884c\u65f6\u6f0f\u4e86 `## ` \u524d\u7f00\uff0c
\u90a3\u4e00\u884c\u76f4\u63a5\u53d8\u6210\u4ee3\u7801 \u21d2 `Dungeon3D.gd` \u6574\u4e2a\u89e3\u6790\u5931\u8d25 \u21d2 \u4f9d\u8d56\u5b83\u7684
`TowerDescent3D` / `MonsterAIManager` \u8fde\u9501\u5931\u8d25 \u21d2 \u63a2\u9488**\u6839\u672c\u6ca1\u8d77\u6765**\uff0c
\u65e5\u5fd7\u91cc\u53ea\u6709 `Could not parse global class ...`\uff0c\u4e14\u8fdb\u7a0b\u6302\u7740\u4e0d\u9000\u3002
\u6240\u4ee5\uff1a**\u6539\u6ce8\u91ca\u540e\u5fc5\u987b\u7528 `cat -A` \u770b\u884c\u9996**\uff0c\u4e0d\u80fd\u53ea\u770b\u5185\u5bb9\u3002

"""

PB_ANCHOR = "- **`door_policies` \u4e00\u8def\u53cc\u843d**"
PB_ADD = """- **HUD \u76ee\u6807\u6587\u6848\u4e5f\u5403\u8fd9\u4efd\u58f0\u660e**\uff1a`TowerDescent3D._journey_objective()` / `_expedition_objective()`
  \u539f\u672c\u53ea\u770b `_get_total_room_keys() <= 0`\uff08\u6211\u6709\u6ca1\u6709\u94a5\u5319\uff09\uff0c\u4e0d\u770b\u300c\u8fd9\u6247\u95e8\u8981\u4e0d\u8981\u94a5\u5319\u300d
  \u21d2 \u548c\u5e73\u533a HUD \u4f1a\u5199\u300c\u7528\u94a5\u5319\u5f00\u95e8\u9009\u62e9\u8def\u7ebf\u300d\u3002\u73b0\u7528 `_room_produces_room_key(room)` \u524d\u7f6e\u4e00\u6863\u3002
  \u26a0\ufe0f \u6539\u6ce8\u91ca\u5757\u65f6**\u5fc5\u987b\u770b\u884c\u9996**\uff1a\u6f0f\u4e00\u4e2a `## ` \u5c31\u628a\u90a3\u884c\u53d8\u6210\u4ee3\u7801\uff0c
  `Dungeon3D.gd` \u89e3\u6790\u5931\u8d25 \u21d2 `TowerDescent3D` / `MonsterAIManager` \u8fde\u9501\u5931\u8d25 \u21d2 \u63a2\u9488\u6839\u672c\u8d77\u4e0d\u6765\u3001\u8fdb\u7a0b\u6302\u4f4f\u3002
"""


def patch(path, anchor, add, dup_marker) -> bool:
    raw = open(path, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE %s: 行尾不纯" % path)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if dup_marker in text:
        print("%s: already" % os.path.basename(path))
        return True
    n = text.count(anchor)
    if n != 1:
        print("SKIP %s: 锚点命中 %d" % (os.path.basename(path), n))
        return False
    text = text.replace(anchor, anchor + add)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write %s" % path)
    open(path, "wb").write(data)
    print("%s OK CR=%d LF=%d" % (os.path.basename(path), data.count(b"\r"), data.count(b"\n")))
    return True


def main() -> int:
    # 每项独立 try：一处锚点没命中不许拖累其它三项。
    patch(DOC, ROW3_ANCHOR, ROW3, "\u76f4\u63a5\u5f00\u542f\u4e0b\u4e00\u6248\u95e8\u300d |")
    patch(DOC, DOC_EXTRA_ANCHOR, DOC_EXTRA, "\u76ef\u4f4f\u4e86\uff1a\u548c\u5e73\u533a\u7684")
    patch(TXN, TXN_ANCHOR, TXN_ADD, "## \u7b2c\u4e09\u9762\uff1aHUD")
    patch(PB, PB_ANCHOR, PB_ADD, "HUD \u76ee\u6807\u6587\u6848\u4e5f\u5403\u8fd9\u4efd\u58f0\u660e")
    return 0


if __name__ == "__main__":
    sys.exit(main())
