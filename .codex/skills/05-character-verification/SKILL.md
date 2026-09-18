---
name: 05-character-verification
description: 角色类表现资产链路第 5 段。为玩家、NPC、怪物、Boss 的表现资产跑专项验收，覆盖加载、节点/骨架契约、根缩放与朝向、包围盒、碰撞不变、挂点、动画时序、换装与真实渲染截图；要求分别记录退出码、预期故障、非预期脚本错误与未执行项。不用于制模（用 01-character-contract-authoring）、导出（用 02-character-export-transfer）、Godot 包装（用 03-character-godot-import）、状态接线（用 04-character-state-binding）、台账推进（用 06-character-ledger）。
---

# S5 · 专项验收

```text
账本 → S1 契约反推 · 双母版 → S2 导出中转 → S3 Godot 包装 → S4 状态映射 → 【S5 专项验收】 → S6 台账推进
```

**入口**：S4 交接的适配层与映射表，账本行 `制作状态 = active`（未经验收则为 `validated`）。
**出口**：一份可复现的验收记录 + 通过结论，账本行写入验收证据。

## 边界

- 本段**只做验收**，不改资产内容。发现问题的修复动作回到对应上游段（S1–S4）。
- 验收不是「跑一遍看绿了」——**分别记录**：退出码、预期故障、非预期脚本错误、未执行项。四类里任何一类没记录，这次验收就不算完成。

## 验收入口

ShellStorm2 的验收入口在 `tests/verification/`，成对存在：

```text
verify_<域>_<方面>_flow.gd   +  .tscn     ← 逻辑验收
verify_<域>_<方面>_visual.gd +  .tscn     ← 视觉验收（真实渲染）
```

现役角色相关入口（举例，实际以目录为准）：

| 方面 | 入口 |
|---|---|
| 尺寸/包围盒 | `verify_player3d_avatar_bounds` |
| 换装/DIY | `verify_player3d_diy_flow` |
| 头部配件 | `verify_player3d_head_accessory_flow` / `_visual` |
| 下身挂点 | `verify_player3d_lower_body_socket_flow` |
| 状态画廊 | `verify_player3d_state_gallery_flow` / `_visual` |
| 动画 | `verify_player3d_animation_flow` / `verify_player3d_idle_animation_flow` |
| 武器姿态与握持 | `verify_player3d_weapon_pose_collision_flow` / `verify_player3d_weapon_grip_visual` |
| 垂直物理 | `verify_player3d_vertical_physics_flow` |
| 敌人行为 | `verify_3d_enemy_behavior_flow` |

**NPC 与普通怪的验收入口当前不存在**，需随该域首批资产一并建立；建立前不得声称该域已验收。

## 验收项（按域裁剪，逐项留证）

**通用（每件必测）**

- [ ] 独立加载：Prefab 可单独实例化，无解析错误
- [ ] 节点/骨架契约与 S1 记录一致
- [ ] 根缩放 = `1,1,1`；方向契约一致（Blender `-Y` / Godot `-Z`）
- [ ] 包围盒与账本「标准尺寸」列一致
- [ ] **碰撞不变**：表现替换未改变碰撞层、尺寸归属或玩法净空
- [ ] 挂点数量、名称、位置与契约一致
- [ ] 材质与贴图无丢失

**分域追加**

| 域 | 追加项 |
|---|---|
| 玩家 | 八态 + 四变体动作时序；换装槽位回退策略；武器握持对齐（枪口 local `-Z` 与 aim 方向偏差）；旧程序驱动为关闭状态、程序 action transform 为零 |
| NPC | `idle`/`talk` 切换；交互与对话显示/隐藏；不引入移动与战斗态 |
| 普通怪 / 精英 | 12 态映射（当前为程序驱动，验收时须**明确记录**「状态→动作映射尚未建立」）；`Enemy3D` 碰撞复用正确 |
| Boss | 三阶段共用主体；`presentation_scene` 不指向裸 GLB |

## 渲染与视觉验收

- **真实渲染用例必须使用真实渲染器**，不接受无渲染的等效替代。
- 视觉验收产出截图留档；「应该没问题」不作为结论。
- 需要角色动画时，**分别验证**导入剪辑与角色状态机的时序，而不是只看 GLB 能否播放。

## 纪律（三条硬线）

1. **不为全绿删设计或放宽旧阈值。** 旧阈值放宽必须有独立依据并单独登记，不能混在本次验收里。
2. **预期故障要入册。** 项目有 `tests/verification/expected_errors/` 用于登记预期错误；非预期脚本错误一律视为失败。
3. **未执行项要明说。** 跳过的用例、用户要求跳过的验收（如账本中已记录的「用户要求跳过验收，未验证」）必须在结论中原样标注，不得被「通过」二字掩盖。

## 收口

```bash
python3 scripts/check_verification_log.py        # 验收日志门禁
```

- 验收记录（退出码 / 预期故障 / 非预期脚本错误 / 未执行项）写入对应域的开发记录与账本备注。
- 通过后把账本行推进到 `active`，并在备注写入：验收入口名、SHA-256、日期、结论。
- 涉及渲染的用例，截图路径一并登记。

## 交接给 S6 的东西

1. 验收记录四件套（退出码、预期故障、非预期脚本错误、未执行项）
2. 通过的验收入口清单与截图路径
3. 账本行待写入字段：`制作状态 = active`、`SHA-256`、`更新时间`、`备注`（验收证据）
