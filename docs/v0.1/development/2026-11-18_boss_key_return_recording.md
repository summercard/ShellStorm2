# 击败Boss后钥匙返航段落连续录制与安全信标落点修复

- 日期：2026-11-18；记录ID：`boss_key_return_recording_20261118`；工程版本：0.1.0。
- 功能ID：`NARRATIVE-TRIGGER / DIALOGUE-UI / SAVE-PROFILE / BOSS-STAGES`。
- 任务范围：按业主“击败Boss后回到基地这段剧情”的指正，录制**稀土钥匙返航段落**的连续视频（击败首领 → 首领箱 → 领取稀土钥匙 → 方式B返航通讯 → 安全撤离信标落地 → 主动8秒同步），并在录制过程中修掉一个真实功能缺陷：安全信标在首领房拿不到合法地面落点时只会永久重试。
- 工作区基线：开始前已有大量未提交变更（叙事A/B、安全信标、Boss房减怪、震屏对齐等），本记录只覆盖本轮改动范围，未回滚他人变更。

## 1. 上一轮理解偏差

业主上一句“击败boss后，回到基地后的这段剧情”被误解为 3.3（回99F插钥匙）。实际指的是本轮新增的**钥匙返航段落**：`nar_main_032_key_return_call` + `STORY_SAFE` 安全信标。3.3 的录制本轮不做。

## 2. 录制入口扩展

`tests/verification/capture_main_story_chapter.gd` 原来只支持 `031/032/033`。新增 `032K` 章节码：

- 章节ID映射到 `MainStoryChapter3D.KEY_RETURN_CALL_ID`，场景仍用 `ExpeditionLevel01_3D.tscn`（首领房）。
- 032K 预置 `nar_main_032_monitor_audience` 已完成，否则进房会先重播显示器九镜台词。
- 032K 复用 `_setup_boss` 的真实进房事务，但**不做** 032 专属的“Boss 未激活门闩”断言——3.2 已完成时 Boss 不再被 hold。
- 新增 `_capture_key_return`：只跑正式链，不手工造箱、不手工写 history。

## 3. 录制内容与检查

流程与断言（全部走正式接口）：

| 步骤 | 断言 |
|---|---|
| Boss 存活 | 真实 Boss 实体在树、房间归属为 `boss` |
| 击杀 | `take_damage` 后 `is_room_boss_defeated("boss")` 为真 |
| 首领箱 | 由 `_mark_room_boss_defeated` → `_ensure_boss_chest_drop` 正式生成 `drop_boss` 箱 |
| 领取 | 真实交互入口 `perform_interaction`；钥匙状态变 `acquired` |
| 返航通讯 | 控制器自动起播 `nar_main_032_key_return_call`，逐句显示 3 句方式B对白 |
| 通讯收口 | 完整播放后写入 history，阶段变 `beacon_ready` |
| 信标落地 | 真实 wrapper 实例化、0.6 秒后 `interaction_ready` 为真 |
| 能力 | `defense_encounter_enabled=false`，不产生防守遭遇 |
| 同步 | 主动交互启动，8 秒读条，图片帧可见 |

结果：`30 checks / failures=[]`，退出码 `0`，引擎错误 `0`。

## 4. 修复：安全信标落点永久失败

### 4.1 现象

首次录制时通讯正常结束、`beacon_ready` 正常落盘，但安全信标反复告警：

```text
[E 1] WARNING: [TowerDescent3D] 安全信标没有可用真实地面落点；保留 beacon_ready 待办
```

信标始终不出现，只在 2 秒间隔里无限重试。

### 4.2 原因

`_restore_main_story_safe_beacon` 用**领取钥匙时的玩家位置**（首领箱前，位于入口高台，局部 y≈11.97）作为请求点，交给 `resolve_narrative_floor_positions`。该函数要求候选点局部高度≈0 且四点支撑射线命中同一水平面；入口高台/坡道上的点不满足，而 `max_adjustment_m=8` 的候选点里也没有可用点，于是整批拒绝。

即：**首领箱一旦落在高台，玩家又原地开箱，安全信标就永远落不下来。** 这是功能缺陷，不是录制脚本问题。

### 4.3 改法

`src/world3d/TowerDescent3D.gd` `_restore_main_story_safe_beacon`：请求点解析失败后，依次退回

1. 本房首领战场锚点 `room.boss_spawn_position_world()`（`BossSpawnCenter`）；
2. 房间中心 `room.to_global(Vector3.ZERO)`。

任一成功即用该点并 `push_warning` 记录“已退回房间内可站立地面”。仍失败才保留 `beacon_ready` 待办重试。

顺序上先战场锚点、后房间中心：Boss 房中心可能是深井，直接退中心不一定有承重地面。

## 5. 首领箱掉在门口：确认是夹具偏差，不是掉落逻辑问题

业主看片后质疑“钥匙为什么掉在门口”。核查结论：**掉落逻辑无误，是我的夹具把玩家停在门口。**

掉落点是 `Dungeon3D._clear_drop_offset()`：

```gdscript
var player_local := room.to_local(player.global_position)
var toward_center := Vector2(-player_local.x, -player_local.z).normalized() * 2.2
spawn_offset = Vector2(player_local.x, player_local.z) + toward_center
```

即「玩家所在位置 + 朝房间中心偏 2.2 m」，本来就是按玩家周围掉。而 `_setup_boss` 为了让 032 从门口沿坡道走位，把玩家停在**门内 3 m 的入口高台**，箱子便跟着钉在门口。

### 5.1 改法

`_capture_key_return` 先把玩家摆到战场中央（房间局部 `z=-17.5`，射线取真实承重面），再让正式掉落链自己选点。

### 5.2 改后证据

```text
player_local = (0.0, 0.0019, -17.5)
chest_local  = (0.0, 0.0, -15.3)
dist         = 2.2000
```

距离恰等于代码里的 2.2 m、方向朝房间中心 —— 掉落规则按设计生效。

## 5.3 产物

| 项 | 值 |
|---|---|
| 视频 | `ShellStorm2-work/verification/narrative_recording/20261118_1700_boss_key_return_center/远征01_击败Boss_钥匙返航通讯_安全信标.mp4` |
| 原始 AVI | 同目录 `boss_key_return.avi` |
| 关键帧 | 同目录 `frames/chapter_032K_kr_01..09*.png` |
| 规格 | 1280×720、30 FPS、699 帧、23.3 秒、H.264 |
| 报告 | 同目录 `frames/report.json`（`checks=31`、`failures=[]`） |

战场中央版（最终）：首领箱落在主角前方 2.2 m；方式B双侧立绘（左绿苔全息、右主角）；安全信标落地并出现交互提示；同步阶段显示“撤离同步”进度条；全场无怪物。

早期门口版（`20261118_1628_boss_key_return_final`）保留为对照，不作为交付。

## 6. 已知边界

- 录制夹具把“击杀”“走到箱前”“走到信标旁”压成定位步骤，不是玩家手动操作的完整走位；正文镜头、对白、落地动画、读条与结算都是正式链路。
- 视频时长 23.8 秒是 `--fixed-fps 30` 下的等价时长；实际渲染墙钟为 40.5 秒（机器渲染慢），不表示剧情被压缩。
- 本轮未重跑 031/032/033 的录制；032K 分支新增未影响既有章节的断言路径。
- 主线集成专项（`main_story_integration --logic`）已在同一隔离副本复跑，用于确认落点回退没有破坏既有安全返航链，结果见 §7。

## 7. 回归结果

改完 `_restore_main_story_safe_beacon` 后在隔离副本复跑主线集成专项：

- `main_story_integration --logic`：退出码 `0`、引擎错误 `0`、`119 checks`、`failures=[]`
- 结果文件：`ShellStorm2-work/verification/narrative_presentation/20261118_155226_34b0ba/result.json`
- 覆盖：安全信标完整链、普通信标刷怪对照、旧 schema 迁移、死亡取消、存档失败重试、返航通讯 skip 可重试

落点回退只在原解析返回空时触发，正常落点路径行为不变；因此既有 119 项断言全部保持通过。

## 8. 改动文件

| 文件 | 内容 |
|---|---|
| `tests/verification/capture_main_story_chapter.gd` | 新增 `032K` 章节码与 `_capture_key_return`；032 专属门闩断言加章节条件 |
| `src/world3d/TowerDescent3D.gd` | 安全信标落点解析失败时退回首领战场锚点／房间中心 |
| `docs/v0.1/development/README.md`、`CHANGELOG.md` | 登记本记录 |

未改：剧情 JSON、对白文本、镜头时序、Boss 房编成、安全信标资产、账本。
