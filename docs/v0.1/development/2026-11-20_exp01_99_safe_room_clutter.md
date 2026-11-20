# 远征 01／99 入口安全屋固定五件移除

2026-11-20 · `WORLD-INTERACTIVE-CLUTTER` / `WORLD-PLAN` · 主树 `0.2` / `64107848` + 原有工作区改动。依据 [易碎陈设设计](../design/场景可交互低模物件设计.md#正式接入与验收)。

- 远征 01 与测试远征 99 均在 `start` 安全屋停用固定的罐子、书本堆、花瓶、椅子、木箱。两份 `art_source/design/whitebox/tower_zones/{expedition_01,99}/v001/data/level_plan.json` 为真源，逐字节同步 `data/level_plans/{expedition_01,99}/level_plan.json` 及 `data/runtime_design_data_manifest.json` 对应两条摘要。仅增加 `furnishing.fixed_lobby_clutter_enabled=false`，未改变其它计划字段。
- 两关复用 `DungeonRoom3D` 原固定清单；01 静态壳与 99 程序化壳不改。不动门、灯、走行面、Boss、其他关卡数据与四类共享资源（Prefab、模型、碰撞、场景账本）；不新增存档字段。未改变传送落点和其它家具的缺省开关。
- `sync_runtime_design_data.py --check`：`0`，52 组、无漂移；`check_level_decoupling.py`：`0`，7 个容器无违规；`check_verification_registry.py`：`0`，321 场景唯一归属。未注入预期故障。
- 独立入口：`python -B scripts/run_expedition_layout_qa.py safe-room --godot <Godot console>`。隔离用户数据后读取两份正式场景，核对 `start` 零固定实例、预热列表为空且保留四墙角、两门侧和其他家具开关。该探针只签结构，不代签整关、画面或存档往返。Godot 4.7.2 首跑在 01 楼层壳体装配阶段达到 180 秒上限（`124`，通过标记 0，非预期脚本或引擎错误 0）；可见既有导入 UID 警告。01/99 正式入口装配、实景和存档往返尚未签通过。首轮日志见工程外 `verification/expedition_layout/20261120_183810_722590/`。
