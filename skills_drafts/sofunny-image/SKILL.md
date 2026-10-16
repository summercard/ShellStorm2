---
name: sofunny-image
version: 1.1.0
description: 使用 Sofunny-AIKey 平台按模型前缀自动调用 Gemini 原生接口或 OpenAI Images 兼容 API 生成/编辑图片，支持 GPT Image 与 Qwen Image。适用于文本生图、参考图编辑、1K/2K 图片生成和输出本地图片，并希望复用共享 `~/.sofunny/aikey-config.json` 配置或当前 shell 环境变量的场景。
---

# sofunny-image

## 何时使用

在以下场景使用本 skill：

- 用户要生成图片，而当前客户端主模型并不适合直接承担图片输出
- 用户要上传一张或多张参考图，再结合文本生成新图片
- 用户要通过 `Sofunny-AIKey` 平台出图，并按模型前缀自动选择 Gemini 原生接口或 OpenAI Images API
- 用户希望优先复用共享连接配置：
  - `~/.sofunny/aikey-config.json`
  - 进程环境变量

如果只是普通文本问答、代码生成或工具调用，不要使用本 skill。

## 配置来源

脚本按「命令行参数 > 进程环境变量 > `~/.sofunny/aikey-config.json` > 旧版 `~/.sofunny-image.env` > 内置默认值」的优先级读取配置（高优先级覆盖低优先级）。

推荐使用共享配置文件：

```json
{
  "default": {
    "base_url": "https://llm-api-proxy.hnfunny.com",
    "api_key": "你的 Sofunny-AIKey 平台令牌"
  },
  "sofunny-image": {
    "model": "gpt-image-2"
  }
}
```

`base_url` 和 `api_key` 按字段继承：`sofunny-image` 段只覆盖自己明确填写的字段，其余字段继承 `default`。`model` 只读取 `sofunny-image` 段，不从 `default` 继承。共享 JSON 存在但格式错误时会直接报错，避免静默使用过期配置。

优先变量：`SOFUNNY_BASE_URL`、`SOFUNNY_API_KEY`、`SOFUNNY_MODEL`。默认期望值：

- `SOFUNNY_BASE_URL=https://llm-api-proxy.hnfunny.com`
- `SOFUNNY_MODEL=gpt-image-2`

支持的模型（按模型注册表选择协议适配器）：

- `gemini-3.1-flash-lite-image`（Gemini 原生接口）
- `gemini-3.1-flash-image`（Gemini 原生接口）
- `gemini-3-pro-image`（Gemini 原生接口）
- `gpt-image-2`（OpenAI Images API）
- `gpt-image-2.5-flare`（OpenAI Images API，速度优先）
- `gpt-image-2.5-sunburst`（OpenAI Images API，质量与可控性优先）
- `qwen-image-3.0-pro`（OpenAI Images 兼容接口）
- `doubao-seedream-5-0-pro`（Seedream 专用 JSON 图片接口）
- `doubao-seedream-5-0-flash`（Seedream 专用 JSON 图片接口，与 Pro 同能力档，不支持 fast 提示词优化）
- `doubao-seedream-5-0-lite`（Seedream 专用 JSON 图片接口）

旧版 `~/.sofunny-image.env` 仍会被读取，用于兼容已有安装；它不是新安装的推荐配置位置。若共享配置不存在，脚本才会回退读取旧文件。

## 安装与执行入口

## 协议适配器

脚本通过模型注册表选择协议适配器，入口层不把所有图片模型强行当成同一种 OpenAI 请求：

- `scripts/adapters/gemini.js`：Gemini 原生 `generateContent` 请求与响应
- `scripts/adapters/openai-images.js`：GPT Image，以及由 Sofunny-AIKey 统一转换的 Qwen Image
- `scripts/adapters/seedream.js`：Doubao Seedream 专用 JSON 请求、组图、图层拆分和元数据响应
- `scripts/model-registry.js`：模型前缀与协议能力档案

渠道原生差异由 Sofunny-AIKey 后端处理。Skill 只在协议确实不同的地方分流；例如 Seedream 即使有参考图也仍走 JSON `generations`，不会复用 OpenAI 的 multipart `edits`。

- 推荐安装：`npx skills add https://git.sofunny.io/skill-libs/sofunny-image.git`，安装时可自主选择目标 Agent（Claude Code / Codex 等）的 skills 路径。
- 可执行脚本入口：`<安装目录>/scripts/sofunny-image.js`（下文示例以 `${SKILL_DIR}` 代指该安装目录）。
- 依赖：Node.js 18+（内置 `fetch`）。

## 更新

```bash
npx skills update sofunny-image
```

或批量更新所有已安装 skill：`npx skills update`（被 pin 固定版本的 skill 会跳过）。更新后需重启 Agent。

## 快速用法

文本生图：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --prompt "生成一张 16:9 的极简香蕉海报，不要任何文字。"
```

参考图编辑：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --prompt "保持主体不变，把背景改成晨雾中的山谷。" \
  --input /absolute/path/to/ref-1.png \
  --input /absolute/path/to/ref-2.jpg
```

指定输出、比例和分辨率：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --prompt "生成一张赛博朋克风格香蕉图标。" \
  --aspect-ratio 1:1 \
  --image-size 2K \
  --output /tmp/banana-icon.png
```

使用 `gpt-image-2` 文生图：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --model gpt-image-2 \
  --prompt "生成一张极简风格的蓝色机械鸟海报，不要文字。"
```

使用 `gpt-image-2` 图生图：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --model gpt-image-2 \
  --prompt "保留主体轮廓，把材质改成磨砂陶瓷。" \
  --input /absolute/path/to/ref-1.png
```

使用 `qwen-image-3.0-pro` 生成 2K 图片：

```bash
node ${SKILL_DIR}/scripts/sofunny-image.js \
  --model qwen-image-3.0-pro \
  --image-size 2K \
  --prompt "生成一张厦门海岸的写实风景照。"
```

## 参数说明

- `--prompt`：必填，图片生成或编辑指令
- `--input`：可重复传入，一张或多张参考图
- `--output`：可选，输出文件路径
- `--size`：可选，OpenAI 图片尺寸；支持 `1024x1024`、`1024x1536`、`1536x1024`、`auto`；未传时不发送该字段，由上游使用默认 `auto`
- `--resolution`：可选，统一图片分辨率档位；支持 `1K`、`2K`、`4K`。由中转按实际渠道转换参数，Skill 不感知 Azure 或腾讯云渠道；可与 `--size` 同时传入以表达目标档位和画幅。
- `--quality`：可选，OpenAI 图片质量；支持 `low`、`medium`、`high`、`auto`；未传时不发送该字段
- `--background`：可选，OpenAI 背景参数；支持 `transparent`、`opaque`、`auto`
- `--output-format`：可选，OpenAI 输出格式；支持 `png`、`webp`、`jpeg`；未传时不发送该字段
- `--output-compression`：可选，OpenAI 输出压缩率；未传时不发送该字段
- `--aspect-ratio`：可选，默认 `16:9`
- `--image-size`：可选，默认 `1K`；Gemini 原样写入 `imageConfig.imageSize`，`qwen-image-*` 的 `1K` / `2K` 分别映射为 `size=1024x1024` / `size=2048x2048`
- `--model`：可选，默认读取共享配置中的 `sofunny-image.model`，兜底为 `gpt-image-2`；`gemini-*` 走 Gemini 原生接口，`gpt-image-*` / `qwen-image-*` 走 OpenAI Images API，`doubao-seedream-*` 走 Seedream 专用 JSON 适配器
- `--response-format`：可选，Seedream 返回 `url` 或 `b64_json`
- `--sequential-image-generation`：可选，Seedream Lite 组图模式 `auto` / `disabled`
- `--max-images`：可选，Seedream Lite 最大生成数量（1-15）
- `--watermark`：可选，Seedream 水印开关
- `--layer-decomposition`：可选，Seedream Pro / Flash 图层拆分开关
- `--optimize-prompt-mode`：可选，Seedream 提示词优化 `standard` / `fast`（`fast` 仅 Pro 支持，Flash 与 Lite 会被拒绝）
- `--tools-web-search`：可选，Seedream Lite 联网搜索工具
- `--base-url`：可选，覆盖配置中的 base URL
- `--api-key`：可选，覆盖配置中的 token

## 工作流

1. 收集用户的 prompt、参考图、输出路径和画幅要求。
   - **改图/修图判断**：当用户提供了图片路径、截图、或明确要求"改图"、"修图"、"基于这张图"、"编辑这张图"时，必须将图片路径作为 `--input` 参数传递。没有 `--input` 的调用只会走纯文生图，参考图会被完全忽略。
   - 如果用户提到的图片是对话中之前生成的，使用之前保存的输出路径作为 `--input`。
   - 如果用户提供了截图或粘贴了图片路径，确认路径有效后作为 `--input` 传入。
   - `--input` 可重复传入多张参考图（如 `--input a.png --input b.png`）。
2. 运行 `scripts/sofunny-image.js`。
3. 脚本会按模型前缀自动分流：
   - `gemini-*`：调用 `{BASE_URL}/v1beta/models/{MODEL}:generateContent`
   - `gpt-image-*` / `qwen-image-*` 且无 `--input`：调用 `{BASE_URL}/v1/images/generations`（纯文生图）
   - `gpt-image-*` / `qwen-image-*` 且有 `--input`：调用 `{BASE_URL}/v1/images/edits`（图生图/改图）
   - `doubao-seedream-*`：无论是否有 `--input` 均调用 `{BASE_URL}/v1/images/generations`，以 JSON 的 `image` 字段传入参考图；支持组图与图层元数据，详见 [Seedream 协议参考](references/protocols/seedream.md)
   - `gpt-image-2.5-*` 的 `resolution` 由中转按渠道适配：Azure 转为 `size`，腾讯云保留为 `resolution`。调用 Skill 时无需指定渠道。
4. Gemini 响应提取最后一个 `inlineData.data`；OpenAI Images 响应提取最后一个 `data[].b64_json` 或下载最后一个 `data[].url`，并视为最终图片保存到本地。
5. 把保存路径返回给用户。

## 错误处理

- **禁止自动切换模型**：如果脚本调用失败，不要自动更换模型重试。用户配置（共享 JSON、环境变量或 `--model`）指定的模型就是要用的模型。
- 失败时应按以下顺序提示用户：
  1. 展示完整错误信息
  2. 建议用户检查配置（API Key、模型名称、渠道是否可用）
  3. 询问用户是否要重试（相同模型、相同参数）
  4. 询问用户是否要切换到其他模型（给出推荐，如 `gpt-image-2`、`gemini-3.1-flash-lite-image`、`gemini-3.1-flash-image`、`gemini-3-pro-image`），由用户决定
- 不要在用户未确认的情况下更换模型、更换参数或跳过错误。

## 注意事项

- 本 skill 默认不附带 `tools` 和 `thinking`，避免图片模型在工具模式下失败。
- `BASE_URL` 应为服务根地址；脚本会自动拼出 `/v1beta/...` 或 `/v1/images/...`，不要手动把环境变量写成特定接口路径。
- 若未指定输出路径，脚本默认保存到：
  - 当前工作目录
- 缺少 API Key 时，脚本提示配置 `~/.sofunny/aikey-config.json`；旧 `.env` 仅作为兼容读取来源。
- Gemini/OpenAI Images 保持兼容行为；Seedream 组图会保存所有成功图片，图层拆分会在输出摘要和 `<output>.metadata.json` 中保留 `z_index`、名称、描述和边界框。
- 当前 `gpt-image-*` 先不支持 `mask`；若用户传入 `--input`，默认按普通图生图/编辑处理。
- `gpt-image-*` 若未显式传入 `--size`、`--quality`、`--background`、`--output-format`、`--output-compression`，脚本不会自动补发这些字段，避免把“脚本默认值”误当成“用户显式指定”传给上游。
- `qwen-image-*` 使用 `--image-size 1K|2K` 指定分辨率档位；若同时传入 `--size`，以 `--size` 为准。Qwen 当前返回 PNG，最终计费以实际响应图片尺寸为准。
- 若需要稳定复现某个上游参数组合，再显式传入对应参数，例如 `--quality auto`、`--output-format png`。
