---
name: git-isolated-index-commit
description: 在不触碰既有暂存区的前提下构造自定义提交 —— 当需要「提交工作区全部改动但排除某些路径」而本机 git 不支持 `:(exclude)` / `:!` pathspec magic 时使用。用 GIT_INDEX_FILE 建立隔离索引（复制真实索引 → reset 掉要剔除的路径 → commit），提交完真实索引一字节不动。适用于多 agent/多会话共用同一工作区、或需按自定义入/出集合出提交的场合。
agent_created: true
---

# git 隔离索引提交（GIT_INDEX_FILE）

## 何时用

- 需要**提交全部改动但排除某些路径**（临时文件、运行时产物、探针脚本、缓存）。
- 试过 `git commit -- . ':!tmp'` 或 `':(exclude)tmp'` 报：

  ```
  fatal: Unimplemented pathspec magic '_' in ':!_scratch'
  ```

  ⇒ 该 git 构建**不支持 exclude pathspec magic**，排除式提交不可用。
- 工作区里**已有别的会话/agent 精心 `git add` 好的暂存区**，你不能破坏它，但仍要出一个自己的提交。
- 需要「以真实暂存区为基线、只挑一部分路径进去」的提交。

## 不要用

- 单纯提交已有暂存区 → 直接 `git commit`。
- 只想 unstage 几个文件、且不介意动真实暂存区 → `git reset -- <path>`。
- 需要在一个工作区里长期共存多份互不干扰的索引 → 用 `git worktree`。

## 标准流程

```bash
cd <repo>

# 0) 记录基线：真实索引指纹（提交后必须与之一致）
sha256sum .git/index

# 1) 以真实索引为基线复制隔离索引（纯 ASCII 相对路径，避免中文路径坑）
rm -f .git/alt_index
cp .git/index .git/alt_index

# 2) 让后续所有 git 命令作用在隔离索引上
export GIT_INDEX_FILE=.git/alt_index

# 3) 把要剔除的路径从隔离索引里退回（index-only unstage）
git reset -q -- <剔除路径1> <剔除路径2> ...

# 4) 自校验：剩下多少、还有没有残留剔除项
git diff --cached --shortstat
git diff --cached --name-only | grep -cE '^(<剔除路径1>|<剔除路径2>)/'   # 必须为 0

# 5) 提交（信息建议落文件，避开 shell 引号/中文转义）
git commit -F .git/COMMIT_MSG.txt

# 6) 收尾：清掉隔离索引与消息文件，核对真实索引未被动过
rm -f .git/alt_index .git/COMMIT_MSG.txt
sha256sum .git/index
# 增量自校验（别用 ls-tree 全树计数，见坑 5）
git diff-tree -r --name-only --no-commit-id <新提交sha> | grep -cE '^(<剔除路径>)/'   # 必须为 0
```

## 关键点与坑

1. **`GIT_INDEX_FILE` 每条命令都要重新 `export`** —— shell 状态在命令之间不保留（工作目录也不一定保留）。把「复制 + reset + 校验 + commit」写进同一条命令，或分多条但每次 `export`。
2. **路径用纯 ASCII 相对路径**：`GIT_INDEX_FILE=.git/alt_index`，别用绝对中文路径。
3. **`git reset -q -- <path>` 是 index-only**（缺省 `--mixed`），不动工作区文件。对被剔除的**新文件** = 退回未跟踪；对**已跟踪文件的改动** = 退回 HEAD 版本。
4. **别用 `git rm --cached -r <dir>` 做剔除** —— 若该目录里本来就有 HEAD 已跟踪的文件，会把它们从索引树删掉，**在提交里产生大批删除**。必须用 `git reset -- <dir>`。
5. **自校验分两层**：① `git diff --cached --name-only` 里剔除项计数为 0（本轮没进去）；② `git diff-tree -r --name-only --no-commit-id <sha>` 里剔除项计数为 0（本提交**增量**里没有）。⚠️ 别用 `git ls-tree` 全树计数来判断 —— 历史遗留存量会让计数非 0，看着像失败。
6. **提交后真实索引会「看起来变干净」**：新 HEAD 的树内容与真实索引一致 ⇒ `git status` 变 clean。这是正常的，不是你把别人的 staging 弄丢了。
7. **中文路径显示**：`git diff --cached --name-only` 默认给非 ASCII 路径加引号，用 `-c core.quotepath=false` 关掉更易读；`-z` + `tr '\0' '\n'` 则完全不转义（**统计时优先用 `-z`**）。
8. 提交前确认无 hook 干扰：`ls .git/hooks/ | grep -v '\.sample'` 为空即干净。
9. 若只想以 HEAD 为基线（不是以真实暂存区为基线），把第 1 步换成 `git read-tree HEAD`。
