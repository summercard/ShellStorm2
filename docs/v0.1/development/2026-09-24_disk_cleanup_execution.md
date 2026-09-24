# 磁盘清理执行记录

日期：2026-09-24。关联模块：ASSET-PIPELINE / TOOLING。设计规则未变，游戏版本仍为 0.1.0。盘点、筛选边界和剩余项见[磁盘清理审计](../audits/2026-09-24_disk_cleanup_candidates.md)。

本次删除 57 个无现行路径引用且可从 Git 恢复的旧版 Blender 源、78 个 Blender 自动回退文件、39 个 `.DS_Store`，并清空忽略目录 `outputs/` 的 47 个临时产物顶层项（保留 `.gdignore`）。未修改运行资产、Prefab、账本或游戏代码。20 个无主文件的 `.blend1`、122 个仍有引用的旧版源、正在使用中的 Godot 导入缓存和个人数据未动。

验证：`check_documentation_contracts.py`、`check_asset_runtime_naming.py`、`check_asset_registry.py --scope structure` 均退出0；`check_asset_registry.py --scope full` 退出非0，仅报告清理前已有的 GroundLootPickup3D.gd 哈希不一致1项。未执行 Godot 运行/真实渲染验收；旧 `outputs/` 结果不可作为当前证据。

后续：若要真正只保留每组最新 Blender 源，先逐资产核对正式运行版本与账本源路径，迁移生成脚本/manifest和可追溯关系，再按资产ID分批删除并验收。

补充执行：用户随后要求删除导入缓存。确认 `.godot/` 已被 Git 忽略、跟踪文件为0后，定向清理 `.godot/imported/` 和 `.godot/shader_cache/`；目录占用由约3.0 GiB降至约8.5 MiB。未动编辑器状态文件。文档契约检查仍退出0；由于编辑器尚在运行，缓存可能再次生成。
