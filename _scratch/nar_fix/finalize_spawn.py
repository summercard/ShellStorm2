# -*- coding: utf-8 -*-
"""① 定稿剧本 02 的刷怪参数；② C2 加「整条队列在玩家前方」回归断言；③ 文档项数；④ skill 补坑 21。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
JSON02 = os.path.join(ROOT, "data", "narrative", "nar_tower_opening_02_zombies.json")
TEST = os.path.join(ROOT, "tests", "verification", "verify_narrative_timeline.gd")
DOC = os.path.join(ROOT, "docs", "v0.1", "08_技术施工_剧情触发.md")
SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"


def load(path):
    raw = open(path, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s CRLF=%d LF=%d" % (path, crlf, lf)
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(path, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(path), data.count(b"\r"), data.count(b"\n")))


def patch(path, pairs):
    t = load(path)
    for label, a, b in pairs:
        n = t.count(a)
        assert n == 1, "锚点『%s』命中 %d 次：%s" % (label, n, os.path.basename(path))
        t = t.replace(a, b)
    save(path, t)


T = "\t"

# ---------------- ① 剧本 02 定稿参数 ----------------
import re
raw = open(JSON02, "rb").read()
assert raw.count(b"\r\n") == raw.count(b"\n")
t = raw.decode("utf-8").replace("\r\n", "\n")
t = re.sub(r'"forward_m":\s*[0-9.]+', '"forward_m": 4.8', t)
t = re.sub(r'"distance":\s*[0-9.]+', '"distance": 5.6', t)
save(JSON02, t)

# ---------------- ② C2 新增回归断言 ----------------
A_OLD = (
    T + T + "var origin: Variant = call.get(\"origin\", null)\n"
    + T + T + "_check(\n"
    + T + T + T + "origin is Vector3 and (origin as Vector3).length() > 0.0,\n"
    + T + T + T + "\"队列中心由玩家位置推出（不是原点）\",\n"
    + T + T + ")\n"
)
A_NEW = A_OLD + (
    T + T + "# 队列必须**整体在玩家前方**。触发发生在玩家刚跨进房间那一刻（他还在门口），\n"
    + T + T + "# 若队列压在玩家身后/门线上，实机看到的就是「怪刷在门口」（2026-09-21 主人反馈）。\n"
    + T + T + "# 旧值 forward=distance*0.5=2.3 时，最后一只在 −0.7m —— 正是这个断言要挡住的情况。\n"
    + T + T + "var fwd_axis := -_player.global_basis.z\n"
    + T + T + "fwd_axis.y = 0.0\n"
    + T + T + "if origin is Vector3 and fwd_axis.length_squared() > 0.000001:\n"
    + T + T + T + "fwd_axis = fwd_axis.normalized()\n"
    + T + T + T + "var center_fwd := ((origin as Vector3) - _player.global_position).dot(fwd_axis)\n"
    + T + T + T + "var row := float(int(call.get(\"count\", 1)) - 1) * 0.5\n"
    + T + T + T + "var rearmost := center_fwd - row * float(call.get(\"spread\", 1.5))\n"
    + T + T + T + "_check(\n"
    + T + T + T + T + "rearmost > 1.0,\n"
    + T + T + T + T + "\"队列最后一只也在玩家前方 %.2fm（不贴门口，须 >1.0m）\" % rearmost,\n"
    + T + T + T + ")\n"
)
patch(TEST, [("c2-rearmost-guard", A_OLD, A_NEW)])

# ---------------- ③ 文档项数 91 -> 92 ----------------
patch(DOC, [("doc-count", "三层 **91 项**检查", "三层 **92 项**检查")])

# ---------------- ④ skill 补坑 21 ----------------
PIT21 = (
    "21. **`scene.spawn` 的队列默认贴着玩家 —— 触发发生在你**刚跨进门**那一刻，"
    "`forward = distance*0.5` 只有两三米，最后一只甚至压在你身后（门线上）。"
    "要「怪在房间里侧」就写 `forward_m`（沿视线额外前推，独立于 `distance`）。"
    "⚠️ 两个连带效应：① 前推会把队列推向**画面正中**（相机右移构图被破坏）⇒ 要同时加大 `distance`；"
    "② 前推会拉大相机到队列的距离 ⇒ `verify_narrative_timeline` 的构图带宽（偏角 12~24°、深度 8~13.5m）会拦住你，"
    "别硬放宽带宽去迁就，先确认是你真的要换构图。\n"
)
patch(SKILL, [
    ("pit21", "---\n\n## 8. 交付自检\n", PIT21 + "\n---\n\n## 8. 交付自检\n"),
])

print("DONE")
