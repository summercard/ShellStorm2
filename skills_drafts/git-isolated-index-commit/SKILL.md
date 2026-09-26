---
name: git-isolated-index-commit
description: 在不破坏既有暂存内容的前提下构造自定义提交 —— 当需要「提交工作区全部改动但排除某些路径」而本机 git 不支持 `:(exclude)` / `:!` pathspec magic 时使用。用 GIT_INDEX_FILE 建立隔离索引（复制真实索引 → 吸收工作区改动 → reset 掉要剔除的路径 → commit），提交后立刻 `git reset` 把真实索引对齐回 HEAD。适用于多 agent/多会话共用同一工作区、或需按自定义入/出集合出提交的场合。⚠️ 含一个必做的收尾步骤，漏掉会留下「批量删除」地雷。
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

# 3) 按需吸收工作区改动（二选一）
#    3a) 只以「真实暂存区」为基线（不吸收未暂存修改与未跟踪新文件）→ 跳过这步
#    3b) 吸收工作区全部改动（含未暂存 M 与未跟踪 ??）→ 全量吃下，随后再退回剔除集
git add -A

# 4) 把要剔除的路径从隔离索引里退回（index-only unstage）
git reset -q -- <剔除路径1> <剔除路径2> ...

# 5) 自校验：剩下多少、还有没有残留剔除项
git diff --cached --shortstat
git diff --cached --name-only | grep -cE '^(<剔除路径1>|<剔除路径2>)/' || true   # 必须为 0；⚠️ 见坑 11

# 6) 提交（信息建议落文件，避开 shell 引号/中文转义）
git commit -F .git/COMMIT_MSG.txt

# 7) 收尾：清掉隔离索引与消息文件
rm -f .git/alt_index .git/COMMIT_MSG.txt

# 8) 🔴 必须把真实索引对齐到新 HEAD（否则留「批量删除」地雷，见坑 14）
unset GIT_INDEX_FILE
git reset -q                          # index := HEAD_new；工作区一字节不动
git diff --cached --shortstat         # 必须为空

# 9) 增量自校验（别用 ls-tree 全树计数，见坑 5）
git diff-tree -r --name-only --no-commit-id <新提交sha> | grep -cE '^(<剔除路径>)/' || true   # 必须为 0
```

## 关键点与坑

1. **`GIT_INDEX_FILE` 每条命令都要重新 `export`** —— shell 状态在命令之间不保留（工作目录也不一定保留）。把「复制 + reset + 校验 + commit」写进同一条命令，或分多条但每次 `export`。
2. **路径用纯 ASCII 相对路径**：`GIT_INDEX_FILE=.git/alt_index`，别用绝对中文路径。
3. **`git reset -q -- <path>` 是 index-only**（缺省 `--mixed`），不动工作区文件。对被剔除的**新文件** = 退回未跟踪；对**已跟踪文件的改动** = 退回 HEAD 版本。
4. **别用 `git rm --cached -r <dir>` 做剔除** —— 若该目录里本来就有 HEAD 已跟踪的文件，会把它们从索引树删掉，**在提交里产生大批删除**。必须用 `git reset -- <dir>`。
5. **自校验分两层**：① `git diff --cached --name-only` 里剔除项计数为 0（本轮没进去）；② `git diff-tree -r --name-only --no-commit-id <sha>` 里剔除项计数为 0（本提交**增量**里没有）。⚠️ 别用 `git ls-tree` 全树计数来判断 —— 历史遗留存量会让计数非 0，看着像失败。
6. **提交后真实索引**会**落后新 HEAD 一个提交**：因为提交走的是隔离索引的副本，真实 `.git/index` 从未更新。
   按「被提交内容的形态」有**两种截然不同的表现**，都已实测：

   | 提交内容形态 | 提交后 `git status` / `--cached` | 误 `git commit` 后果 |
   |---|---|---|
   | 真实索引**原本就已 staged**（别的会话已 `git add` 过） | 索引内容恰好 == 新 HEAD，`git status` 看着**干净** | 无（这是唯一安全的情形） |
   | 内容**含未跟踪新增**（未 staged） | 新 HEAD 里有、索引里没有 ⇒ 报 **`D ` 暂存删除**；实测 `+3698 / −225353` | 🔴 **一次提交 2296 个删除**，文件仍在磁盘但被从版本库抹掉 |
   | 内容**全是已跟踪文件的修改**（未 staged） | 索引里是旧 blob ⇒ 报 **`M ` 暂存修改**，且 diff **恰好是本次提交的镜像反向**（提交 `+1018/−514` ⇒ 暂存区显示 `+514/−1018`） | 🔴 **静默把 38 个文件回退到旧版本**（比删除更隐蔽，diff 看着像正常改动） |

   🔴 **两种都必须 `unset GIT_INDEX_FILE && git reset -q` 把索引对齐回 HEAD 才能收工。**
   - `git reset`（mixed）**不动工作区任何文件**；且此时「被丢弃的暂存状态」只剩你剔除的那批临时文件 ——
     其余原本 staged 的内容都已进新 HEAD，**不丢东西**。这一步不是可选项。
7. **中文路径显示**：`git diff --cached --name-only` 默认给非 ASCII 路径加引号，用 `-c core.quotepath=false` 关掉更易读；`-z` + `tr '\0' '\n'` 则完全不转义（**统计时优先用 `-z`**）。
8. 提交前确认无 hook 干扰：`ls .git/hooks/ | grep -v '\.sample'` 为空即干净。
9. 若只想以 HEAD 为基线（不是以真实暂存区为基线），把第 1 步换成 `git read-tree HEAD`。
10. **优先用 `git add -A` 吃全量再 `git reset` 退回，而不是逐路径枚举要保留的路径** —— 枚举会漏掉新出现的目录（尤其工作区有几百个未跟踪文件时）。缺点是要先把剔除集也加进来再退掉，但那只是一次 `reset`，代价可接受。
11. **`git add -A` 可能很慢**：体积大时会逐文件哈希。实测 **370 MB / 2445 文件 ≈ 2 分 09 秒**。超过 ~100 MB 就放后台跑，别在前台等（会撞默认超时）。
12. **`grep -c` 零匹配返回退出码 1** —— 放在命令末尾会让整条命令看起来「失败」（工具报 `failed`），**实际是成功**。要么加 `|| true`，要么判成功看更早的哨兵输出（如 `ADD_DONE` / `RESET_DONE`）与统计行。
13. **推送体积同样要评估**：单文件 >50 MB 时 GitHub 只给警告、>100 MB 会**直接拒绝**。提交前先筛一遍：`git ls-files --others --exclude-standard -z | tr '\0' '\n' | while read -r f; do [ -f "$f" ] && s=$(stat -c %s "$f") && [ "$s" -gt 104857600 ] && echo "$s $f"; done`。
14. 🔴 **提交后必须 `git reset -q`（见坑 6）** —— 这是本方案唯一的真实危险点。判据：`unset GIT_INDEX_FILE` 后
    `git diff --cached --shortstat` **必须为空**。
    ⚠️ **别只看 deletions**：内容全为「已跟踪文件修改」时，暂存区显示的是 **insertions 为主的反向 diff**
    （提交 `+1018/−514` ⇒ 暂存区 `+514/−1018`），看着像正常改动、实为回退。
    **唯一可靠判据 = `--cached` 完全为空**，非空就别把这个工作区交给别人用。
