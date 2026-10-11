# 工作区与目录规范

状态：工程目录与工程外产物的稳定约定。适用工程：0.1.0 起。生效日期：2026-10-11。
基线实测见 [工程瘦身执行记录](v0.1/development/2026-10-11_workspace_slimming.md)；本文是该记录的**常驻规范**，不是时点交付记录。

## 1. 这份文档回答什么

- 工作区里每个顶层目录**是什么、归谁管**。
- 一次会话/一次制作产生的**产物该写到哪**——这是最常出错的地方。
- 哪些行为被**门禁脚本**强制、怎么自查。

## 2. 工作区根布局

工作区根 `I:/工作项目/shellstrom2/` **只允许 8 项**（2026-10-11 定稿）：

| 顶层项 | 体积 | 角色 | 归属 |
|---|---:|---|---|
| `ShellStorm2/` | 12.22 GB / 100,675 文件 | **唯一 Git + Godot 工程根** | 工程资产 |
| `ShellStorm2-backup/<日期>_<主题>/` | 48.02 GB / 249,261 文件 | 改动前备份：`before_edits/` · `original_tree/` · `management/` | 归档，只读 |
| `ShellStorm2-work/` | 5.24 GB / 5,711 文件 | **工程外一切产物的唯一出口** | 可丢弃 |
| `.codex-tools/` | 1.62 GB | 外部代理工具缓存 | 工具 |
| `结构打包审计_20261011/` | 60 MB | 原始打包审计与候选分析 | 审计证据 |
| `.workbuddy/` | 3.4 MB | 工作区级记忆（**与工程内 `.workbuddy/` 两套独立，不得混写**） | 记忆 |
| `仓库体积审计_20261011.md` | — | 体积审计报告 | 报告 |
| `nul` | 0 B | Windows 保留设备名残留，**删不掉**，无害 | 遗留 |

🔴 **新增任何顶层目录前先自问：该不该进 `ShellStorm2-work/`。** 除上表 8 项外，根目录不新增条目。

## 3. 工程内关键目录（`ShellStorm2/`）

| 路径 | 角色 |
|---|---|
| `src/`、`scenes/`、`data/` | 正式代码、场景、运行数据 |
| `assets/art/**/components/`、`runtime/` | 正式 GLB/贴图与 Godot 包装；**路径不含版本号**，替换即覆盖同名 |
| `art_source/` | 当前可编辑美术母版与设计源；参与 Git/LFS，Godot 不导入、不打包；见 [制作源目录规范](ART_SOURCE_LAYOUT.md) |
| `assets/registry/` | 九分账本、当前源索引、旧源归档索引 |
| `docs/`、`tests/` | 设计与文档、验收入口 |
| `scripts/`、`tools/` | 必要工具与验收入口。`scripts/blender/` 是 **Blender 制作/绑骨脚本的家**（309 份已入库） |
| `.godot/` | 本机可重建缓存，不入库 |

## 4. 工程外产物出口：`ShellStorm2-work/`

🔴 **一切工程外产物写这里，禁散落工作区根、禁在工程内新建整项目副本。**

| 子目录 | 放什么 | 现有 |
|---|---|---:|
| `sessions/<日期>_<主题>/` | 一次会话/一次交付的过程与结论 | 0.76 GB |
| `scratch/` | 临时工作区、中间产物 | 3.78 GB |
| `outputs/` | 交付给业主的成果（报告、打包、截图集） | 0.61 GB |
| `probes/` | 探针产物：隔离 APPDATA、探针日志、一次性脚本 | 72 MB |
| `audits/` | 审计证据与可复用审计工具箱 | 12 MB |
| `verification/` | 验收截图等视觉证据 | 1.2 MB |
| `build/` | 导出包（Windows PCK、APK 等） | — |

### 代码出口（唯一正确姿势）

```python
import sys; sys.path.insert(0, 'scripts')
import workspace_paths as wp
p = wp.work_path('sessions/2026-10-11_slimming/export.log')   # 自动建父目录
```

`work_path()` 会拒绝落在工程内的路径并 raise，**不要绕过它手拼路径**。根目录可用环境变量 `SHELLSTORM_WORK_ROOT` 重定向。

若某工具确实只能接受绝对路径，用 `wp.work_root()` 出发拼接，不要写字面量。

## 5. 边界规则

### 必须

- 工程外产物 → `ShellStorm2-work/`；探针隔离 `APPDATA` 同理（别再往工程根丢 `_godot_appdata_*`）。
- 改动工程文件前，先在 `ShellStorm2-backup/<日期>_<主题>/before_edits/` 留改动前副本。
- 临时脚本重定向用 `> /dev/null`。

### 禁止

- 🔴 工作区根新增目录/散件。
- 🔴 在工程内新建整项目副本（历史教训：验证套件每轮留 5 GB，累积到 289 GB）。
- 🔴 写 `> nul` 或 `> $null` —— 二者在 bash 下会创建**删不掉的** 0 字节文件（Windows 保留设备名；`\\?\` 前缀、短路径、`\\.\`、Win32 原生 `MoveFileW`/`DeleteFileW` 全部被拒）。已有一个，勿再造。

## 6. 强制执行与自查

| 工具 | 作用 | 现状 |
|---|---|---|
| `scripts/check_workspace_hygiene.py` | 工程内不得留有 `outputs`/`output`/`_scratch`/`_scratch_logs`/`build`/`.codex-tmp`/`.tmp`/`.tmp_plan`/`Godot`（除 `.gdignore`）；运行数据投影一致；导出预设排除项齐全 | 实测 **0 issue** |
| `scripts/workspace_paths.py` | 工程外路径出口，越界即 raise | — |
| `scripts/purge_stale_verification_workspaces.py` | 清理陈旧验证工作区 | — |
| `scripts/run_verification_suite.sh` | 套件自带隔离工作区（整份复制 + 独立 user 目录） | — |

提交前：`python3 scripts/check_workspace_hygiene.py`。

## 7. 备份与回滚

- 备份目录按 `<日期>_<主题>` 分，内含 `before_edits/`（改动前副本）、`original_tree/`（按原相对路径保留迁走的文件）、`management/`（搬迁日志、校验、恢复清单）。
- `management/moves.jsonl` 每条记原位置、新位置、理由、校验结果。
- 回滚：以 `before_edits/` 为本次开始时的副本**逐文件比对**后恢复，**不要用整树覆盖**，以免抹掉后续制作进展。
- 同盘归档**不释放整盘空间**，只改变职责边界。

## 8. 变更本文的流程

本文是常驻规范，改动等同改变工作方式：

1. 先在实际会话中验证新约定可行（跑一轮真实产物落地）。
2. 更新本文相应表格与红线。
3. 若涉及工具行为，同步改 `scripts/workspace_paths.py` / `check_workspace_hygiene.py`。
4. 在 `docs/v0.1/development/` 追加一条交付记录说明改了什么、为什么。
