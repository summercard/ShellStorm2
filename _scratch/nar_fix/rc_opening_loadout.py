# -*- coding: utf-8 -*-
"""反向对照开关（幂等，按当前内容判定，可重复跑）：

apply = 同时改坏两处：
  ① 塔楼落位常量 5.3 → 2.0（枪会离门 6m+，且与剧本的 to_point_offset 不再同值）
  ② 剧本 01 的 flow.end 18.0 → 15.0（挪到台词之前 ⇒ 「说完才解锁」不再成立）
restore = 还原两处。
"""

import json
import sys

TD = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\TowerDescent3D.gd"
S1 = r"I:\工作项目\shellstrom2\ShellStorm2\data\narrative\nar_tower_opening_01_wake.json"

GOOD_CONST = "const NEW_GAME_OPENING_DROP_OFFSET := Vector3(5.3, 0.05, -0.7)\n"
BAD_CONST = "const NEW_GAME_OPENING_DROP_OFFSET := Vector3(2.0, 0.05, -0.7)\n"


def read_text(path: str) -> str:
    raw = open(path, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE %s: 行尾不纯" % path)
    return raw.decode("utf-8").replace("\r\n", "\n")


def write_text(path: str, text: str) -> None:
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write %s" % path)
    open(path, "wb").write(data)


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    # ① 常量
    t = read_text(TD)
    if action == "apply":
        if BAD_CONST in t:
            print("const: already applied")
        elif GOOD_CONST in t:
            write_text(TD, t.replace(GOOD_CONST, BAD_CONST))
            print("const: applied (5.3 -> 2.0)")
        else:
            raise SystemExit("ABORT const: 两个值都不在")
    elif action == "restore":
        t = read_text(TD)
        if GOOD_CONST in t:
            print("const: already restored")
        elif BAD_CONST in t:
            write_text(TD, t.replace(BAD_CONST, GOOD_CONST))
            print("const: restored")
        else:
            raise SystemExit("ABORT const: 两个值都不在")
    else:
        raise SystemExit("usage: rc_opening_loadout.py apply|restore")

    # ② 剧本 flow.end
    t = read_text(S1)
    d = json.loads(t)
    ends = [c for c in d["cues"] if str(c.get("do")) == "flow.end"]
    if len(ends) != 1:
        raise SystemExit("ABORT script: flow.end 有 %d 条" % len(ends))
    cur = float(ends[0]["at"])
    target = 15.0 if action == "apply" else 18.0
    if cur == target:
        print("script: already %s (%.1f)" % (action, cur))
    else:
        ends[0]["at"] = target
        if action == "apply":
            d["duration"] = 15.0
        else:
            d["duration"] = 18.0
        write_text(S1, json.dumps(d, ensure_ascii=False, indent=2) + "\n")
        print("script: flow.end %.1f -> %.1f" % (cur, target))
    return 0


if __name__ == "__main__":
    sys.exit(main())
