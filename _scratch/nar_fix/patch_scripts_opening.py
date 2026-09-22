# -*- coding: utf-8 -*-
"""两条开场剧本的改动：
① 01 尾段补「转向地上的枪 → 对着枪说『那是主人留下的礼物。。』→ 再解锁」；
② 02 台词改「黑暗中是什么东西！」，并加系统提示「…按F开启手电」。
"""

import json
import sys

S1 = r"I:\工作项目\shellstrom2\ShellStorm2\data\narrative\nar_tower_opening_01_wake.json"
S2 = r"I:\工作项目\shellstrom2\ShellStorm2\data\narrative\nar_tower_opening_02_zombies.json"

DROP_OFFSET = [5.3, 0.05, -0.7]
DROP_ROOM = "floor_01_exit"


def read_crlf(path: str) -> str:
    raw = open(path, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE %s: 行尾不纯" % path)
    return raw.decode("utf-8").replace("\r\n", "\n")


def write_crlf(path: str, text: str) -> None:
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write %s: 行尾异常" % path)
    open(path, "wb").write(data)


def dump(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    # ---------- 剧本 01 ----------
    t1 = read_crlf(S1)
    d1 = json.loads(t1)
    if any(str(c.get("do")) == "actor.face" and "to_point_room" in c for c in d1["cues"]):
        print("剧本 01 already patched")
    else:
        tail = [
            {
                "at": 14.4,
                "do": "actor.face",
                "to_point_room": DROP_ROOM,
                "to_point_offset": DROP_OFFSET,
                "duration": 0.6,
            },
            {
                "at": 15.2,
                "do": "actor.say",
                "text": "那是主人留下的礼物。。",
                "hold": 2.4,
            },
            {
                "at": 18.0,
                "do": "flow.end",
            },
        ]
        # 原有的 flow.end 由上面的 18.0 取代（先摘旧的后接新的）。
        d1["cues"] = [c for c in d1["cues"] if str(c.get("do")) != "flow.end"] + tail
        d1["duration"] = 18.0
        write_crlf(S1, dump(d1))
        print("剧本 01 patched -> duration=%.1f cues=%d" % (d1["duration"], len(d1["cues"])))

    # ---------- 剧本 02 ----------
    t2 = read_crlf(S2)
    d2 = json.loads(t2)
    changed = False
    for cue in d2["cues"]:
        if str(cue.get("do")) == "actor.say" and str(cue.get("text", "")) == "它们是什么？":
            cue["text"] = "黑暗中是什么东西！"
            changed = True
    if not any(str(c.get("do")) == "ui.hint" for c in d2["cues"]):
        d2["cues"] = [c for c in d2["cues"] if str(c.get("do")) != "flow.end"]
        d2["cues"].append(
            {
                "at": 6.4,
                "do": "ui.hint",
                "text": "打开你身上的手电，那里有危险！按F开启手电",
                "auto": 4.0,
            }
        )
        d2["cues"].append({"at": 10.6, "do": "flow.end"})
        d2["duration"] = 10.6
        changed = True
    if changed:
        d2["cues"].sort(key=lambda c: float(c.get("at", 0.0)))
        write_crlf(S2, dump(d2))
        print("剧本 02 patched -> duration=%.1f cues=%d" % (d2["duration"], len(d2["cues"])))
    else:
        print("剧本 02 no change")
    return 0


if __name__ == "__main__":
    sys.exit(main())
