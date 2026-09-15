# 楼梯间 Blender 美术源目录规范化 v019

## 目标

将已验收的 v019 楼梯间美术场景从工具工作目录整理为项目资产源目录，明确唯一 Blender 源、组件清单、验收图和 QA 的对应关系；不修改几何、材质、运行时 GLB 或 Godot 引用。

## 交付事实

- 当前 Blender 美术源为 `assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v019/env_tower_stairwell_art_source_v019.blend`。
- 同级 `asset_manifest.json` 登记资产 ID、版本、基线、组件目录、验收图、QA、输出网格数和运行时状态。
- `component_packages/` 保存 10 个末级组件包的 manifest、catalog 和 tree；`renders/` 保存总览及开口近景；`qa/` 保存范围锁定脚本和报告。
- 原 `tools/3Dgame-design/save/blocks/stairs/whitebox_tower_stairs_v019/` 改为工作台快照，仅保留回滚用途并写明迁移位置。
- `stairs_12m/README.md` 区分 v001 几何基线源与 v019 当前美术源；Godot 仍使用既有 GLB，未触发重新导入。

## 验收

- 从新规范路径打开 Blend 并运行范围锁定脚本：退出码 0，301 个输出网格、10 个非空且唯一归属组件包，290 个锁定对象与 v018 一致。
- 从新规范路径执行 Blender 材质与 PaletteUV 专项：退出码 0，640 个全场景网格、21,422 个面通过。
- `python3 scripts/check_documentation_contracts.py` 退出码 0。
