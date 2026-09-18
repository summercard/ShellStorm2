# ArtFlow CLI 命令与参数参考

CLI 入口：`node ${SKILL_DIR}/scripts/artflow.mjs <command> [flags]`（零依赖 Node ≥18）。

全局 flags：`--base-url`（默认 `https://artflow.hnfunny.com`）、`--timeout-per-request 60s`、`--quiet`。

环境变量：`ARTFLOW_CLI_BASE_URL` / `ARTFLOW_CLI_CONFIG`（默认 `~/.artflow-cli/config.json`，0600）。凭据来自 `login --feishu` 保存的本机配置，无 token 环境变量。

输出契约：stdout 恰好一个 JSON（batch `--stream` 时 NDJSON）；stderr 进度与错误 JSON `{"error":{"code","message","hint"}}`。

## 任务类型

| 类型 | 说明 | 必填 | 特点 |
|---|---|---|---|
| `minimax_h3` | H3 视频（本地 GPU） | `--prompt` | 480p 快/720p 高清；duration 5/8/10/15s |
| `ltx_video` | LTX 视频（本地 GPU） | `--prompt` | duration 3/5/8s；分辨率 768x448 等 |

其他平台类型（seedance/happy_house 等）用 `submit --json` 原始模式，参数见平台文档。

## submit 友好模式参数

### minimax_h3

| flag | 取值 | 默认 |
|---|---|---|
| `--prompt` | 文本 | 必填 |
| `--mode` | `keyframe` / `reference` | keyframe |
| `--output-kind` | `video` / `audio` | video |
| `--first-frame` / `--last-frame` | URL / `@本地路径` / 服务器路径 | 空 |
| `--ref-image`（可重复 ×9）/ `--ref-video`（×3）/ `--ref-audio`（×3） | 同上 | 空 |
| `--resolution` | `480p` / `720p` | 480p |
| `--ratio` | `16:9` `9:16` `1:1` `4:3` `3:4` | 16:9 |
| `--duration` | 5/8/10/15 | 5 |
| `--seed` | 数字（-1 随机） | -1 |
| `--shift-video` / `--shift-audio` | 数字 | 12 / 3 |
| 音频模式 | `--audio-format mp3/flac/opus`；`--remove-bgm=false` / `--clean-audio=false` 关闭默认开关 | mp3；默认开 |

### ltx_video

`--prompt`（必填）、`--negative-prompt`（默认内置画质负面词）、`--first-frame` / `--last-frame` / `--reference-audio`、`--resolution`（768x448/960x544/448x768/768x768，默认 768x448）、`--duration`（3/5/8，默认 5）、`--fps`（默认 24）、`--seed`、`--cfg`（默认 1）、`--image-strength`（默认 0.7，first-frame-strength 默认跟随）、`--last-frame-strength`、`--reference-audio-guidance`、`--two-stage-upscale`、`--generate-audio=false` 关闭。

### 通用

- `--dry-run`：只打印请求体不提交（不消耗凭据）。
- `--node-id`：默认 `codex-cli`（平台运营区分来源）。
- 原始模式：`--json '<完整body>'` / `--json-file f.json` / `--json-file -`（stdin），整包透传，素材字段支持 `@路径` 自动上传。

## 任务管理

所有任务命令都要求已登录（`login --feishu`）。权限与网页端一致：**取消/重跑/恢复仅限本人任务（超管例外），删除仅限超管**。

```bash
node ${SKILL_DIR}/scripts/artflow.mjs status <jobId...>          # 查询；404 → status:"not_found"
node ${SKILL_DIR}/scripts/artflow.mjs list --type minimax_h3 --status succeeded --limit 20 --mine
node ${SKILL_DIR}/scripts/artflow.mjs wait <jobId...> --timeout 4h --poll-interval 5s [--download ./out]
node ${SKILL_DIR}/scripts/artflow.mjs cancel <jobId>             # 取消排队/运行中（仅本人/超管）
node ${SKILL_DIR}/scripts/artflow.mjs rerun <jobId>              # 克隆原请求重提（仅本人/超管）
node ${SKILL_DIR}/scripts/artflow.mjs recover <jobId>            # 超时/服务重启后救回（仅本人/超管）
node ${SKILL_DIR}/scripts/artflow.mjs download <jobId...> --out-dir ./out [--no-clobber]
node ${SKILL_DIR}/scripts/artflow.mjs delete <jobId>             # 删除任务（仅超管，不可恢复）
```

wait 退出码：全成功 0；有 failed/超时 pending 2。`--mine` 服务端按归属过滤（旧服务端回退本地过滤）。

## batch 批量

```bash
node ${SKILL_DIR}/scripts/artflow.mjs batch jobs.jsonl --wait --timeout 4h --concurrency 2 --out results.jsonl [--stream] [--fail-fast]
```

jobs.jsonl 每行一个任务（submit 原始模式形状，`#` 注释行忽略）：

```jsonl
{"type":"minimax_h3","payload":{"prompt":"镜头一：日出","resolution":"720p","duration":8}}
{"type":"minimax_h3","payload":{"prompt":"镜头二：日落","first_frame_url":"@./end_of_shot1.png"}}
{"type":"ltx_video","payload":{"prompt":"镜头三：空镜转场","duration":5}}
```

- 提交阶段单行失败不中止（`--fail-fast` 反转）；`--concurrency` 只影响提交速度（GPU 串行执行）。
- `--out results.jsonl` 增量追加（submitted / submit_failed / done 事件），CLI 被杀不丢已完成数据。
- 退出码：全成功 0；部分失败或超时 pending 2；零提交成功 1。

## 素材上传

```bash
node ${SKILL_DIR}/scripts/artflow.mjs upload <file...> [--kind image|video|audio]
```

- 上限：文件 ≤180MB（>150MB 警告）；更大素材改用公网 URL 直接作为参数。
- 上传返回 `{url: "/uploaded-media/..."}`，可填入 payload 素材字段复用。

## 凭据管理

```bash
node ${SKILL_DIR}/scripts/artflow.mjs login --feishu   # 飞书设备码登录（与网页同账号，唯一登录方式）
node ${SKILL_DIR}/scripts/artflow.mjs whoami           # 当前身份 + JWT 到期时间
node ${SKILL_DIR}/scripts/artflow.mjs logout           # 清除本机凭据
node ${SKILL_DIR}/scripts/artflow.mjs doctor           # 连通/鉴权/注册表自检
```
