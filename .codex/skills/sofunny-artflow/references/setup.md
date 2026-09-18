# 接入与安装指南

## 前置条件

- Node.js ≥ 18（`node --version` 确认；零依赖，无需 npm install）
- 能访问平台入口：公网 `https://artflow.hnfunny.com`（默认）或内网 `http://10.20.3.93:33500`
- 飞书账号（`login --feishu` 设备码登录，与网页登录同账号；唯一登录方式）

## 获取本仓库

```bash
git clone git@git.sofunny.io:skill-libs/sofunny-artflow.git
# 或 https: git clone https://git.sofunny.io/skill-libs/sofunny-artflow.git
cd sofunny-artflow
```

## 安装

```bash
bash scripts/setup.sh
```

脚本行为：校验 Node 版本 → 复制 `scripts/` 下的 CLI 文件到 `~/.artflow-cli-bin/`。完成后入口为 `node ~/.artflow-cli-bin/artflow.mjs <command>`。

## 首次登录

凭据只有一种获取方式：飞书设备码登录（与网页飞书登录同账号）。

```bash
node ${SKILL_DIR}/scripts/artflow.mjs login --feishu
```

stderr 打印授权链接（自动尝试打开浏览器），在飞书确认后 JWT 自动保存到 `~/.artflow-cli/config.json`（0600，30 天有效），过期重新 login 即可。首次飞书登录者自动成为平台超管。

CLI 权限与网页端登录后完全一致：取消/重跑/恢复仅限本人任务（超管例外）、删除仅限超管；详见 SKILL.md「任务权限」。

```bash
node ${SKILL_DIR}/scripts/artflow.mjs doctor   # 验证，退出码 0 即就绪
```

## 推荐的 Agent 工作流配置

把以下内容加入 agent 的 AGENTS.md / 系统提示：

```
你可以用 artflow-cli 生成视频：
- 入口：node ~/.artflow-cli-bin/artflow.mjs（或 ${SKILL_DIR}/scripts/artflow.mjs）
- 凭据：本机 login --feishu 已保存（未登录时引导用户先登录）
- 固定流程：doctor 自检 → types 查参数 →（复杂提交先 --dry-run）→ submit/batch → wait → download
- stdout 恰好一个 JSON（解析它），stderr 是进度；退出码 1=调用问题（读 stderr），2=任务失败（读 stdout 的 jobs[].error）
- GPU 任务串行排队（queue_position 显示排队位），批量提交不会加速执行
- 提交成功后中断不要重提，用 status <jobId> 查真实状态
```
