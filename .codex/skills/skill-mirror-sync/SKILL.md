---
name: skill-mirror-sync
description: 把 ~/.workbuddy/skills（唯一正本）全量镜像到项目内 skills_drafts、项目 .codex/skills、用户级 ~/.codex/skills 三处副本，并校验逐文件 sha256 一致与 CRLF 行尾纯度。用于「skill 改了要同步到各处 / 四副本是否一致 / 副本缺哪个 skill / 行尾被谁改乱了」这类问题。不用于 skill 内容本身的编写与评审。
agent_created: true
---

# skill 四副本镜像同步

## 唯一正本

`~/.workbuddy/skills/`（下称 A）。其余三处都是副本 —— **任何内容改动只在 A 做，然后向下同步**。

| 代号 | 路径 | 性质 |
|---|---|---|
| A | `C://Users//zhuangmenghong//.workbuddy//skills` | **正本 / 唯一真源** |
| B | `I://工作项目//shellstrom2//ShellStorm2//skills_drafts` | 项目内草稿区 |
| C | `I://工作项目//shellstrom2//ShellStorm2//.codex//skills` | 项目 Codex 技能区 |
| D | `C://Users//zhuangmenghong//.codex//skills` | 用户级 Codex 技能区 |

## 用法

```bash
python scripts/sync_skill_mirrors.py --sync    # 以 A 为准全量重建 B/C/D
python scripts/sync_skill_mirrors.py --check   # 只读校验
```

`--sync` 对 A 拥有的每个 skill：先 `rmtree` 目标目录再整树复制，**杜绝残留旧文件**；排除 `__pycache__`。

⚠️ **不要把临时文件写进 skill 目录（`~/.workbuddy/skills/<name>/`）。** 那里是正本，
任何临时日志都会被当成 skill 内容同步到 B/C/D —— 实测把 `_sync.log` 重定向进
`skill-mirror-sync/` 后，`--check` 立刻报 `diff=['skill-mirror-sync/_sync.log', ...]`
外加 `A has 1 non-CRLF file(s)`。临时输出一律落在 skill 目录**之外**（如 `%TEMP%` 或项目
`_scratch/`）；若已写进去，从 A 删掉再跑一次 `--sync` 即可用全量重建清掉副本里的残留。

## 判据

- 每个 skill 的全部文件 sha256 与 A 逐字节相同
- 行尾全为 CRLF（无 lone LF、无 bare CR）
- 退出码 0 = 一致；1 = 有差异

## 新增 skill

1. 内容写在 A 里（`~/.workbuddy/skills/<name>/`）。目录名必须与 SKILL.md 的 `name:` 完全一致。
2. **先过行尾关再同步**：`--check` 要求 A 里**每个文件**都是 CRLF —— 包括 `assets/*.json`、`references/*.md`、`scripts/*.py`。用别的工具生成的模板常是 LF，不转就 `SKILL_MIRROR_CHECK_FAIL ... A has N non-CRLF file(s)`。
3. 跑 `--sync`，再跑 `--check`。`--sync` 会 `rmtree` 重建，所以新 skill 的副本一定干净。

若 skill 原本只存在于**项目级** `{workspace}/.workbuddy/skills/`，那处不在这四副本里、也不由本脚本管理 —— 要推广到各处，必须先把目录复制进 A，再 `--sync`。

## 改名 skill 的坑

`--sync` 只按「A 当前拥有的名字」写入，**从不删副本里的多余目录**；`--check` 也只遍历 A 的名字，**不会报告副本里多出来的旧目录**。所以给 skill 改名（例如加 `00-` 前缀）后：

- A 里的旧名目录要自己删；
- B/C/D 里若曾同步过旧名，旧名目录会**静默留存**，改完必须人工核对目录清单，别只看 `--check` 的 OK。

改名后要同步改的位置：目录名、SKILL.md 的 `name:`、以及所有引用该 skill 名字的地方（其他 skill 的路由表、项目文档、交付 zip）。

## 顺便发现：副本落后于正本

`--sync` 是全量重建，会把**所有** skill 的最新内容带过去，包括与本次任务无关的。若某副本此前落后，事后 `git diff` 会看到它的改动 —— 属正常补齐，不是误改。可先确认是纯增量：

```bash
git diff --unified=0 -- <copy>/<skill>/SKILL.md | grep -E '^[-+][^-+]' | awk '{substr($0,1,1)=="+"?a++:d++} END{print "added="a" removed="d}'
```

`removed=0` 说明只补了内容、没丢东西。

## 边界

- **绝不反向**：不从副本同步回 A。副本行尾被污染时，修副本、不修 A。
- **不删副本里 A 没有的 skill**：D 中另有若干其他项目的 skill（`match3-ui-art-qa`、`wechat-minigame-submission`、`sausage-character-asset-maker` 等），不属于本套，保留不动。
- A 根部的 `.disable_to_model_invocation_migration.json` / `.model_invocation_to_override_migration.json` 是 WorkBuddy 引擎标记文件，**不是 skill，不参与同步**。
- 副本本来就是子集，**不要假设到处都有某个 skill** —— 这正是本 skill 存在的原因。
