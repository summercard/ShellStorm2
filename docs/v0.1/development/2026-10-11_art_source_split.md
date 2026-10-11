# 2026-10-11 美术制作源与运行资产分离

功能：ASSET-PIPELINE / WORLD-BLOCKS / PLAYER-STATE / ENEMY-AI。工程版本保持 0.1.0；资产文件名、版本、AssetID 与运行接入不因整理改变。

## 最终结构

规则主源为 [美术制作源目录](../../ART_SOURCE_LAYOUT.md)。工程根 `art_source/` 集中当前原始美术文件、必要独立组件/优化母版、设计 JSON 与制作清单；原 `source/art` 位于 `art_source/design`，旧网页工具设计位于 `art_source/legacy_design`。正式 `assets/art` 的 GLB、运行贴图、导入 sidecar、Godot 包装与代码引用保持原位。

当前保留 1,095 份 Blender 源，制作目录共 4,210 个文件，约 **2.793 GiB**；`assets/art` 约 **0.538 GiB**。塔4保留 v010 制作母版和远景母版；移除其 v002/v004/v006/v008/v009 旧制作目录、Boss 改动前快照及其他过程导出/验收/缓存。不同资产或制作角色的独立最新组件、优化 Blend 和外链库继续保留，不按整个目录的最大版本数字批量删除。

工程内旧过程资产减少约 **2.489 GiB**，原位置文件保存在上层 `ShellStorm2-backup/2026-10-11_art_source_split/original_tree`。修改前副本在同主题 `before_edits`；同盘归档不释放整盘空间。Git 历史与本机 Git LFS 缓存另外计量，未重写 Git 历史。

## Git 与导出边界

- 制作目录参与 Git；1,095 份 Blend 的 Git LFS 指针逐项核对实际 SHA-256 和大小，PSD 也配置 LFS。
- 移除原“大源不入库”例外；`art_source/.gdignore` 与预设的 `art_source/*` 共同禁止导入/打包。正式导入文件原路径不变。
- 39 份运行 JSON 的源路径索引改为制作目录，`data` 中运行内容保持字节一致。
- 精确迁移与归档见 `assets/registry/art_source_migration.json`；母版入口见 `current_source_index.json`。九分账本 1,062 个资产完整保留，版本列不变，只更新本次路径和有证据的源哈希。

## 约束与工具

更新 AGENTS、工作区规范、3D 命名与导入规范、角色制作规范、资产规范及账本入口。新增 `art_source_paths.py` 为制作脚本解析旧式拼接路径。运行投影输入位置同步更新。旧网页设计工具从新目录保存/读取，原 `/save/` URL 保持兼容。

34 个相关 skill 的存放路径和交付规则已更新，覆盖角色六段链、房间组件、场景、道具、武器、UI、音效、音乐和台账。唯一正本及项目/用户副本逐文件一致；工作区级 skill 检查通过。之前未纳入四副本的项目角色阶段和用户媒体 skill 本轮建立正本，不反向覆盖其他既有正本。

## 验证与边界

| 检查 | 当前结果 |
|---|---|
| 原位资源保真 | 5,011 个 GLB、贴图、导入设置、场景、材质与代码文件 SHA-256 全部不变 |
| Blender 外链 | 944 份 Blend；解压后除 Image/Library 路径数组外所有字节一致，新外链目标存在 |
| Blender 原生加载 | 11 份代表性母版，含全部五份库引用母版，缺失依赖 0 |
| Git 制作源 | 4,210 文件已跟踪，1,095 个 Blend LFS 指针正确，忽略项 0 |
| 源目录、工作区、导出边界 | 均通过 |
| 运行 JSON 投影 | 39 文件字节一致 |
| 分账本保真 | 1,062 资产 / 九域，通过 |
| 制作脚本 | 353 个涉及修改的 Python 文件语法核对，无新增错误；网页工具设计 JSON/GLB 读取 HTTP 200，字节一致 |
| 运行贴图预算 | 106 贴图、1,474 GLB，通过；本轮未修改图像 |
| Windows 实际 PCK | **267.275 MiB / 7,088 条目**；`art_source`、Blend、PSD 0 条目 |

不宣称全量游戏验收通过：全量资产登记仍有原有 514 项哈希债务；文档默认 Python 环境仍有原有缺页、六个未登记验收入口和 openpyxl 缺失；运行命名门禁仍有原有违规。全量 skill 镜像九项红项仅涉及本轮未修改的会议转录 skill 与 sofunny-image，34 个本轮相关 skill 镜像一致。未运行 APK 或完整游戏流程。

过程证据、导出包、专项日志与 Git 结果位于工程外 `ShellStorm2-work/sessions/2026-10-11_art_source_split`。本轮开始前的剧情代码与设计 JSON 改动不混入此次提交；旧剧情验收临时产物已完整迁至工程外 `ShellStorm2-work/scratch/2026-10-11_existing_narrative_verification`。
