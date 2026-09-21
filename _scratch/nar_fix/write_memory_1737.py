# -*- coding: utf-8 -*-
"""写入 1737 事务：气泡残影复发与类名抢注。全部按 CRLF 二进制写回。

幂等：可重复运行；对已含行尾损伤的文件先归一化再重写。
"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(MEM, "2026-09-21")

TX_PATH = os.path.join(DAY, "1737_气泡残影复发与类名抢注.md")
INDEX_PATH = os.path.join(DAY, "_INDEX.md")
PB_PATH = os.path.join(MEM, "MEMORY-playbooks.md")


def to_lf(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def write_crlf(path, text):
    """任何输入 -> 归一 LF -> 统一 CRLF 落盘。先校验后写。"""
    text = to_lf(text)
    data = text.replace("\n", "\r\n").encode("utf-8")
    cr = data.count(b"\r")
    lf = data.count(b"\n")
    assert cr == lf, "CRLF 不纯: %s CR=%d LF=%d" % (os.path.basename(path), cr, lf)
    with open(path, "wb") as f:
        f.write(data)
    print("wrote %s CR=%d LF=%d" % (os.path.basename(path), cr, lf))


# ---------------- 1) 事务文件 ----------------
TX = to_lf("""# 气泡残影复发 · 类名抢注（`SpeechBubble3D`）

> 类型：故障修复（只读诊断 → 移出副本 → 加守门脚本）
> 关联：**1345**（同一 footgun 首次，脚本副本落 res://）、**1400**（气泡走路重影本体修复）、**1440**（并发 VFX 会话）

## 现象
主人报「刚才改的对话框有残影这个问题又出现了」。
先查 `src/ui/bubble/SpeechBubble3D.gd` 源码 —— 它是**正确的**防残影版本：
- `_make_material()` 走 `TRANSPARENCY_DISABLED`（L299）
- `Label3D.alpha_cut = ALPHA_CUT_DISCARD`（L172）
- 底板材质与 Label3D 的 billboard 均 `BILLBOARD_DISABLED`（改由节点级朝向驱动）

但复跑 `verify_speech_bubble_3d` **红**：`底板 surface 0/1 不是不透明管线`、`Label3D 未启用 alpha 裁剪`（60 项里 3 项失败）。

## 根因：类名抢注（`class_name` squatting）
`.godot/global_script_class_cache.cfg` 里 `SpeechBubble3D` 的 `path` 指向
**`res://_scratch/rv4/old_ok.gd`** —— 不是 `src/ui/bubble/` 的真源。

res:// 内残留两份**修复前**副本（`TRANSPARENCY_ALPHA`、**无** `alpha_cut` = 会拖 TAA 残影的旧版），
且都声明了 `class_name SpeechBubble3D`：
- `_scratch/rv3/SpeechBubble3D.gd`（13:53）
- `_scratch/rv4/old_ok.gd`（13:57）

它们是 14:00（事务 1400）**反向对照**（验证「去掉 `alpha_cut` → 验收变红」）留下的快照，
**忘了移出 res://**。Godot 对重复类名**不报错**，只在缓存里留一个 `path`
（谁被扫到最后谁赢，且**跨目录**），于是所有 `SpeechBubble3D.new()` / `var v: SpeechBubble3D`
都解析到旧副本 —— 真源的修复被静默遮住。

命中两处调用方：
- `src/ui/bubble/CharacterBark3D.gd:107`（`_bubble = SpeechBubble3D.new()`，**游戏运行时**）
- `tests/verification/verify_speech_bubble_3d.gd:42`（验收）

全项目 `class_name` 扫描（`_scratch/nar_fix/sweep_classnames.py`）：**160 个类，仅此 1 组重复**。

## 修法
1. 把两份副本**移出 res://**（不删，保留可回溯）→
   `../.workbuddy/quarantine/20260921_classname_squat/{rv3,rv4}/`。
2. `--headless --path . --import` 重刷全局类缓存。
3. 复核缓存 `path` = `res://src/ui/bubble/SpeechBubble3D.gd`；
   `verify_speech_bubble_3d` = **60/60 绿、exit 0**。

剩余 3 条 `ERROR:` 全是并发会话的 VFX 解析错误
（`VfxMuzzleFlash3D` / `VfxImpact3D` / `VfxBulletVisual3D`），与本批无关（本批 non-VFX ERROR=0）。

## 沉淀
- 新增守门脚本 **`scripts/check_classname_unique.py`**：扫全 res:// 的重复 `class_name`；
  `--strict` 连「快照目录里声明了类名」也判失败；**已反向对照**（插回副本 → exit 1 + 列文件 + 打印缓存实际指向；清掉 → exit 0）。
  ⚠️ **尚未接入 `run_verification_suite.sh`**，需要时显式加调用。
- playbooks「环境 · 脚本快照纪律」补判据：类名抢注的**判据 = 读缓存 `path` 字段**，修法 = 移出 res:// + `--import`。
- 呼应 1345 的老教训（脚本副本禁落 res://）：本次是**同一 footgun 的复发**，
  残影「修好又复发」**不是代码回归**，别再当成新问题查源码。

## 结论一句话
气泡残影复发**不是** `SpeechBubble3D` 代码回归，而是 `_scratch` 两份修复前副本抢注同名 `class_name`
遮住了真源；移出 res:// + 重刷缓存后验收 **60/60 复绿**，并补了可复用的类名唯一性守门脚本。
""")
write_crlf(TX_PATH, TX)

# ---------------- 2) 索引追加一行（幂等） ----------------
with open(INDEX_PATH, "rb") as f:
    idx = to_lf(f.read().decode("utf-8"))
lines = [ln for ln in idx.split("\n") if not ln.startswith("| 17:37 |")]
NEW_ROW = (
    "| 17:37 | [气泡残影复发 · 类名抢注（`SpeechBubble3D`）](1737_气泡残影复发与类名抢注.md) "
    "| **故障修复（诊断 + 移出副本 + 守门脚本）** "
    "| 主人报「对话框残影又出现了」，源码却是对的（真源已是 `TRANSPARENCY_DISABLED`+`alpha_cut`），但验收红 3 项。"
    "根因 = **类名抢注复发**：`.godot/global_script_class_cache.cfg` 里 `SpeechBubble3D` 的 `path` 指向**修复前副本** "
    "`_scratch/rv4/old_ok.gd`（14:00 反向对照遗留、忘移出 res://），命中 `CharacterBark3D.gd:107`（运行时）+ 验收 L42。"
    "全项目扫描 160 类**仅此 1 组**重复。修法：两份副本移出 res://（到 `../.workbuddy/quarantine/…`）+ `--import` 重刷 "
    "⇒ 验收 **60/60 绿、exit 0**。新增守门 `scripts/check_classname_unique.py`（含反向对照；未接入套件）。呼应 1345 老教训 |"
)
hit = 0
out = []
for ln in lines:
    out.append(ln)
    if ln.startswith("| 16:41 |"):
        out.append(NEW_ROW)
        hit += 1
assert hit == 1, "索引未找到 16:41 锚点 (hit=%d)" % hit
write_crlf(INDEX_PATH, "\n".join(out))

# ---------------- 3) playbooks 补一条判据（幂等） ----------------
with open(PB_PATH, "rb") as f:
    pb = to_lf(f.read().decode("utf-8"))
anchor = "纯 `.before` 后缀不会被导入。"
assert pb.count(anchor) == 1, "playbooks 锚点不唯一 (count=%d)" % pb.count(anchor)
mark = "**类名抢注的判据与修法（2026-09-21 复现"
if mark in pb:
    print("playbooks 已含该类名抢注条目，跳过插入")
else:
    BULLET = (
        "- ⛔ **类名抢注的判据与修法（2026-09-21 复现，见 1737 事务）**：重复 `class_name` **不报错**，"
        "Godot 只在 `.godot/global_script_class_cache.cfg` 里留**一个** `path`（谁被扫到最后谁赢，**且跨目录** —— "
        "`_scratch/` 副本会顶掉 `src/` 真源）⇒ 所有 `X.new()` / `var v: X` 静默解析到副本。"
        "**判据 = 读缓存里该类的 `path` 字段**。实例：`SpeechBubble3D.gd` 真源已是「不透明管线 + `alpha_cut`」（防 TAA 残影），"
        "但 `_scratch/rv3`、`_scratch/rv4` 两份**修复前**副本抢注同名类 ⇒ 气泡残影「修好又复发」而源码无问题。"
        "**修法 = 把副本移出 res://（不删）+ `--headless --path . --import` 重刷 + 复核缓存 `path`**。"
        "守门脚本 `scripts/check_classname_unique.py`（扫全 res:// 重复类名；`--strict` 连快照目录声明类名也判失败；已反向对照；**未接入套件**）。"
    )
    pb = pb.replace(anchor, anchor + "\n" + BULLET)
    write_crlf(PB_PATH, pb)

print("ALL_MEMORY_WRITES_DONE")
