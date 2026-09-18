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

## 判据

- 每个 skill 的全部文件 sha256 与 A 逐字节相同
- 行尾全为 CRLF（无 lone LF、无 bare CR）
- 退出码 0 = 一致；1 = 有差异

## 边界

- **绝不反向**：不从副本同步回 A。副本行尾被污染时，修副本、不修 A。
- **不删副本里 A 没有的 skill**：D 中另有若干其他项目的 skill（`match3-ui-art-qa`、`wechat-minigame-submission`、`sausage-character-asset-maker` 等），不属于本套，保留不动。
- A 根部的 `.disable_to_model_invocation_migration.json` / `.model_invocation_to_override_migration.json` 是 WorkBuddy 引擎标记文件，**不是 skill，不参与同步**。
- 副本本来就是子集，**不要假设到处都有某个 skill** —— 这正是本 skill 存在的原因。
