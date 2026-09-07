# base_facility_layout · 基地设施布局资产

> ShellStorm2 顶视角射击搜打撤肉鸽 —— 基地设施（HQ）布局的 Blender 源与导出。

## 📂 目录结构

```
base_facility_layout/
├── source/                                    ← v017 完整布局源（可编辑）
│   └── base_facility_runtime_layout_hq_v017.blend
├── export/                                    ← 基于 v017 源的优化导出
│   └── v017/
│       ├── base_facility_runtime_layout_hq-v017-structural.blend         （结构）
│       ├── base_facility_runtime_layout_hq-v017-wall_contents.blend      （墙体内容）
│       └── base_facility_runtime_layout_hq-v017-remaining_facilities.blend （剩余设施）
├── component_packages/                        ← v017 源的组件清单（按区域分）
│   ├── architecture/  east_facilities/  west_facilities/
│   ├── loft/  underloft/  warehouse/  floor/  support/
│   └── component_sets/   east_door_wall_set/  west_door_wall_set/
└── 使用说明.md
```

## 🎯 源 vs 导出 · 派生关系

| 维度 | source/ | export/ |
|---|---|---|
| 性质 | **源**，可编辑 | **派生**，只读 |
| 内容 | 完整布局（结构 + 墙体内容 + 设施全部合在一个 .blend） | 按"结构 / 墙体内容 / 剩余设施"三组分拆，便于导入 |
| 命名 | `..._hq_v0XX.blend`（独立版本号） | `..._hq-v0XX-<类型>.blend`（连字符标记派生，版本号绑定源） |
| 迭代规则 | 源变 → 版本号 +1；新源替代旧源 | 源不变 → 导出按"迭代轮次"重做，不升版本号 |

**关键**：**导出版本号永远等于源版本号**。即使导出迭代了 10 次、文件名依然是 `-v017-...`。

## 📐 命名规则

### 源文件
```
base_facility_runtime_layout_hq_v<NNN>.blend
```
- `<NNN>` = 3 位版本号（v001、v002 …）
- 源发生实质性变化 → 版本号 +1

### 导出文件
```
base_facility_runtime_layout_hq-v<NNN>-<类型>.blend
```
- `<NNN>` = **必须等于源版本号**（派生绑定）
- `<类型>` = 三选一：`structural` / `wall_contents` / `remaining_facilities`
- 导出重做时（如重新分组、修bug）→ **覆盖原文件，不升版本号**

## 🔄 派生与迭代流程

```
source/v017/base_facility_runtime_layout_hq_v017.blend   ← 编辑（Blender）
        │
        │  File → Append / 导出分组（脚本或手工）
        ▼
export/v017/base_facility_runtime_layout_hq-v017-structural.blend
export/v017/base_facility_runtime_layout_hq-v017-wall_contents.blend
export/v017/base_facility_runtime_layout_hq-v017-remaining_facilities.blend
```

- **源升级** → 建 `source/v018/`、`export/v018/` 两个新目录
- **导出重做** → 覆盖 `export/v017/` 下三个文件，**不**建新目录
- **历史备份** → 由 git 负责（不要在本目录留时间戳后缀或 v001_v002_... 那种历史副本）

## 🧹 维护规则

1. **本目录不留历史**：v001 ~ v016 的所有 .blend / 脚本 / 预览图都已在 git 历史里，本目录只保留**当前源 + 当前导出**
2. **新源升版**：把旧 `source/v017/` 整个 → `source/v018/`，并把 `export/v017/` → `export/v018/`，新版本号绑新源
3. **导出文件命名强制 v<NNN>-<类型>**：发现 `v021_wall_contents.blend` 这种"导出用了独立版本号"立刻改回
4. **不要在主目录留 .blend**：所有 .blend 必须落到 `source/` 或 `export/`

## 📜 历史归档说明

v001 ~ v016 的所有历史 `.blend`、`.blend1`、`.py` 脚本、预览 PNG、`component_packages_v008~v016/` 已于 2026-09-07 清理。历史内容保存在 ShellStorm2 git 仓库历史提交中，需要时通过 git checkout 找回。

清理原因：
- 文件体积庞大（数 GB），本地工作目录膨胀
- 历史版本功能已迭代替代
- git 历史是唯一的真相源，本地无需冗余副本