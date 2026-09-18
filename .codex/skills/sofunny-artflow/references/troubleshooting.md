# 故障排查

## 错误码速查

| 错误码 | 含义 | 处置 |
|---|---|---|
| `USAGE` | 参数错误 | 读 stderr message 修正命令 |
| `AUTH` / `AUTH_EXPIRED` | 未登录 / JWT 过期 | 重新 `login --feishu`（JWT 30 天有效） |
| `NETWORK` | 入口不可达 | 先 `doctor`；检查网络或换 `--base-url` |
| `HTTP`（429） | 公网 nginx 限流 | CLI 已自动退避重试；持续 429 把 batch `--concurrency` 降为 1 |
| `VALIDATION` | 本地校验失败 | 按 message 修 flags（如 reference 模式需至少一个参考素材） |
| `UPLOAD_TOO_LARGE` | 素材 >180MB | 改用公网 URL |
| `JOB_EVICTED` / status not_found | 任务超过 300 条被清理 | 成品已下载的忽略；否则无法找回 |
| exit 2 + `jobs[].error` | 任务终态失败 | 读 error；改 prompt 重提或 `rerun` |

## 常见问题

### 任务一直 queued / 排队很慢

本地 GPU 每端点同时只跑 1 条（H3/LTX 按角色路由到不同端点）。`status` 看 `queue_position`；`list` 看整体队列。批量 N 条 ≈ N × 单条时长（H3 720p 约 5-20 分钟/条），给用户如实预估。**不要**为了快而并发重提。

### 任务 failed 提示超时

服务端单任务上限 3 小时。先 `recover <jobId>` 重查一次（上游可能已完成只是没落盘）；救不回再 `rerun`。

### canvas-lab 重启后任务 failed

上游型任务的凭据在内存中丢失 → `recover <jobId>`。

### login --feishu 报"飞书登录未配置"

后端 `.env` 缺 `FEISHU_APP_ID/SECRET/REDIRECT_URI` 三件套（与网页飞书登录同套配置）。找管理员确认。

### login --feishu 一直等待

stderr 会打印授权链接与用户码；用户需在有效期内（默认 600s）在飞书完成确认。超时/拒绝/过期 CLI 会明确报错退出，重跑即可。

### 上传很慢或失败

内网走 `http://10.20.3.93:33500` 直连更快（`ARTFLOW_CLI_BASE_URL`）。超大素材（>180MB）改公网 URL 直接作为素材参数。上传失败若与体积相关，注意服务端限制链：canvas-lab 220MB JSON body / nginx 250m。

### 上游类型任务（seedance/happy_house 等）报 400/502

`submit --json` 原始模式可提交上游类型，但要求：该账号已在平台自填 API key，且依赖 workbench（127.0.0.1:33111）在线。当前部署未保证两者，失败形态为 400/502。本地 GPU 类型（h3/ltx）不受影响。

### 401 与凭据语义

- JWT（`login --feishu` 签发）30 天过期 → 重新 `login --feishu`。
- 所有 v2 任务端点（含查询/等待轮询）都要求登录：等待中凭据过期会导致轮询 401，重新 login 后用 `status` 恢复继续等。

### 403 与权限边界

- 取消/重跑/恢复仅限**本人任务**（超管例外），删除仅限**超管**——与网页端权限一致。
- 收到 403 说明当前身份无权操作该任务：先 `whoami` 确认身份与角色，不要重试；确需操作时让任务 owner 本人执行或找超管。

## 平台侧信息

- 任务保留：jobs.json 最近 300 条、列表接口 120 条；重要成品及时 download。
- 任务归属：提交者的登录身份即 owner，成品出现在平台 `/library`（按 owner 过滤）。
- node_id 默认 `codex-cli`：平台运营侧区分 CLI 来源；`--node-id` 可自定义。
