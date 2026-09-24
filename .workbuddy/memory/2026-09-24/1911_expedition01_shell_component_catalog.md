# 事务：远征01 壳体组件改注册表驱动（Task #39）

时间：2026-09-24 19:11

## 做了什么

把 `DungeonRoom3D._authored_component_prefab()`（原 L1640-1653 的硬编码 `match` 表）
改为**注册表驱动**，并新建跨区运行时注册表。

### 新增（全部 CRLF）

| 文件 | 作用 |
| --- | --- |
| `assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json` | 运行时壳体通用组件注册表。schema `shellstorm2.runtime_shell_component_catalog.v001`，6 件：5 类壳体件 + 门扇。每件 = `component_id`（通用件名 `ENV-SHARED-GENERIC-*`）＋ `aliases`（具体批次号）＋ `slug`/`category`/`slot_role`/`source_package_id`/`prefab_asset_id`/`prefab_path` |
| `assets/art/environments/tower_zones/shared/runtime/qa/probe_shell_component_catalog.gd` | 探针（`extends SceneTree`，`--script` 跑）。A 注册表自洽 / B 既有 5 个 ID 行为逐字不变 / C 通用件名与 alias 命中同一 prefab / D 共享源目录无孤儿件 / E prefab 根节点 asset_id 对齐 / F 未登记 ID 返回 null |

### 改动

- `src/world3d/DungeonRoom3D.gd`：新增 `SHELL_COMPONENT_CATALOG_PATH`
  / `SHELL_COMPONENT_CATALOG_SCHEMA` / `static var _shell_component_prefab_paths`
  / `static var _shell_component_catalog_attempted` / `_load_shell_component_catalog()`；
  重写 `_authored_component_prefab()`（查表 + `ResourceLoader.exists` + `load`）。
  L133-137 注释块同步为「注册表驱动」；5 个 `*_COMPONENT_*` 常量降级为「既有摆位源在用的批次号」。
- `assets/art/environments/tower_zones/expedition/runtime/README.md`：壳体 5 类一节改为
  「ID → PackedScene 由跨区注册表解析」，附 6 件表与四条不静默口径。

## 验收

| 项 | 结果 |
| --- | --- |
| `probe_shell_component_catalog.gd` | `SHELL_COMPONENT_CATALOG_OK pass=82 fail=0` |
| `verify_block00_floor98_assembly.tscn` | `BLOCK00_ASSEMBLY_OK checks=230`（改动前基线同值） |

## 口径与判例

- **单一真源** = `shared/runtime/shell_component_catalog.json`。它是仓库里第一个**运行时**注册表
  （既有 `shared/source/.../component_catalog.json` 与 `battle/source/.../v006/component_catalog.json`
  都是**源**注册表）。二者关系：源注册表说「这一件是通用件、来自哪个批次」；运行时注册表说
  「这个 ID 用哪个 PackedScene」。
- **双 ID 契约**：`component_id` 用通用件名（表达「这是通用件」），`aliases` 放具体批次号
  （`ENV-BATTLE-COMMON-*` / `ENV-TOWER-CORNER-L-5M`）。战区摆位源继续用批次号，远征位源可用通用件名，
  两侧命中同一 prefab。**不准出现只登记源、运行时解析不到的孤儿件**（探针 D 段盯）。
- **有意新增**：`ENV-BATTLE-COMMON-DOOR-5M` 旧表里没有（返回 null），本次解析到塔楼 A 套门扇
  `prp_tower_door_leaf_5m.tscn`。与「行为不变」分开断言，避免混为一谈。
- **`corner_l` 角色不走本表**：实际由 `_spawn_room_corner()` 装配（`FACILITY` 房取 `BASE99_CORNER_L_PREFAB`）。
  注册表为它登记只是保证 ID 可解析 + 台账可追溯。

## 坑

1. **`--path .` 会指错**：Bash 工具的默认 cwd 是**仓库父目录** `I:\工作项目\shellstrom2`（非仓库），
   cwd 不跨命令保留。必须每条命令自带 `cd /i/工作项目/shellstrom2/ShellStorm2 && ...`；
   漏了就变成「Godot 找不到 project.godot」并把进程挂着（实测挂了 4 分钟，靠 `taskkill` 收）。
2. **`for x in dict.get(k, []) as Array:` 有解析风险**：本文件统一改成先落变量
   （`var alias_list: Array = entry.get("aliases", [])`）再 `for`，避免 `as` 与 `in` 的优先级歧义。
3. **`--script` 模式下 autoload 不存在**：会报
   `Identifier not found: RuntimePerformanceManager / InputSettings / AudioManager`，
   连带 `RoomDoor3D.gd` / `RoomFurniture3D.gd` 等编译失败 —— 是 `--script` 模式的固有噪声，不是本次引入的红；
   探针只用静态函数，照常出结论（远征探针同样如此）。

## 未完

Task #40 Boss 房静态布局清单 / #41 通用壳体组合器 / #42 设计源房型模板约束与透传 / #43 账本与设计页同步跑门禁。
