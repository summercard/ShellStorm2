---
name: sofunny-artflow
version: 2.1.0
description: 接入 Sofunny ArtFlow 视频生成平台（MiniMax-H3 / LTX），主打首尾帧与全能参考模式视频生成，支持批量提交、GPU 队列轮询与成品下载。适用于平台账号归属、批量 jobs.jsonl 场景。
---

# sofunny-artflow

## 何时使用

- 用户要生成视频，且要求任务归属到 ArtFlow 平台账号（网页 /minimax 与 /library 可见、可点赞评论）
- 首尾帧驱动的可控视频生成（`--first-frame` / `--last-frame`）
- 全能参考模式：多参考图/视频/音频驱动的视频生成（`--mode reference`）
- 用户要**批量**生成（一个清单一次跑完，如分镜多镜头）
- 需要走平台本地 GPU 池（MiniMax H3、LTX）

## 安装与凭据

本仓库即 skill（`SKILL.md` + `scripts/` + `references/`，零依赖 Node ≥18）。

运行入口统一写为 `node ${SKILL_DIR}/scripts/artflow.mjs`（下同）：`${SKILL_DIR}` 指本 skill 的安装目录——已安装到 Agent 时为 skills 目录（如 `~/.claude/skills/sofunny-artflow`），仓库内直接使用时为仓库根目录。也可 `bash ${SKILL_DIR}/scripts/setup.sh` 安装到机器级路径 `~/.artflow-cli-bin/`。详细接入步骤见 [references/setup.md](references/setup.md)。

凭据只有一种获取方式：`login --feishu` 飞书设备码登录——stderr 打印授权链接，用户在飞书确认后 JWT 自动保存到本机 `~/.artflow-cli/config.json`（30 天有效，过期重新 login），与网页飞书登录同账号。

默认入口 `https://artflow.hnfunny.com`；内网可用 `ARTFLOW_CLI_BASE_URL=http://10.20.3.93:33500` 更快。

## 快速用法

```bash
# 提交一条 H3 视频（提交前可加 --dry-run 只看请求体）
node ${SKILL_DIR}/scripts/artflow.mjs submit --type minimax_h3 --prompt "一只橘猫跳舞，镜头缓慢推近" \
  --resolution 720p --duration 8

# 首尾帧驱动（本地图片自动上传）+ 等待完成 + 下载
node ${SKILL_DIR}/scripts/artflow.mjs submit --type minimax_h3 --prompt "画面动起来" --first-frame ./first.png
node ${SKILL_DIR}/scripts/artflow.mjs wait <jobId> --timeout 30m --download ./out

# 批量（jobs.jsonl 每行一个任务，--wait 等全部完成）
node ${SKILL_DIR}/scripts/artflow.mjs batch jobs.jsonl --wait --out results.jsonl
```

## 参数决策

- **类型**：视频用 `minimax_h3`（480p 更快/720p 高清）；轻量短片用 `ltx_video`（分辨率/时长档位更细）。
- **首尾帧模式**：`--first-frame` / `--last-frame` 控制画面首尾（keyframe 模式默认）。
- **全能参考模式**：`--mode reference` 配 `--ref-image×9 --ref-video×3 --ref-audio×3`。
- **素材值**：http URL、`@本地路径`（自动上传）、`/uploaded-media/...` 服务器路径。
- **不确定参数时**：先跑 `node ${SKILL_DIR}/scripts/artflow.mjs types <type>` 查枚举与默认值。

完整命令、参数表与 jobs.jsonl 格式见 [references/cli-commands.md](references/cli-commands.md)。

## 工作流

1. `doctor` 自检（连通/鉴权），退出码非 0 先解决环境问题（未登录先 `login --feishu`）。
2. `types <type>` 确认参数；复杂提交先 `--dry-run` 看请求体。
3. `submit`（单个）或 `batch`（批量，结果落 `--out` 防中断丢数据）。
4. `wait`（默认超时 4h）。本地 GPU 每端点串行排队，`queue_position` 显示排队位，批量提交不会加速执行。
5. `download` 或 wait `--download` 取成品，把 `media_url`/本地路径回报给用户。
6. 任务失败：读 stdout 里 `jobs[].error`，改 prompt 重提或 `rerun <jobId>`。

## 错误处理

- 退出码约定：`0` 成功；`1` 调用/凭据/网络问题（读 stderr JSON）；`2` 任务本身失败（读 stdout 的 `jobs[].error`）。
- `AUTH` / `AUTH_EXPIRED`：未登录或 JWT 过期（30 天）→ 重新 `login --feishu`。
- `VALIDATION`：本地参数校验失败（如 reference 模式没给素材）→ 按 message 修 flags。
- 任务 failed 且 error 提到超时/服务重启 → 先 `recover <jobId>` 尝试救回，救不回再 rerun。
- `status` 返回 not_found：任务超过 300 条保留被清理，成品已下载的忽略。

更多排查（429 限流、排队慢、上传超限、上游类型 400/502）见 [references/troubleshooting.md](references/troubleshooting.md)。

## 任务权限

权限与网页端登录后完全一致。**会话开始先跑 `whoami` 明确当前身份（username / isSuperAdmin）**，再按矩阵操作：

| 操作 | 普通用户 | 超级管理员 |
|---|---|---|
| 查看任务列表 / 单个任务 / 下载成品 | 本人登录后可见全部（共享工作台） | 同左 |
| `cancel` / `rerun` / `recover` | 仅自己的任务 | 任意任务 |
| `delete` | 无权 | 任意任务 |
| `submit` / `batch` / `upload` | 可以（消耗本人账号配额） | 同左 |

AI 行为准则：

- **操作前核对归属**：对目标任务先 `status <jobId>`（或 `list`）看 `owner_username`，非本人且非超管时**直接告知用户无权限，禁止尝试调用**——服务端会 403。
- **403 不重试**：收到「仅任务本人或超级管理员可…」说明权限不足，如实转述；需要操作时让任务 owner 本人执行，或请超管处理。
- **401 重新登录**：所有任务端点（含查询/等待）都要求登录，凭据过期重新 `login --feishu`。
- `list --mine` 只看自己的任务（服务端按归属过滤）。

## 注意事项

- **禁止盲目重提**：提交成功后若客户端中断，用 `status <jobId>` 查真实状态再决定；重提会重复占 GPU 排队。
- **写操作需用户确认**：`delete`（仅超管）与 `cancel`（不可逆中断 GPU 任务）执行前与用户确认；复杂提交先 `--dry-run` 看请求体。
- **任务归属平台账号**：提交者的登录身份就是 owner，成品出现在平台 `/library`。
- **GPU 串行执行**：N 个任务 ≈ N × 单任务时长（H3 720p 约 5-20 分钟/条），批量提交不会加速；按 `queue_position` 如实给用户预估时间。
- **成品及时下载**：jobs 列表只保留最近 120 条、任务记录 300 条，超期被清理后无法找回。
