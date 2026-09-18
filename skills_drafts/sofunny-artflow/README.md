# sofunny-artflow

接入 **Sofunny ArtFlow 视频生成平台**的 Skill + CLI 套件：让 Claude Code / Codex 等 AI Agent 批量提交视频生成任务、轮询状态、下载成品。主打首尾帧与全能参考模式的可控视频生成。任务归属平台账号（网页 `/minimax` 历史与 `/library` 素材库可见、可点赞评论）。

- **零依赖**：CLI 为纯 Node ESM（≥18），无 npm install
- **机器友好**：stdout 恰好一个 JSON；退出码 0/1/2 区分「成功 / 调用问题 / 任务失败」
- **飞书登录**：设备码登录与网页同账号，JWT 自动保存本机（30 天有效）

这是一个通用 Skill（同时适用于 Claude Code、Codex 等 Agent），由 `SKILL.md` 描述触发时机与工作流，由 `scripts/artflow.mjs` 提供可执行入口。

> 本文件仅供人类快速了解；AI 安装 / 使用请以 [SKILL.md](SKILL.md) 为唯一权威定义。

## 能力一览

| 能力 | 命令 |
|---|---|
| H3 视频生成（本地 GPU） | `submit --type minimax_h3` |
| 首尾帧驱动视频生成 | `--first-frame` / `--last-frame`（本地文件自动上传） |
| 全能参考模式（参考图/视频/音频） | `--mode reference` + `--ref-image` 等 |
| LTX 轻量视频 | `submit --type ltx_video` |
| 批量任务（jobs.jsonl） | `batch jobs.jsonl --wait --out results.jsonl` |
| 等待完成并下载 | `wait <jobId> --download ./out` |
| 飞书登录（与网页同账号） | `login --feishu` |

## 安装

推荐使用 `npx skills add` 安装，可自主选择目标 Agent（Claude Code / Codex 等）的 skills 路径（`test/` 等开发产物已通过 `.skillignore` 排除，不会装进 skills 目录）：

```bash
npx skills add https://git.sofunny.io/skill-libs/sofunny-artflow.git
```

安装后入口为 `${SKILL_DIR}/scripts/artflow.mjs`（`${SKILL_DIR}` 指 skill 安装目录）。依赖 Node.js ≥18（零依赖，无需 npm install）。

## 更新

```bash
npx skills update sofunny-artflow
```

或批量更新所有已安装 skill：`npx skills update`（被 pin 固定版本的 skill 会跳过）。更新后需重启 Agent。

## 快速开始

```bash
git clone git@git.sofunny.io:skill-libs/sofunny-artflow.git
cd sofunny-artflow

# 1. 飞书登录（stderr 打印授权链接，在飞书确认后 JWT 自动保存本机）
node scripts/artflow.mjs login --feishu

# 2. 安装 CLI 到机器级路径
bash scripts/setup.sh

# 3. 生成第一条视频
node ${SKILL_DIR}/scripts/artflow.mjs submit --type minimax_h3 \
  --prompt "一只橘猫跳舞，镜头缓慢推近" --resolution 720p
node ${SKILL_DIR}/scripts/artflow.mjs wait <jobId> --download ./out
```

## 仓库结构

```
sofunny-artflow/
├── SKILL.md            # Skill 入口：触发时机、参数决策、工作流、错误处理（权威）
├── scripts/            # CLI 本体（零依赖 Node ESM）+ 安装脚本
│   └── artflow.mjs     # 入口：node ${SKILL_DIR}/scripts/artflow.mjs <command>
├── test/               # 单元测试（仅仓库内，安装时被 .skillignore 排除）
└── references/         # 命令参考 / 接入指南 / 故障排查
```

## 测试

```bash
node --test test/*.test.mjs   # 60 个用例（mock server，无需真实平台）
```

## 文档

- 命令与参数参考：[references/cli-commands.md](references/cli-commands.md)
- 接入与安装：[references/setup.md](references/setup.md)
- 故障排查：[references/troubleshooting.md](references/troubleshooting.md)

## 上游与维护

平台服务端在内部仓库 `sofunny-artflow`（本仓库只含对外分发的 skill 与 CLI）。CLI 行为变更时同步更新 SKILL.md 与 references。
