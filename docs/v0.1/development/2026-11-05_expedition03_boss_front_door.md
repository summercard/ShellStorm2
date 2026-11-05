# 远征03 Boss 房前门特殊组件

- 日期：2026-11-05
- 关卡：`expedition_03`
- 结论：原 Boss 前门不是独立特殊门。虽然白盒/策略语义存在 `boss` 门型，但正式运行视觉仍复用 `ENV-EXP03-MANOR-DOOR-DOUBLE`。

## 交付

新增组件：`ENV-EXP03-BOSS-DOOR-RITUAL` / Boss房仪式封印门。

- 源包：`art_source/environments/tower_zones/expedition/source/common_components/v018/component_packages/boss_door_ritual/`
- 组件计划：`art_source/environments/tower_zones/expedition/source/common_components/v018/component_plan.json`
- 组件目录：`art_source/environments/tower_zones/expedition/source/common_components/v018/component_catalog.json`
- 优化输出：`art_source/environments/tower_zones/expedition/source/common_components/v018/export/v018/Boss房仪式封印门_优化输出_v018.blend`
- 运行视觉 GLB：`assets/art/environments/tower_zones/expedition/components/common_components/boss_door_ritual/env_boss_door_ritual_visual_top3d.glb`
- Godot Prefab：`assets/art/environments/tower_zones/expedition/runtime/common_components/boss_door_ritual/env_boss_door_ritual_root_top3d.tscn`

## 设计契约

- 门洞：2.2 × 2.5 m；源门板厚 0.18 m；可视包络 2.2 × 0.315 × 2.5 m。
- 原点：底面中心；Godot 正面 +Z；允许 Y 轴 0/90/180/270°。
- 组件是 `visual_only`，不携带碰撞，不携带门状态机。
- 不复制成 Boss 房整屋 GLB，不替换远征03普通门。

## 运行时接入

- `FloorPlanGenerator.gd`：当端口目标房间角色为 `BOSS` 时，端口写入 `door_visual_scene`。
- `LevelPlanLoader.gd`：透传 `door_visual_scene`，避免白名单式加载时静默丢字段。
- `DungeonRoom3D.gd`：按端口加载视觉 Prefab；没有覆写时沿用主题/历史门扇选择。
- `RoomDoor3D` 继续持有碰撞、可开启/不可开启、自动开合、战斗封锁、共享门和存档派生语义。
- 因此实际作用范围只有 `boss_foyer → boss` 这条连接，不改钥匙、清房、门状态机或存档规则。

## 账本

已更新场景分账本：

- 《资产主表》新增 `ENV-EXP03-BOSS-DOOR-RITUAL`，资产行 1019。
- 《3D-场景通用》新增 Prefab 行 814。
- 《域变更日志》追加 `v0.1.71`。
- `assets/registry/ledger_split_baseline.json` 已补录新 AssetID；原有资产指纹保持不变。

## 验收记录

- Blender 制作脚本 Python 编译通过。
- Blender 产出命令成功，源 Blend、优化 Blend、GLB、Prefab、manifest 均存在。
- Godot headless editor 解析退出码 0。
- Godot 扫描期间出现既有的共享色盘无效 UID 回退警告和历史重复 UID 警告；未发现本次 Boss 门资源加载错误。
- 尚未做正式游戏画面渲染验收；manifest 保留 `godot_rendered = false`、`formal_scene_assembled = false`，因为本轮需求是组件制作与端口接入，不是整屋场景重装配。
- 端口运行时探针未能完成：加载整套 `FloorPlanGenerator` 时被工程既有的 `MonsterInjector.gd` 全局类解析错误阻断（`EliteRosterService` 未找到），随后探针进程超时终止；这不是 Boss 门资源或本次三段字段链的错误。已用静态链路验收确认 `FloorPlanGenerator → LevelPlanLoader → DungeonRoom3D` 三处均保留 `door_visual_scene`，且 `flow_03` 的 `boss_foyer → boss` 边存在。
- 全量场景账本门禁仍报告两条既有 `sha_mismatch`（`ENV-BASE99-REMAINING-FACILITIES-V021`、`ENV-OPENWORLD-UNDERGROUND-STREET`），新 Boss 门行不在失败项中；文档合同门禁的破链与验证注册缺口也为既有问题。分账本无损、结构、命名、解耦和 flow 配额门禁通过。
