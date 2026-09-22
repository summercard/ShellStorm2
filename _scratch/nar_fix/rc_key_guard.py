# -*- coding: utf-8 -*-
"""反向对照开关：摘掉 `/ 恢复` `_ensure_room_key_reward` 里的钥匙自检那一行。

幂等（apply/restore 可重复跑，按当前内容判定，不看残留备份），
因为 Bash 工具可能把整段命令跑两遍。
"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\Dungeon3D.gd"
GUARD = "\t\tor not _room_produces_room_key(room)\n"


def load():
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE: 行尾不纯")
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(text: str) -> None:
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n") and b"\r\r" not in data
    open(P, "wb").write(data)


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    text = load()
    present = text.count(GUARD)
    if action == "apply":
        if present == 0:
            print("RC already applied (闸口缺省 = 老行为)")
            return 0
        if present != 1:
            raise SystemExit("ABORT: 闸口命中 %d 次" % present)
        save(text.replace(GUARD, ""))
        print("RC applied: 闸口已摘掉（回到只看调用方 spawn_key 的老行为）")
        return 0
    if action == "restore":
        if present == 1:
            print("already restored")
            return 0
        if present != 0:
            raise SystemExit("ABORT: 闸口命中 %d 次" % present)
        anchor = "\t\tor not room.cleared\n"
        if text.count(anchor) != 1:
            raise SystemExit("ABORT: 还原锚点命中 %d 次" % text.count(anchor))
        save(text.replace(anchor, anchor + GUARD))
        print("restored: 闸口已装回")
        return 0
    raise SystemExit("usage: rc_key_guard.py apply|restore")


if __name__ == "__main__":
    sys.exit(main())
