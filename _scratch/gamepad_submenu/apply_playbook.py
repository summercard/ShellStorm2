# -*- coding: utf-8 -*-
# 事务 1442：把两条可复用教训沉淀进 MEMORY-playbooks.md
import pathlib

P = pathlib.Path("I:/工作项目/shellstrom2/.workbuddy/memory/MEMORY-playbooks.md")
t = P.read_bytes().decode("utf-8").replace("\r\n", "\n")

def sub1(text, anchor, repl, label):
    n = text.count(anchor)
    if n != 1:
        raise SystemExit("ANCHOR-FAIL %s count=%d" % (label, n))
    return text.replace(anchor, repl)

# 1) 本地实操补充：光照朝向必须钉住
a1 = "- ⚠️ **同一文件多处编辑必须串行**（同一条消息的多个 `Edit` 会互相覆盖，最后一个静默胜出 —— 本轮 `plans=0` 假绿即由此产生）。"
r1 = a1 + "\n- ⚠️ **依赖「已照亮」样本的 headless 用例，光照朝向必须先钉住**：`DirectionalLight3D` 的默认朝向是 **−Z**。把太阳「水平」摆在敌人与玩家之间时，从敌人朝太阳打的射线会被**原点处的玩家挡住** ⇒ `sun_exposure_ratio` 恒 `0.0`、敌人永远停在 `STATE_DARKNESS`，用例报「敌人仍是黑暗态」（看着像功能坏了，实为取景错）。**必须 `sun.rotation_degrees = Vector3(-90, 0, 0)` 顶照**（2026-09-22 瞄准辅助候选收集用例实测）。"
t = sub1(t, a1, r1, "playbook-light")

# 2) A/B 中和排除法：整文件换 HEAD 版
a2 = "- 实例：2026-09-20 23:4x `verify_arrival_gate_floor_bundle_flow` 报两条 ERROR（期望「首段 69 房」「旧段卸载 65 房」）；该场景**当天 11:32 仍绿**、红出现在 21:2x 另一会话改 `Dungeon3D.gd` / `DungeonRoom3D.gd` / `Block00MasterOfficeLayout3D.gd` 之后；中和本批改动后两条 ERROR 不变 ⇒ 非本批，登记为既有红项。"
r2 = a2 + "\n- **更强的中和法（整文件换 `HEAD` 版）**：当本批改动横跨多文件、逐行中和不现实时 —— 先把**自己改过的每个文件** `cp` 进 `_scratch/<事务>/baseline_bak/`，再用 `git show HEAD:<path> > <path>` 整体换成提交版，重跑同一门禁看红项是否**逐字相同**；相同 ⇒ 非本批。⚠️ 两个硬前提：① **换前必须已备份自己那一版**，换后**必须逐文件 `cp` 还原、并重跑一次确认复绿**（否则会把自己的活永远留在 HEAD 版上）；② 只换自己动过的文件，别顺手换公共依赖。实例：2026-09-22 瞄准辅助事务，`verify_3d_enemy_behavior_flow` 报 7 条 floating-number 红，5 文件换 HEAD 版后**逐字同红** ⇒ 既存红。"
t = sub1(t, a2, r2, "playbook-ab")

P.write_bytes(t.replace("\n", "\r\n").encode("utf-8"))
b = P.read_bytes()
lf = b.count(b"\n"); crlf = b.count(b"\r\n"); crcrlf = b.count(b"\r\r\n")
print("playbook patched; lines=%d crlf=%d lone_lf=%d crcrlf=%d" % (lf, crlf, lf - crlf, crcrlf))
