# sofunny-image

通过 **Sofunny-AIKey** 平台按模型注册表自动选择 Gemini 原生、OpenAI Images 兼容或 Doubao Seedream 专用 JSON 协议，支持 GPT Image、Qwen Image、Seedream 文生图 / 参考图编辑 / 组图 / 图层拆分，并自动保存到本地。

这是一个通用 Skill（适用于 Claude Code、Codex 等 Agent），由 `SKILL.md` 描述触发时机与工作流，由 `scripts/sofunny-image.js` 提供可执行入口。

> 本文件仅供人类快速了解；AI 安装 / 使用请以 [SKILL.md](SKILL.md) 为唯一权威定义。

## 仓库结构

```
sofunny-image/
├── SKILL.md              # Skill 描述：何时使用、配置、工作流、错误处理（权威）
├── README.md             # 本文件（人类概述）
├── scripts/
│   └── sofunny-image.js  # 可执行入口：生成/编辑图片并保存本地
└── agents/
    └── openai.yaml       # Agent 描述元数据（display_name / default_prompt）
```

## 安装

推荐使用 `npx skills add` 安装，可自主选择目标 Agent（Claude Code / Codex 等）的 skills 路径：

```bash
npx skills add https://git.sofunny.io/skill-libs/sofunny-image.git
```

入口脚本：`<安装目录>/scripts/sofunny-image.js`（下文示例以 `${SKILL_DIR}` 代指该安装目录）。

依赖：Node.js 18+（内置 `fetch`）。

## 更新

```bash
npx skills update sofunny-image
```

或批量更新所有已安装 skill：`npx skills update`（被 pin 固定版本的 skill 会跳过）。更新后需重启 Agent。

## 配置

脚本按「命令行参数 > 进程环境变量 > `~/.sofunny/aikey-config.json` > 旧版 `~/.sofunny-image.env` > 内置默认值」的优先级读取配置（高优先级覆盖低优先级）。

推荐创建共享配置文件 `~/.sofunny/aikey-config.json`：

```json
{
  "default": {
    "base_url": "https://llm-api-proxy.hnfunny.com",
    "api_key": "你的服务令牌"
  },
  "sofunny-image": {
    "model": "gpt-image-2"
  }
}
```

`sofunny-image` 段的 `base_url` / `api_key` 会逐字段覆盖 `default`；`model` 只从 `sofunny-image` 段读取。旧版 `~/.sofunny-image.env` 仍兼容读取，但不作为新配置指导。支持的模型：`gpt-image-2`、`gpt-image-2.5-flare`、`gpt-image-2.5-sunburst`、`qwen-image-3.0-pro`（OpenAI Images 兼容）、`doubao-seedream-5-0-pro`、`doubao-seedream-5-0-flash`、`doubao-seedream-5-0-lite`（Seedream 专用 JSON）、`gemini-3.1-flash-lite-image`、`gemini-3.1-flash-image`、`gemini-3-pro-image`（Gemini 原生）。

## 参数速查

| 参数 | 说明 | 默认 |
|------|------|------|
| `--prompt` | 必填，图片生成或编辑指令 | — |
| `--input` | 可重复，参考图本地路径 | — |
| `--output` | 输出文件路径，未指定则写入当前工作目录 | 当前目录 |
| `--size` | OpenAI 图片尺寸（`1024x1024` / `1024x1536` / `1536x1024` / `auto`），未传时不发送 | — |
| `--resolution` | 统一图片分辨率（`1K` / `2K` / `4K`），由中转按渠道转换 | — |
| `--quality` | OpenAI 图片质量（`low` / `medium` / `high` / `auto`），未传时不发送 | — |
| `--background` | OpenAI 背景参数（`transparent` / `opaque` / `auto`） | — |
| `--output-format` | OpenAI 输出格式（`png` / `webp` / `jpeg`），未传时不发送 | — |
| `--output-compression` | OpenAI 输出压缩率，未传时不发送 | — |
| `--aspect-ratio` | 图片比例 | `16:9` |
| `--image-size` | Gemini/Qwen 分辨率（`1K` / `2K`），Qwen 映射为 `1024x1024` / `2048x2048` | `1K` |
| `--model` | 覆盖模型，按模型注册表选择 Gemini、OpenAI Images 或 Seedream 适配器 | `gpt-image-2` |
| `--response-format` | Seedream 返回 `url` 或 `b64_json` | — |
| `--sequential-image-generation` | Seedream Lite 组图模式 | — |
| `--max-images` | Seedream Lite 最大生成数量 | — |
| `--layer-decomposition` | Seedream Pro / Flash 图层拆分 | — |
| `--base-url` | 覆盖服务根地址 | `https://llm-api-proxy.hnfunny.com` |
| `--api-key` | 覆盖服务令牌 | — |
| `--debug` | 输出调试日志到 stderr | 关 |
| `--help` | 显示帮助 | — |

## 快速用法

文生图：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --prompt "生成一张 16:9 的极简香蕉海报，不要任何文字。"
```

参考图编辑：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --prompt "保持主体不变，把背景改成晨雾中的山谷。" \
  --input /absolute/path/to/ref-1.png
```

指定比例与分辨率：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --prompt "生成一张赛博朋克风格香蕉图标。" \
  --aspect-ratio 1:1 \
  --image-size 2K \
  --output /tmp/banana-icon.png
```

完整参数说明、自动分流规则与错误处理见 [SKILL.md](SKILL.md)。

## 工作流

1. GPT/Qwen 调用 `{BASE_URL}/v1/images/generations` 或 `/v1/images/edits`；Seedream 无论是否有参考图都调用 `/v1/images/generations` JSON；Gemini 调用 `{BASE_URL}/v1beta/models/{MODEL}:generateContent`。
2. 按协议解析响应。Seedream 组图保存所有成功图片，图层拆分保留图层元数据。
3. 保存到 `--output`（或当前工作目录），输出 JSON 摘要（含 `outputs` 路径）。

## 重要约束

- **改图必须传 `--input`**：用户提供图片 / 截图 / 要求"改图、修图"时，必须将路径作为 `--input` 传入；没有 `--input` 只走纯文生图，参考图会被忽略。
- **禁止自动切换模型**：失败时不要自动换模型重试；展示错误后由用户决定是否重试或切换。
- `BASE_URL` 应为服务根地址，脚本自动拼出 `/v1beta/...` 或 `/v1/images/...`。
- Gemini/OpenAI Images 保持只保存最后一张的兼容行为；Seedream 组图会保存所有成功图片，并额外写出 `<output>.metadata.json` 保存 usage、单图错误和图层元数据。
