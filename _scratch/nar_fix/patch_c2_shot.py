# -*- coding: utf-8 -*-
"""C2 改位置触发 + 构图断言重定；C3 的 once 反向对照改走位置评估；导演加验收入口。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
TEST = os.path.join(ROOT, "tests", "verification", "verify_narrative_timeline.gd")
DIRECTOR = os.path.join(ROOT, "src", "narrative", "NarrativeDirector3D.gd")
T = "\t"


def load(p):
    raw = open(p, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s" % p
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(p, t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(p, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(p), data.count(b"\r"), data.count(b"\n")))


def patch(p, pairs):
    t = load(p)
    for label, a, b in pairs:
        n = t.count(a)
        assert n == 1, "锚点『%s』命中 %d 次：%s" % (label, n, os.path.basename(p))
        t = t.replace(a, b)
    save(p, t)


# ---------------- 导演：验收入口 ----------------
E_OLD = (
    "## 仅供验收：以「事件名 + 房间 id」走一遍真实的事件评估（等价于 Dungeon3D 的\n"
    "## room_entered 信号路径），绕开信号接线本身，单独验证裁决逻辑。\n"
    "func evaluate_event_for_test(event_name: String, room_id: String) -> void:\n"
    + T + "_evaluate_event(event_name, room_id)\n"
)
E_NEW = E_OLD + (
    "\n"
    "\n"
    "## 仅供验收：走一遍真实的位置评估（等价于 _process 里 0.1s 轮询的那一发）。\n"
    "func evaluate_point_for_test() -> void:\n"
    + T + "_evaluate_point()\n"
)
patch(DIRECTOR, [("eval-point-for-test", E_OLD, E_NEW)])

# ---------------- 测试 ----------------
# ① 常量
C_OLD = "const PROBE_ROOM_CENTER := Vector3(-11.0, 0.0, 7.0)\n"
C_NEW = (
    C_OLD
    + "## 第二段的位置触发点 = 房间中心 + point_offset(-14, 0, 0)，与剧本 02 的声明一致。\n"
    + "const TRIGGER_POINT := Vector3(-25.0, 0.0, 7.0)\n"
)
patch(TEST, [("trigger-point-const", C_OLD, C_NEW)])

# ② C2 触发段
C2_OLD = (
    T + "# ---- C2 下一间房：停住 → 镜头右移 → 右边五只小僵尸 → 挪回 → 「它们是什么？」\n"
    + T + "_spawn_calls.clear()\n"
    + T + "_bark.lines.clear()\n"
    + T + "_finish_reasons.clear()\n"
    + T + "_emit_room(NEXT_ROOM_ID)\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(\n"
    + T + T + "NarrativeDirector.active_id() == ZOMBIES_ID,\n"
    + T + T + "\"room_entered(%s) 触发 %s（实际 %s）\"\n"
    + T + T + "% [NEXT_ROOM_ID, ZOMBIES_ID, NarrativeDirector.active_id()],\n"
    + T + ")\n"
)
C2_NEW = (
    T + "# ---- C2 第二段：**位置触发**（房间相对）→ 停住 → 镜头**平移过去**看僵尸 → 挪回 → 「它们是什么？」\n"
    + T + "# 触发已从 room_entered 改成 point：room_entered 在玩家**刚跨进门**那一刻就发，\n"
    + T + "# 那一刻门还没关、玩家还站在门口 —— 实机表现就是「怪刷在门口、镜头也在门口」。\n"
    + T + "# 现在要玩家真的走进房间（房间中心 + point_offset）才触发（2026-09-21 主人要求）。\n"
    + T + "_spawn_calls.clear()\n"
    + T + "_bark.lines.clear()\n"
    + T + "_finish_reasons.clear()\n"
    + T + "# 反向对照：站在触发点外（> radius）时轮询**不得**触发。\n"
    + T + "_player.global_position = TRIGGER_POINT + Vector3(12.0, 0.0, 0.0)\n"
    + T + "NarrativeDirector.evaluate_point_for_test()\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(not NarrativeDirector.is_playing(), \"位置触发：站在触发点外不触发（反向对照）\")\n"
    + T + "# 走进房间、踩到触发点 → 轮询命中\n"
    + T + "_player.global_position = TRIGGER_POINT\n"
    + T + "NarrativeDirector.evaluate_point_for_test()\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(\n"
    + T + T + "NarrativeDirector.active_id() == ZOMBIES_ID,\n"
    + T + T + "\"走进房间触发点后起跑 %s（实际 %s）\" % [ZOMBIES_ID, NarrativeDirector.active_id()],\n"
    + T + ")\n"
)
patch(TEST, [("c2-trigger", C2_OLD, C2_NEW)])

# ③ C3 once 反向对照改走位置
C3_OLD = (
    T + "_emit_room(NEXT_ROOM_ID)\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(not NarrativeDirector.is_playing(), \"once=run 的第二段不会重播\")\n"
)
C3_NEW = (
    T + "_player.global_position = TRIGGER_POINT\n"
    + T + "NarrativeDirector.evaluate_point_for_test()\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(not NarrativeDirector.is_playing(), \"once=run 的第二段不会重播\")\n"
)
patch(TEST, [("c3-once-point", C3_OLD, C3_NEW)])

# ④ C2 构图断言
F_OLD = (
    T + "# 构图断言：镜头右移的驻留窗口（平移 0.1+1.3 结束 → 2.6 开始回摆）内逐帧测量。\n"
    + T + "var framing: Dictionary = await _sample_framing(1.5, 2.55)\n"
    + T + "_check(\n"
    + T + T + "int(framing[\"samples\"]) > 0,\n"
    + T + T + "\"镜头右移驻留窗口内采到帧（%d 帧，峰值 t=%.2f）\"\n"
    + T + T + "% [int(framing[\"samples\"]), float(framing[\"peak_t\"])],\n"
    + T + ")\n"
    + T + "_check(\n"
    + T + T + "float(framing[\"depth\"]) > 8.0 and float(framing[\"depth\"]) < 13.5,\n"
    + T + T + "\"僵尸队列在相机前方 8~13.5m（depth=%.2f）\" % float(framing[\"depth\"]),\n"
    + T + ")\n"
    + T + "# 反向对照：把 camera.pan 的符号写反，队列会从 +16° 甩到 +37°（贴近画面边缘），\n"
    + T + "# 深度也从 10.7m 掉到 6.9m —— 所以角度带与深度带同时收紧才能抓住符号翻转。\n"
    + T + "_check(\n"
    + T + T + "float(framing[\"angle_deg\"]) > 12.0 and float(framing[\"angle_deg\"]) < 24.0,\n"
    + T + T + "\"僵尸队列落在画面**右侧**且与角色分离（水平偏角 %.1f°，目标 12~24°）\"\n"
    + T + T + "% float(framing[\"angle_deg\"]),\n"
    + T + ")\n"
)
F_NEW = (
    T + "# 构图断言：镜头**平移过去**看僵尸的驻留窗口（0.1+1.3 结束 → 2.6 开始回摆）内逐帧测量。\n"
    + T + "var framing: Dictionary = await _sample_framing(1.5, 2.55)\n"
    + T + "_check(\n"
    + T + T + "int(framing[\"samples\"]) > 0,\n"
    + T + T + "\"运镜驻留窗口内采到帧（%d 帧，峰值 t=%.2f）\"\n"
    + T + T + "% [int(framing[\"samples\"]), float(framing[\"peak_t\"])],\n"
    + T + ")\n"
    + T + "_check(\n"
    + T + T + "float(framing[\"depth\"]) > 4.0 and float(framing[\"depth\"]) < 10.0,\n"
    + T + T + "\"僵尸队列在相机前方 4~10m（depth=%.2f）\" % float(framing[\"depth\"]),\n"
    + T + ")\n"
    + T + "# 构图契约变了：以前是「镜头绕主角右甩、僵尸落在画面右侧」（偏角 12~24°）；\n"
    + T + "# 现在是「镜头**平移过去正对僵尸**」⇒ 僵尸应在画面**正中**（|偏角| 小）。\n"
    + T + "# 反向对照：把 pivot 去掉（回到绕玩家），偏角会跳回 16°+ 且深度掉出这条带。\n"
    + T + "_check(\n"
    + T + T + "absf(float(framing[\"angle_deg\"])) < 6.0,\n"
    + T + T + "\"镜头正对僵尸 ⇒ 僵尸在画面正中（水平偏角 %.1f°，目标 |偏角| < 6°）\"\n"
    + T + T + "% float(framing[\"angle_deg\"]),\n"
    + T + ")\n"
    + T + "# 机位真的绕**队列**而不是绕玩家：相机到队列距离 == 接管前的相机距离。\n"
    + T + "if not _spawn_calls.is_empty():\n"
    + T + T + "var queue_origin: Vector3 = _spawn_calls[0].get(\"origin\", Vector3.ZERO)\n"
    + T + T + "var queue_rest_len := _CAMERA_REST_OFFSET.length()\n"
    + T + T + "_check(\n"
    + T + T + T + "absf(_camera.global_position.distance_to(queue_origin) - queue_rest_len) < 0.05,\n"
    + T + T + T + "\"机位绕的是**僵尸队列**（距队列 %.2fm，接管前相机距离 %.2fm）\"\n"
    + T + T + T + "% [_camera.global_position.distance_to(queue_origin), queue_rest_len],\n"
    + T + T + ")\n"
)
patch(TEST, [("c2-framing", F_OLD, F_NEW)])

print("STAGE2_DONE")
