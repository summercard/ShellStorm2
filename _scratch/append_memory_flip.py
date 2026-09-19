"""Append the L-corner facing-fix note to today's workspace memory log (LF, append-only)."""

import io

TARGET = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-19.md"

NOTE = """## L 墙角朝向修正：长臂装饰面原先朝外（主人反馈 → 重派生 + 重导出）

**主人原话**：「L型墙壁的blender组合资产中其中一面墙的正面（带比较多装饰的那面）变成靠外面了，
导致里面的对着里面的本该朝向玩家的变成了背面，反过来重新导出一遍。」

### 现象与根因
- 首版 v001 的**长臂是纯平移**（`T(+2.5,0,0)`，无偏航），保留了 bake 后装饰面朝 Godot `+Z` 的朝向
  —— 那是 L 的**外侧**。玩家站房间里看长臂，看到的是平整的**结构背**。
- **根因不是几何，是「哪一侧算房间内」被写错了**：prefab 注释与探针都把凹侧标成 `−X/−Z`；
  而两臂沿 `+X` 与 `−Z` 伸出时，**两臂之间的凹象限是 `+X`/`−Z`**。
- 当时的朝向断言也是照这个错标号写的（`verify_glb` 断言「长臂装饰面在 Godot +Z」），
  于是**错标号 + 顺着标号写的断言互相自洽**，一路绿灯出货。
- 正确口径只认运行时：`DungeonRoom3D._spawn_room_corner()` 注释（两臂从角点沿房间两条边指向房内）
  + `_build_corner_aware_wall_run()` 的南墙 `rotation_y=PI` / 西墙 `+PI/2`（A 套直墙装饰面永远朝房内）。

### 修正三件事
| 项 | 改法 |
|---|---|
| 几何 | 长臂补 `Rz(+180°)`（与南墙同款）；短臂不变 |
| 断言 | 新增 `ARM_FACING_GODOT`：逐臂断言自身 AABB 的**离面轮廓**（装饰面凸 0.3175 / 结构背 0.15），任一臂反了报 `CORNER_ARM_FACING_WRONG` |
| 标号 | prefab `origin_note` 与探针注释改成「房间内侧 = 两臂之间的凹象限（`+X`/`−Z`）」，探针机位随之取景 |

`verify_glb` 的旧断言「long-arm decoration is not on +Z」本身是错标号，改为断言
「结构背在 `+Z`（≈0.15）/ `−X`（≈−0.15）」。

### 重导出实测
- GLB 751852 B，`sha256=451ba73e82aa38fa4bf91e8421496b09488cd202c453aee2c749619146031c71`（旧 `297ffb52…`）。
- 两臂仍各 5319 面、L 合计 10638（「与直墙逐面一致」未被破坏）。
- 可视包络 `5.15 × 11.9 × 5.15`，最小角 `(−0.15, 0, −5.0)`（`z_max` 由 0.3175 收成 0.15）。
- `.import` 的共享色盘绑定**没被动**（无需重做 gotcha 处理）。
- `PREFAB_CONTRACT_OK … count=6`（0 ERROR）；`CORNER_L_VISUAL_OK … captured=4`。

### 新增自动判据（本轮补完，落在画面探针里）
`tests/verification/probe_corner_l_visual.gd` 增 `FACE_GAUGES` + `_measure_faces()`：
- 把长臂**装饰面**（房内侧 `z=−0.3175`）与**结构背**（外侧 `z=+0.15`）的世界四角用
  `Camera3D.unproject_position()` 投影到屏幕取外接矩形、裁出来量**高通能量**
  （积分图盒式模糊半径 6，平均 `|灰度 − 邻域均值|`，与离线脚本 `panel_check3` 同口径）。
- 判据 `room / outer ≥ FACE_ENERGY_RATIO_MIN = 1.6`；实测 **3.220**（`0.02099 / 0.00652`），
  多轮重跑数值完全一致。
- **反向对照（防假绿）**：把两个取样面互换机位重跑 → **0.149**，立刻 `exit 1` 并报
  「长臂装饰面疑似朝外」。判别力 ≈ **21×**，不是摆设。
- ⚠️ **这是本项目唯一能抓住「面朝反」的自动判据**：包络 / 面数 / 材质角色 / 原点约定四类断言
  对朝向缺陷**全部全绿**——长臂反 180° 后仍是 10638 面、角色不变、`bottom_corner` 仍成立，
  唯一会变的是「房内那面变光滑 / 房外那面有花纹」，而没有任何数值在看这件事。

### 台账二次补丁（第 69 行）
`_scratch/patch_ledger_corner_l_row69_flip.py`（dry-run/`--apply`，备份 `.bak_corner_l_5m_flip`）：
`N69` 可视包络 `5.3375 → 5.15`；`T69` 哈希 `297ffb52… → 451ba73e…`；`Y69` 追加同日朝向修正段。
范围引用一律不动（max row 241、dimension、S69 公式不变）。
> 坑：该脚本首跑 `row 69 is not ENV-TOWER-CORNER-L-5M (got None)` —— `cell_text` 只处理
> `t="inlineStr"`，而 `A69` 是**共享字符串**（`t="s"`）。加 `shared_value()` 解析后通过。

分账门禁 `verify_ledger_split`：`failure_count=474`，构成与上次一致
（`dedupe_key_formula_wrong 235` + `dedupe_result_formula_wrong 235` + `row_content_mutated 2`
（55 墙 / 69 L 角，均有意）+ `asset_not_in_baseline 1` + `moved_sheet_mutated 1`），
`missing=None`、`extra=0` → 红项 ⊆ 基线 ∪ 本次有意变更。

### 文档
`docs/v0.1/development/2026-09-19_关卡通用物体资产契约对照.md` §8.6 全量更新：
摆位表（长臂 `@Rz(+180°)` → Godot `−Z` 房内）、「房间内侧 = 凹象限（`+X`/`−Z`）」说明段、
实测门禁段、画面探针表（机位命名 + 逐面量化表 + 判据已固化进探针）、新增
「同日修订：长臂装饰面原先朝外」整段、台账 T 列哈希 297ffb52 → 451ba73e。
§3.1 清单行包络 `5.3175 → 5.15`；§6 检查清单加「逐臂朝向断言」一条。

### 教训（已进 MEMORY.md）
> **朝向类缺陷四类既有断言全绿**。凡是「面朝哪一侧」这种问题，必须专门写判据（逐臂 AABB
> 离面轮廓 + 画面逐面能量），并且**判据本身要经过反向对照验证**，否则「错标号 + 顺着标号写的
> 断言」会互相自洽、一路绿灯。
"""


def main() -> None:
    with io.open(TARGET, "rb") as handle:
        raw = handle.read()
    assert b"\r\n" not in raw, "memory log must stay LF"
    with io.open(TARGET, "a", encoding="utf-8", newline="\n") as handle:
        handle.write(NOTE)
    with io.open(TARGET, "rb") as handle:
        after = handle.read()
    print("appended bytes:", len(after) - len(raw))
    print("line endings: LF=%d CRLF=%d" % (after.count(b"\n"), after.count(b"\r\n")))


main()
