# 2026-11-18 主页面玩家输入锁定回归修复

- **关联功能**：PLAYER-STATE、UI-HUD、PRESENTATION / 主页面与角色换装
- **工程版本**：以 `project.godot` 为准，未升级版本
- **问题**：主页面 `MainEntryScreen3D.present()` 会调用 `Player3D.set_input_locked(true)`，但 `Dungeon3D._sync_player_input_lock()` 每帧只按普通模态、背包、教学和叙事状态重算，未把塔楼入口覆盖层纳入统一裁决。结果是展示页建立锁定后，下一帧被覆盖回可操作，玩家可以移动、瞄准和开火。
- **回归定位**：`MainEntryScreen3D.present()` 的锁定逻辑自 2026-08-20 已存在；当前锁同步函数的主页面缺口在近期主页面接入后暴露。相关接入历史包括 `c8b28456`（启动加载页与主界面/暂停/命运经济）及 2026-11-18 的塔楼改动；不能仅凭提交时间断言唯一引入提交。

## 设计依据

- `docs/v0.1/16_技术施工_主页面与角色换装.md §1`：真实玩家展示期间锁定输入，开始过渡完成后才恢复输入。
- `docs/v0.1/03_技术施工_玩家与操作.md §3`：移动、主攻击、技能和冲刺在 `locked` 时拒绝。
- `docs/v0.1/design/UI与UX全局设计及全界面清单.md §1.1`：阻断型 UI 必须接入统一输入锁闭环。

## 实际修改

1. `src/world3d/Dungeon3D.gd`
   - 新增可覆盖查询 `is_main_entry_input_locked()`，普通 `Dungeon3D` 默认返回 `false`。
   - `_sync_player_input_lock()` 将该查询并入唯一锁裁决；主页面/开场影片期间不再依赖覆盖层直接写锁。
2. `src/world3d/TowerDescent3D.gd`
   - 覆盖 `is_main_entry_input_locked()`，读取 `_main_entry_screen.is_camera_override_active()`。
   - 入口覆盖层存在且仍持有相机时，统一锁住真实 `Player3D` 的移动、瞄准和战斗输入；过渡结束后自动恢复。
3. `tests/verification/verify_main_entry_cinematic_flow.gd`
   - 增加入口覆盖层接入测试。
   - 增加展示后下一帧 `player.input_locked == true` 与状态机为 `locked` 的回归断言。

## 验证结果

- `python3 scripts/check_level_decoupling.py`：退出码 **0**，7 个通用机制容器违规 **0**。
- `python3 scripts/check_asset_runtime_naming.py`：退出码 **0**，报告为既有欠账 289 文件 / 13 目录，未新增本次相关资产。
- `git diff --check`（本次 3 个文件）：退出码 **0**。
- Godot 项目加载/入口专项：**未完成**。验证套件在全工程资源初始化阶段被环境超时信号中断，未取得 `MAIN_ENTRY_CINEMATIC_OK`；因此不宣称专项运行通过。
- `python3 scripts/check_documentation_contracts.py`：退出码 **1**，为工作区既有文档红项（断链与 `verify_fat_zombie21_gait` 未登记），本次未修改这些无关项。

## 未执行 / 待补

- 需要在资源导入缓存稳定、验证工作区可正常完成初始化后重跑 `scene verify_main_entry_cinematic_flow`，确认真实运行时锁定与开始过渡解锁。
- 需要真实窗口人工操作确认：主页面期间 WASD、鼠标瞄准、鼠标左键、冲刺均无效；点击“开始游戏”过渡完成后恢复。
