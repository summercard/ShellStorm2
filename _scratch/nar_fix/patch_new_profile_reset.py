# -*- coding: utf-8 -*-
"""补「新档=新本局」复位：复位存档后本局内存态归零，冷启动开场剧本可重触发。

改动：
  1. NarrativeDirector3D.gd  → _ready 接 BaseManager.game_save_reset_completed；
                              新增 reset_run_state() + _on_game_save_reset_completed()
  2. verify_narrative_timeline.gd → C5 用例（重触发 + 反向对照）
  3. docs/v0.1/08_技术施工_剧情触发.md → 项数 85→90 + §9 新档边界一句话

行尾：保持各文件原有风格（不改动无关行）。
"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
DIRECTOR = os.path.join(ROOT, "src", "narrative", "NarrativeDirector3D.gd")
TEST = os.path.join(ROOT, "tests", "verification", "verify_narrative_timeline.gd")
DOC = os.path.join(ROOT, "docs", "v0.1", "08_技术施工_剧情触发.md")


def read_text(path):
    raw = open(path, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    lone_cr = raw.count(b"\r") - crlf
    if crlf and lf != crlf:
        raise SystemExit("行尾不纯: %s CRLF=%d LF=%d" % (path, crlf, lf))
    if lone_cr:
        raise SystemExit("存在孤立 CR: %s (%d)" % (path, lone_cr))
    style = "\r\n" if crlf else "\n"
    text = raw.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    return text, style


def write_text(path, text, style):
    data = text.replace("\n", style).encode("utf-8")
    open(path, "wb").write(data)
    print("  wrote %s style=%s CR=%d LF=%d"
          % (os.path.basename(path), repr(style), data.count(b"\r"), data.count(b"\n")))


def patch(path, pairs):
    text, style = read_text(path)
    for label, anchor, insert in pairs:
        n = text.count(anchor)
        if n != 1:
            raise SystemExit("锚点『%s』命中 %d 次（需恰好 1 次）：%s" % (label, n, path))
        text = text.replace(anchor, insert)
    write_text(path, text, style)


T = "\t"

# ---------------- 1) NarrativeDirector3D.gd ----------------
DIRECTOR_READY_ANCHOR = (
    T + "get_tree().node_added.connect(_on_node_added)\n"
    + T + "_arm_catalog_triggers()\n"
)
DIRECTOR_READY_NEW = DIRECTOR_READY_ANCHOR + (
    "\n"
    + T + "# 复位存档 = 新档：本局内存态（once / 标记）必须归零。BaseManager 是 autoload 且\n"
    + T + "# 注册在本节点之前，其 game_save_reset_completed 只在复位**成功**时发（08 文档 §9）。\n"
    + T + "# 不接这条线：复位档走 change_scene_to_file，autoload 存活 ⇒ 冷启动开场剧本的\n"
    + T + "# fired_count 不随场景重载归零，once=run 会把它永久挡住（2026-09-21 真机实测）。\n"
    + T + "var save_service := get_node_or_null(\"/root/BaseManager\")\n"
    + T + "if save_service != null and save_service.has_signal(\"game_save_reset_completed\"):\n"
    + T + T + "save_service.game_save_reset_completed.connect(_on_game_save_reset_completed)\n"
    + T + "else:\n"
    + T + T + "_warn(\"未接上 BaseManager.game_save_reset_completed：复位存档后本局剧情标记不会归零。\")\n"
)

DIRECTOR_RESET_ANCHOR = (
    "## 仅供验收与调试：清干净一切（不动场景，场景由归还机制负责）。\n"
    "func reset_for_test() -> void:"
)
DIRECTOR_RESET_NEW = (
    "## 新档 / 新本局：把「本局内存态」整体归零，让 `once = run` 的剧本可以重新触发。\n"
    "##\n"
    "## 由 BaseManager.game_save_reset_completed 驱动（复位存档成功的唯一出口）。\n"
    "## 为什么必须有：`once` / `flow.mark` / `grant.flag` 全是本局内存态（08 文档 §9），\n"
    "## 而复位档走 `change_scene_to_file` —— autoload 存活，`_armed` 里的 `fired_count`\n"
    "## 不随场景重载归零 ⇒「复位存档 → 重新开始」后冷启动开场剧本不再播（真机实测）。\n"
    "## 只重挂登记表，不重解析剧本（`_scripts` 缓存保留）。\n"
    "func reset_run_state() -> void:\n"
    + T + "abort(\"new_profile\")\n"
    + T + "_flags.clear()\n"
    + T + "# 先清空再重挂：arm() 会从既有登记里**继承** fired_count，不清空等于没复位。\n"
    + T + "_armed.clear()\n"
    + T + "_diagnostics.clear()\n"
    + T + "_arm_catalog_triggers()\n"
    + T + "_dispatch_log.clear()\n"
    + T + "_paused_dialogue_synced = false\n"
    "\n"
    "\n"
    "func _on_game_save_reset_completed(result: Dictionary) -> void:\n"
    + T + "# 契约上信号只在复位成功时发；这里再确认一次，避免将来 BaseManager 改口径后静默误复位。\n"
    + T + "if not bool(result.get(\"success\", false)):\n"
    + T + T + "return\n"
    + T + "reset_run_state()\n"
    "\n"
    "\n"
    + DIRECTOR_RESET_ANCHOR
)

patch(DIRECTOR, [
    ("ready-connect", DIRECTOR_READY_ANCHOR, DIRECTOR_READY_NEW),
    ("reset-run-state", DIRECTOR_RESET_ANCHOR, DIRECTOR_RESET_NEW),
])

# ---------------- 2) verify_narrative_timeline.gd ----------------
TEST_ANCHOR = (
    T + "_note(\n"
    + T + T + "\"C 统计：刷怪调用=%d，台词累计=%d，姿态指令=%d\"\n"
    + T + T + "% [_spawn_calls.size(), _bark.lines.size(), _avatar.pose_calls]\n"
    + T + ")\n"
)
TEST_NEW = TEST_ANCHOR + (
    "\n"
    + T + "# ---- C5 复位存档 = 新本局：本局内存态归零，冷启动开场剧本必须能重新触发（2026-09-21 真机）\n"
    + T + "# 根因：复位档走 change_scene_to_file、autoload 存活 ⇒ _armed 的 fired_count 不归零 ⇒\n"
    + T + "# once=run 把开场永久挡住。reset_run_state() 由 BaseManager.game_save_reset_completed 驱动。\n"
    + T + "_finish_reasons.clear()\n"
    + T + "NarrativeDirector.reset_run_state()\n"
    + T + "_check(not NarrativeDirector.is_playing(), \"reset_run_state 之后没有在演剧本\")\n"
    + T + "_emit_gameplay_started(OPENING_ROOM_ID)\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(\n"
    + T + T + "NarrativeDirector.active_id() == WAKE_ID,\n"
    + T + T + "\"复位存档后开场剧本重新触发（实际 active=%s）\" % NarrativeDirector.active_id(),\n"
    + T + ")\n"
    + T + "await _wait_until_finished()\n"
    + T + "_check(\n"
    + T + T + "_finish_reasons.size() == 1 and _finish_reasons[0] == \"flow.end\",\n"
    + T + T + "\"重触发那次仍按 flow.end 正常收口（%s）\" % str(_finish_reasons),\n"
    + T + ")\n"
    + T + "_check(not _player.input_locked, \"重触发收口后输入归还\")\n"
    + T + "# 反向对照：不调 reset_run_state、直接再发一次必须**不**播 —— 证明上面的绿不是漏检。\n"
    + T + "_finish_reasons.clear()\n"
    + T + "_emit_gameplay_started(OPENING_ROOM_ID)\n"
    + T + "await _wait_frames(2)\n"
    + T + "_check(not NarrativeDirector.is_playing(), \"反向对照：once 未复位时再发一次仍被挡住\")\n"
)
patch(TEST, [("C5-new-profile", TEST_ANCHOR, TEST_NEW)])

# ---------------- 3) 文档 ----------------
DOC_COUNT_ANCHOR = "三层 **85 项**检查"
DOC_COUNT_NEW = "三层 **90 项**检查"
DOC_NOTE_ANCHOR = (
    "- **标记不进存档**：`flow.mark` / `grant.flag` 与 `once` 都只在本局内存态。"
    "跨局历史（`BaseData.narrative_history`）需走存档系统的事务，不在本版。"
)
DOC_NOTE_NEW = DOC_NOTE_ANCHOR + (
    "\n- **新档边界（2026-09-21 补）**：本局内存态的**归零点** = `BaseManager.game_save_reset_completed`"
    "（复位存档成功的唯一出口，`NarrativeDirector.reset_run_state()` 接）。不进存档 ≠ 不归零 —— "
    "复位档走 `change_scene_to_file`、autoload 存活，若不归零，`once = run` 的冷启动开场剧本"
    "只会播一次，「复位存档 → 重新开始」就再也看不到开场。"
)
patch(DOC, [
    ("doc-count", DOC_COUNT_ANCHOR, DOC_COUNT_NEW),
    ("doc-new-profile-note", DOC_NOTE_ANCHOR, DOC_NOTE_NEW),
])

print("PATCH_ALL_DONE")
