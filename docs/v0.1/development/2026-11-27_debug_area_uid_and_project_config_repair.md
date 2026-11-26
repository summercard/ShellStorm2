# 调试区报错修复：场景 UID 与项目配置

日期：2026-11-27
记录ID：DEBUG-UID-CONFIG-20261127
功能归属：WORLD-PLAN / ASSET-PIPELINE / TOOLING
工程版本：0.1.0
状态：本轮报错已修复；未提升远征01整关验收状态。

## 1. 问题与根因

调试区的 Godot 编辑器扫描报告了 4 组重复场景 UID：

- `uid://coi5sc0c5ag4c`：远征01 `f00_room_01_static_layout.tscn` 与旧 `f00_room_01/room_static_layout.tscn`
- `uid://cdibqxdbkd651`：远征01 `f00_room_05_static_layout.tscn` 与旧 `f00_room_05/room_static_layout.tscn`
- `uid://dj0eld0bcscjt`：远征01 `f00_room_08_static_layout.tscn` 与旧 `f00_room_08/room_static_layout.tscn`
- `uid://cg5q82md0qmm5`：远征01 `f00_room_09_static_layout.tscn` 与旧 `f00_room_09/room_static_layout.tscn`

这 4 组是两套正式资源同时保留时复用了同一 UID，不是运行逻辑分支问题。重复 UID 会让 Godot 文件系统缓存无法稳定区分资源，属于编辑器资源索引错误。

同时发现工作区 `project.godot` 曾被截断为 565 字节；工程外临时恢复文件 `project.godot~RF1ee95451.TMP` 保留了完整配置。恢复后核对并撤销了该临时配置中仅用于探针的自定义用户目录，确保正式工程不被写入 `ShellStorm2MMProbe_1793180917`。最终 `project.godot` 与版本库基线无差异，保留正式 `UiCursorMode` 自动加载项及 `shellstorm_shader_volume` 插件登记。

## 2. 修复内容

只为远征01的 4 份当前正式布局场景生成新 UID，未改节点、摆位、网格、碰撞、门位、房间 ID 或存档 schema：

- `assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_01_static_layout.tscn`
- `assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_05_static_layout.tscn`
- `assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_08_static_layout.tscn`
- `assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_09_static_layout.tscn`

新 UID 只承担 Godot 资源身份，不改变运行时资源路径和数据 ID。

## 3. 验证结果

| 命令/检查 | 结果 | 说明 |
|---|---|---|
| Godot 编辑器诊断 `--headless --editor --quit` | 通过，退出码 0 | 修复后无 `UID duplicate`、`ERROR:`、`SCRIPT ERROR`、`Parse Error`、`Failed to load` 或 `Cannot open file` |
| 定向场景 UID 扫描 | 通过 | 扫描 60 份场景，60 个唯一 UID，0 组重复 |
| `python scripts/check_expedition_scene_height_contract.py` | 通过 | 远征01正式布局 12/12、低墙 Prefab 11/11，`errors=[]` |
| `python scripts/check_level_decoupling.py` | 通过 | 7 个共享机制容器，0 违规 |
| `python3 scripts/check_documentation_contracts.py` | 未全通过（既有问题） | 673 份文档、3592 个本地链接；仍有 11 条既有断链，本轮未扩大范围 |
| `git diff --check` | 未全通过（既有问题） | 只命中 3 份技能镜像的既有行尾空白；不属于本次修复范围 |

## 4. 遗留与边界

- 本轮没有修改 `godzilla-pet/tv/`、存档格式、游戏玩法数值或远征01整关验收状态。
- 工作区所在 I: 盘可用空间约 0.01 GiB；本轮首次读取 Git 状态时曾出现 `index.lock write error: Out of diskspace`。修复已写入工作区，但继续运行 Godot 导入、Git 操作或大文件写入前必须先释放工程盘空间。
- 当前工作区存在其他并发事务的大量未提交改动；本轮只确认并修改上面 4 份场景，未清理或回滚其他改动。
