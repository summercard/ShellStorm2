# -*- coding: utf-8 -*-
"""1848 事务：复位存档后开场剧本不播（本局内存态未归零）。全部保持 CRLF。"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(MEM, "2026-09-21")
TX_PATH = os.path.join(DAY, "1848_复位存档后开场剧本不播_本局态归零.md")
INDEX_PATH = os.path.join(DAY, "_INDEX.md")
PB_PATH = os.path.join(MEM, "MEMORY-playbooks.md")
SKILL_PATH = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"


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


def insert_once(path, anchor, replacement):
    t = load(path)
    n = t.count(anchor)
    assert n == 1, "锚点命中 %d 次：%s" % (n, os.path.basename(path))
    save(path, t.replace(anchor, replacement))


def append(path, block):
    t = load(path)
    save(path, t.rstrip("\n") + "\n\n" + block + "\n")


# ---------------- 1) 事务文件 ----------------
TX = """# 复位存档后开场剧本不播 · 本局内存态未归零

> 类型：故障修复（诊断 → 新增归零点 → 双验收 + 两条反向对照）
> 关联：**1539**（两条开场剧本本体）、**1641**（开场挂 `gameplay_started`）、**08 文档 §8.6 / §9**

## 现象
主人问：「这个系统不是跟着存档走的吗？为什么我后面重新复位存档、重新开始，开场的剧情就没了呢」
即：先跑过一遍（开场播了）→ 暂停菜单**复位存档** → 重新开始 → **开场剧情不再播**，且零报错。

## 根因：`once` 是本局**内存**态，复位存档没有归零点
- 开场剧本 `nar_tower_opening_01_wake` 挂 `gameplay_started` + **`once: "run"`**；
  `_try_fire()` 用 `_armed[narrative_id]["fired_count"]` 记账，`once==run && fired_count>0` 直接 return。
- 这份状态**只在 autoload 内存里**（`NarrativeDirector._armed`，08 文档 §9：标记不进存档）。
- 复位存档的真实路径（`PauseMenu3D._confirm_game_save_reset`）：
  `BaseManager.reset_game_save()` → `_reset_runtime_singletons_for_new_profile()`
  → `GameEntryFlow.request_main_entry(REASON_NEW_GAME_RESET)` → **`change_scene_to_file(main_scene)`**。
- ⛔ `change_scene_to_file` **不重启进程** ⇒ autoload 存活 ⇒ `_armed` 原封不动 ⇒ `fired_count` 仍是 1
  ⇒ `once=run` 把冷启动开场**永久挡住**。而 `_reset_runtime_singletons_for_new_profile()` 当时只复位了
  GameTimeManager / LevelSelect / FateCardGameBridge / GameplaySpatialRegistry3D / Global，**没复位剧情系统**。
- 注意 §8.6 的**反面**本来就存在（中途中存档→退出→续局，`once` **会重复触发**），v0.2 明确接受不修；
  本次补的是另一头：**新档必须归零**。

## 修法
1. `NarrativeDirector3D` 新增 `reset_run_state()`（公开）：`abort` 在演剧本 → 清 `_flags` →
   **先清空 `_armed` 再 `_arm_catalog_triggers()`**（`arm()` 会从既有登记**继承** `fired_count`，
   不清空等于没复位）→ 清诊断/派发日志。只重挂登记表，不重解析剧本（`_scripts` 缓存保留）。
2. 归零**由存档事件驱动**，不在 UI 侧硬调：`_ready` 订阅 **`BaseManager.game_save_reset_completed`**
   （该信号只在复位**成功**时发；BaseManager 在 autoload 顺序里早于 NarrativeDirector，可直接订阅）。
3. ⚠️ 静态守卫拦截了一次：`src/narrative/**` **禁节点路径字面量**（验收 `_no_path_literals` 禁
   `get_node("` / `get_node_or_null("` / `NodePath("` / `"../`）—— 初版写的
   `get_node_or_null("/root/BaseManager")` 直接让 `verify_narrative_timeline` 变红。
   改用 **autoload 全局标识 `BaseManager`**（本文件既有的 `DialogueUI` 同款写法）后通过。

## 验收
- `verify_narrative_timeline`：**85 → 91 项**。新增 C5（复位后**必须能重新触发** + 反向对照"不复位则仍被挡住"）
  与一条 `is_connected` 接线断言（"断了只会表现为复位档后不播开场，运行时零报错"）。
- **反向对照 ×2**：① 让 `reset_run_state()` 不复位（不 clear `_armed`）→ 恰好 2 条红
  （`复位存档后开场剧本重新触发（实际 active=）` —— **用户症状原样复现**）；② 断开
  `BaseManager` 订阅 → 接线断言**恰好 1 条红**。两次均还原、逐字节干净。
- `verify_opening_script_runtime`：25 项全绿（未被破坏）。
- 文档 08 同步：验收项数 85→91；§9 补「新档边界 = `game_save_reset_completed`」。

## 结论一句话
「复位存档重开后开场没了」**不是**剧本或存档的问题，而是 `once` 的本局内存态没有归零点：
复位档走 `change_scene_to_file`、autoload 存活，`fired_count` 不归零。现由
`BaseManager.game_save_reset_completed → NarrativeDirector.reset_run_state()` 归零，双验收 + 两条反向对照全绿。
"""

save(TX_PATH, TX)

# ---------------- 2) 索引行 ----------------
NEW_ROW = (
    "| 18:48 | [复位存档后开场剧本不播 · 本局内存态未归零](1848_复位存档后开场剧本不播_本局态归零.md) "
    "| **故障修复（诊断 + 新增归零点 + 双验收）** "
    "| 主人报「复位存档、重新开始后开场剧情没了」。根因：开场剧本靠 `once: run` + `_armed.fired_count` 记账，"
    "而这份状态**只在 autoload 内存**（08 §9 不进存档）；复位档走 `BaseManager.reset_game_save()` → "
    "**`change_scene_to_file`**（不重启进程 ⇒ autoload 存活）⇒ `fired_count` 不归零 ⇒ 开场被永久挡住，零报错。"
    "修法：新增 `NarrativeDirector.reset_run_state()`，由 **`BaseManager.game_save_reset_completed`** 驱动。"
    "⚠️ 静态守卫拦截初版：`src/narrative/**` 禁路径字面量 ⇒ 取 autoload 只能用全局标识（不能用 `/root/…`）。"
    "验收 85→**91 项**；**反向对照 ×2**（不复位→用户症状原样复现 / 断订阅→接线断言恰好 1 红）全咬人；"
    "`verify_opening_script_runtime` 25 项仍绿 |"
)
insert_once(INDEX_PATH, "| 17:37 |", "| 17:37 |")  # no-op guard，真正的插入见下

t = load(INDEX_PATH)
lines = t.split("\n")
assert sum(1 for l in lines if l.startswith("| 18:48 |")) == 0, "18:48 行已存在"
out = []
hit = 0
for l in lines:
    out.append(l)
    if l.startswith("| 17:37 |"):
        out.append(NEW_ROW)
        hit += 1
assert hit == 1, "17:37 锚点命中 %d" % hit
save(INDEX_PATH, "\n".join(out))

# ---------------- 3) playbooks 追加小节 ----------------
PB = """### 剧情 · 本局内存态的归零点 = 复位存档（不是"重开场景"）
- `once` / `flow.mark` / `grant.flag` 全是**本局内存态**（08 文档 §9），靠 `_armed[].fired_count` 记账。
- ⛔ 复位存档 = `BaseManager.reset_game_save()` → **`change_scene_to_file(main_scene)`**，**不重启进程**、
  autoload 存活 ⇒ 不归零的话 `once: run` 的冷启动开场剧本**再也触发不了**。症状：**复位存档、重新开始后
  开场剧情整个消失，且零报错**（2026-09-21 真机）。
- 归零点已实装：**`NarrativeDirector.reset_run_state()`**，由 **`BaseManager.game_save_reset_completed`**
  驱动（该信号只在复位**成功**时发；BaseManager 在 autoload 顺序里早于 NarrativeDirector，可直接订阅）。
  实现要点：`arm()` 会从既有登记**继承** `fired_count` ⇒ 必须**先 `_armed.clear()` 再重挂**，否则等于没复位。
- ⚠️ 取别的 autoload 只能用**全局标识**（`BaseManager` / 本文件既有的 `DialogueUI` 同款）：`src/narrative/**`
  **禁节点路径字面量**，验收 `_no_path_literals` 禁 `get_node("` / `get_node_or_null("` / `NodePath("` / `"../`。
- 反面（已知、**不修**）：**中途中存档 → 退出 → 续局，`once` 会重复触发**（08 文档 §8.6，v0.2 明确接受）。
- 守卫：`verify_narrative_timeline` 新增 C5（复位后必须能重触发 + "不复位则仍被挡住"反向对照）+ 一条
  `is_connected` 接线断言；两条都做过源码级反向对照（不复位 / 断订阅）。"""
append(PB_PATH, PB)

# ---------------- 4) skill 10 补坑 20 ----------------
PIT20 = (
    "20. **`once` 只活在「本局内存态」，它的归零点是「复位存档」，不是「重开场景」。** 冷启动开场剧本挂\n"
    "    `gameplay_started` + `once: run`，靠 `_armed[].fired_count` 记账（08 文档 §9：不进存档）。复位存档走\n"
    "    `change_scene_to_file`、autoload 存活 ⇒ 少了 `NarrativeDirector.reset_run_state()` 就**永远不再触发**。\n"
    "    症状是「复位存档、重新开始后开场剧情整个消失」，**零报错**。该复位由 `BaseManager.game_save_reset_completed`\n"
    "    驱动（已实装）。反面：**中途中存档 → 退出 → 续局，`once` 会重复触发**（08 §8.6，v0.2 明确接受）。\n"
    "    另：改叙事脚本时**不能**用 `get_node(\"/root/…\")` 取别的 autoload —— `src/narrative/**` 禁路径字面量，\n"
    "    只能用全局标识（`BaseManager` / `DialogueUI` 同款），否则 `verify_narrative_timeline` 直接变红。\n"
)
insert_once(
    SKILL_PATH,
    "---\n\n## 8. 交付自检\n",
    PIT20 + "\n---\n\n## 8. 交付自检\n",
)

print("ALL_DONE")
