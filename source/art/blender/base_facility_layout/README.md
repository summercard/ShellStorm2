# base_facility_layout · 基地设施布局资产

> ShellStorm2 顶视角射击搜打撤肉鸽 —— 基地设施（HQ）Blender 源、派生导出与 Godot 导入链。

## 当前来源策略

自 2026-09-12 起，**仓库中实际存在的 Blender 源文件就是正式资产来源**。

- 主基地当前正式母版：`source/base_facility_runtime_layout_hq_v026.blend`
- 后续如果继续更新，复制当前最高版本并提升版本号，例如 `v026 -> v027`
- 新版本生成后，**数值最高的完整源版本自动成为新的正式来源**
- 历史版本继续保留，用于回滚和追溯，不删除
- 当前运行资产可以是 v021-v025 的增量组合；账本必须记录实际运行时版本，不能假定所有资产都来自同一版本
- v026 正式源已删除退役资产 `63_设备蒸汽动效组_资产包`；该资产不再导出、不再进入运行时场景。
- 禁止把 v017、v021 等历史版本写死为“当前源”

## 目录结构

```text
base_facility_layout/
├── source/                                 当前与历史母版源
│   ├── base_facility_runtime_layout_hq_v017.blend
│   ├── ...
│   └── base_facility_runtime_layout_hq_v026.blend   ← 当前正式母版
├── export/                                 按源版本派生的导出文件
│   ├── v017/
│   ├── v021/
│   ├── v022/
│   ├── v023/
│   ├── v024/
│   └── v025/
├── component_packages/                     当前组件清单与历史版本目录
└── 使用说明.md
```

## 版本规则

1. 源文件命名：`base_facility_runtime_layout_hq_v<NNN>.blend`
2. 派生文件命名：`base_facility_runtime_layout_hq-v<NNN>-<scope>.blend`
3. 派生版本必须等于被选中的源版本。
4. Blender 源内容发生几何、材质、拆分或接口变化时，创建更高版本，不原地修改已发布基线。
5. 只有当前基线制度化的非内容性修复，才允许在原版本上执行；执行后必须重新计算源、派生、GLB、PackedScene 和台账 SHA。
6. Godot 账本要区分：
   - `当前母版来源`：当前最高 Blender 源
   - `运行时资产版本`：包装场景和 GLB 的实际版本

## 当前材质规则

场景和固定设施统一只使用以下四个材质角色：

- `01_精工金属_紫色骨架`
- `02_细腻哑光_青绿大面`
- `03_清漆反光_紫粉点缀`
- `04_柔和自发光_UI灯光`

禁止保留以下迭代遗留物：

- `.001`、`.002` 等 Blender 自动后缀
- `_v018公共色盘`、`_全息增强_v022`、`_117转角墙外链修正版` 等版本化材质名
- 未使用但仍保存在 `.blend` 中的旧材质球

当前主基地 v025 已由：

`tools/blender/normalize_current_base99_materials.py`

收敛为四个标准材质。

## 当前正式运行入口

- 美术布局：`assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn`
- 墙面内容聚合：`env_base99_wall_contents_root_top3d_v003.tscn`
- 剩余设施聚合：`env_base99_remaining_facilities_root_top3d_v004.tscn`
- L 型楼梯：`env_base99_stair_l_z5_root_top3d_v006.tscn`
- L 型转角墙：`env_base99_corner_l_5m_root_top3d_v003.tscn`
- 门墙：`env_base99_wall_door_5x9_root_top3d_v003.tscn`

正式关卡只实例化 PackedScene 包装场景，不直接实例化裸 GLB。

## 维护命令

当前源材质收敛：

```powershell
blender --background --python tools\blender\normalize_current_base99_materials.py -- `
  --blend source\art\blender\base_facility_layout\source\base_facility_runtime_layout_hq_v026.blend
```

当前引用 GLB 材质收敛：

```powershell
python tools\asset_pipeline\normalize_scene_facility_glb_materials.py `
  --project . --referenced-only
```

批次 JSON 来源与哈希修复：

```powershell
python tools\asset_pipeline\repair_base99_asset_lineage.py --project .
```

Excel 台账同步：

```powershell
python tools\asset_pipeline\sync_base99_current_ledger.py --project .
python scripts\check_asset_registry.py --scope structure
python scripts\check_asset_registry.py --scope full
```

Godot 材质去重验收：

```powershell
godot --headless --path "F:\wxgame\ShellStorm2" --script "res://tools/asset_pipeline/validate_base99_godot_materials.gd"
```

## 原则

- Blender 源是资产本体与版本来源。
- GLB 和 PackedScene 是派生物，不能反向定义源版本。
- 历史版本只用于回滚，不得替代当前最高源版本。
- 当前正式资产必须使用四个标准材质角色。
- 文档、JSON 台账、Excel 台账和 Godot 实际引用必须指向同一资产端。
