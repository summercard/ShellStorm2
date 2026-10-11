# 美术制作源与运行资产目录

适用工程 0.1.0；2026-10-11 起生效。制作源与发行资源分开，资产版本号不因本次迁移变化。

```text
ShellStorm2/
├─ art_source/                   当前可编辑源，Git LFS 管理大型母版，Godot 不导入、不打包
│  ├─ .gdignore
│  ├─ characters/ enemies/       玩家、NPC、怪物、Boss 的模型与动画母版
│  ├─ environments/              场景、设施、组件库和布局源
│  ├─ props/ weapons/            道具、武器源
│  ├─ vfx/ items_weapons/         特效与共享制作模板
│  ├─ ui/ audio/ music/           UI 与音频制作源的后续落位（按账本建立）
│  ├─ design/                    原 source/art：白盒、设计 JSON、布局母版
│  ├─ legacy_design/             旧网页设计工具保存的可编辑设计
│  └─ intake_recovered/          已找回的独立最新源
├─ assets/art/                   正式导入资产；既有路径、文件名及版本保持不变
│  ├─ **/components/             GLB、运行贴图
│  └─ **/runtime/                Godot 包装、正式布局
├─ assets/registry/              分账本、当前源索引、迁移清单
└─ data/                         必须随游戏发布的运行 JSON 投影
```

## 路径与所有权

- 原 `assets/art/<分类>/<套件>/source/...` → `art_source/<分类>/<套件>/source/...`。保留内部分组和现有版本号；制作源不再写入 `assets/art`。
- 原 `art_source/design/...` → `art_source/design/...`；原 `art_source/intake_recovered/...` → `art_source/intake_recovered/...`。
- 原模板或散落的 `.blend`、`.psd` 同样进入 `art_source`。精确文件映射见 `assets/registry/art_source_migration.json`，当前母版入口见 `assets/registry/current_source_index.json`。
- 正式 GLB、贴图、`.import`、PackedScene、材质和代码引用不因源迁移改动。公共运行色盘继续位于 `assets/art/shared/palette/`；Blender 使用修复后的相对外链，不复制色盘。
- 每个资产/部件/模型或动作角色保留自己的最新母版。不同用途不能仅因版本数字较小而删除；被当前母版外链的组件库属于必要依赖。
- 最新独立组件 Blend、可重导的优化 Blend 与其资产清单属于必要制作源。即使历史分组名为 `component_packages/` 或 `export/`，也不能把它们当重复 GLB 导出删除；可再生成的 GLB、导入缓存和过程截图才移出工程。
- 当前制作版本原样保留。以后制作新版本时，把被替代的旧源移到上层 `ShellStorm2-backup/<日期>_<主题>/original_tree/`，不在工程中叠放历史过程源。

## 输出与 Git

- 临时导出、QA、预览、截图和日志写入 `scripts/workspace_paths.py` 的 `work_path()` 出口，位于工程外 `ShellStorm2-work/`；确认后的正式 GLB 才覆盖稳定 `components/` 路径。
- `art_source/.gdignore` 与导出预设的 `art_source/*` 双重隔离。不得由运行代码读取制作源；必要 JSON 通过 `scripts/sync_runtime_design_data.py` 投影到 `data/`，保持字节一致。
- `art_source/**/*.blend`、`*.psd` 使用 Git LFS；不再套用旧的“大源不入 Git”例外。协作者克隆后执行 `git lfs pull` 获取原文件。工作区整理不重写既有 Git 历史。
- 台账源路径更新到 `art_source`；运行路径、AssetID、版本和制作状态保持不变。只更新本次源路径修复对应的哈希，不接受无关历史漂移。

## 验证

运行 `python scripts/check_art_source_layout.py`、`python scripts/sync_runtime_design_data.py --check`、`python scripts/configure_export_boundaries.py --check`。发行前实际导出 PCK，确认没有 `art_source/` 条目或制作源，并核对正式资源哈希。Blender 外链需检查文件存在性，并对库引用母版进行 Blender 原生加载。
