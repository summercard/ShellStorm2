---
name: git-push-rebase-and-text-conflict-merge
description: 在多会话并发共用同一工作区的仓库里，安全完成「提交今日改动 → 变基到远端 → 推送 → 验证落地」全流程；并解决变基时的**文本冲突**（Markdown 表格相邻行、JSON 基线、记忆文件）。当出现 `behind N` 却"拉取失败/冲突打不开"、`git status` 有 `UU` 但 `--abort` 报无操作、或两个会话同时改了同一张功能表格的相邻行时使用。含三类冲突面各自的分流解法、门禁「合并前后同数值」判新增、以及推送落地必须以 SHA 逐字相同为准的判据。
agent_created: true
---

# 提交流程 + 文本变基冲突合并（多会话并发仓库）

## 何时用

- 用户说「推送一下今天的修改」「提交并推送」，而 `git status -sb` 显示 `behind N`（远端有新提交）。
- 变基时冲突文件是**文本**（`.md` 表格、`.json` 基线、`.workbuddy/memory/*.md`）——不是 xlsx（那是另一套，见 `xlsx-git-conflict-resolution`）。
- 症状：「拉取最新」后 `status` 仍挂 `UU`，但 `git merge --abort` / `git rebase --abort` 都报没有进行中的操作（僵尸冲突态）。

## 0. 先取真实状态（不要信上一轮快照）

```sh
git -c core.quotePath=false status --porcelain -uall
git status -sb | head -3
git -c core.quotePath=false rev-list --left-right --count HEAD...origin/<分支>
```

并发仓库里，别的会话/编辑器（Godot 常驻）随时可能动过工作区。按需分三类：

| 现象 | 含义 | 走哪条 |
|---|---|---|
| `0  0` 但有 `UU`，`.git/` 有孤儿的 `REBASE_HEAD`/`AUTO_MERGE` | **僵尸冲突态**：HEAD 已等于远端，只剩本地残留 | §1 |
| `N  0`（ahead N） | 只有自己的提交待推 | §3 |
| `0  N`（behind N） | 远端领先，须变基 | §2 → §3 |

## 1. 僵尸冲突态

判据是 `rev-list --left-right --count` 为 `0  0` —— **HEAD 已等于线上最新**，代码层面无须前进，要清的只是本地残留。

```sh
# 改前先冻结涉及文件（仓库约定：回退指针要入库）
mkdir -p .workbuddy/backup/<YYYYMMDD>_<主题>/before_edits
cp -p <冲突/被改文件> .workbuddy/backup/<YYYYMMDD>_<主题>/before_edits/

git reset --hard HEAD        # HEAD 即线上版本
rm -f .git/REBASE_HEAD .git/AUTO_MERGE
```

未跟踪文件（本地新写的报告等）不受影响，会保留。

⚠️ 用户说「冲突以线上为主」时，正是这套：备份 → `reset --hard HEAD` → 清孤儿文件。**不要**用 `git checkout --ours/--theirs`（僵尸态下它们会报错）。

## 2. `behind N`：提交顺序铁律

**先提交自己的改动 → `git fetch` → `git rebase origin/<分支>` → `git push`**。

顺序颠倒（先 pull/rebase）会把**未提交的已跟踪改动并掉**——`pull --rebase` / `rebase` / `reset` 都是回退矢量，未跟踪文件不受影响。

提交前按主题拆提交（如 ① 代码/文档/资产 ② 记忆与回退指针），便于冲突面收敛。

## 3. 变基冲突：四个冲突面分流

```sh
git fetch origin
git rebase origin/<分支>     # 冲突时进入 rebase 中间态
grep -n '^<<<<<<<\|^=======$\|^>>>>>>>' <冲突文件>
```

### 3.1 `.workbuddy/memory/<日期>.md`（各会话都往末尾追加）

两侧块**都保留**，按时间排序（旧在前），删掉 3 个标记行。
自证两手都要做：`git show <commit>:<file>` 逐块 diff，证明两侧逐字完整。

### 3.2 `docs/v0.1/MODULE_INDEX.md` 功能表格相邻行 ← 高频

两个会话各改了相邻的 `| FEATURE-ID | … |` 行时，git 把它们当成**同一区块**冲突，两侧各带 1 行自己的更新。

**解法＝逐行取各自较新的一侧**（不是整块取一侧），保持表格行数结构完整：

```python
# 两行各来自哪侧是确定的：远端/本地各更新了不同的功能行
new = [ [x for x in head if x.startswith('| INVENTORY-SLOTS')][0],
        [x for x in theirs if x.startswith('| FATE-RULES')][0] ]
```

判据：`grep -c '^<<<<<<<'` 归零，且表格行数与原结构一致。

### 3.3 `assets/registry/*.json` 基线（如 `ledger_split_baseline.json`）

两侧各自新增键/改 digest 时 git 通常**能自动合并**，但**必须验证**：

```sh
git diff origin/<分支> -- assets/registry/ledger_split_baseline.json   # 逐块确认两侧改动都在
```

本次实例：保留远端 3 处 UI 摘要更新（UI-SCREEN-BASE-VENDING / INVENTORY-3D / VAULT）＋本地 2 张新特效，`asset_count` 1280→1282。

### 3.4 `.xlsx` 等二进制

转 `xlsx-git-conflict-resolution` 做逐格比对与 XML 保真合并，别整份 `--ours/--theirs`。

解决后：`git add <file> && GIT_EDITOR=true git rebase --continue`。

## 4. 门禁验证：以「合并前后同数值」判新增

这些门禁**本就常红**（既有债务），退出码不是判据。**判据是 merge/rebase 前后逐项数值完全相同 ⇒ 本次 0 新增问题**：

```sh
python3 tools/asset_pipeline/verify_ledger_split.py    # 关注 failures=/missing=/extra=
python3 scripts/check_asset_runtime_naming.py           # 带版本资产/目录计数
python3 scripts/check_documentation_contracts.py        # JSON 输出，统计 issues 里本次相关项
```

- 文档门禁输出 JSON：解析后按今日日期/新增文件名过滤，确认 `0` 项与本次相关。
- 本机坑：**没有 `timeout` 命令**（`command not found`），别用它包裹长命令。
- 系统 `python3` 缺 `openpyxl` ⇒ 造垫片前置于 PATH（**写成独立普通文件，先 `ls -la` 确认不是符号链接**）：

```sh
#!/bin/sh
exec "<venv>/bin/python" "$@"
```

## 5. 推送落地判据：SHA 逐字相同

`git push` 退出码 0、甚至 `Uploading LFS objects: 100% … done` **都不等于推送成功**（长传后远端可能断连，LFS 上去了但 ref 没更新）。唯一判据：

```sh
git push origin <分支>
git fetch origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/<分支>)" ] && echo 落地
```

不符就原样重跑 `git push`（已传 LFS 不重传）。

## 6. 收尾

- 工作区应干净：`git status --porcelain -uall` 为空。
- 记忆/回退指针按仓库约定入库（可能需再补一次记忆提交 + 推送，同样按 §5 验落地）。
