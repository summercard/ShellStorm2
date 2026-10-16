# Doubao Seedream 协议适配

Seedream 通过 Sofunny-AIKey 的 `/v1/images/generations` 入口调用，但请求和响应不是普通 OpenAI Images 的完全等价协议。

## 请求规则

- 无论文生图还是图生图，都发送 JSON 到 `/v1/images/generations`。
- 参考图使用 `image` 字段，单张为字符串，多张为字符串数组；本地文件由脚本转为 `data:image/<format>;base64,...`。
- 不使用 OpenAI multipart `/v1/images/edits` 作为 Seedream 图生图路径。
- Pro 与 Flash 最多 10 张参考图；Lite 最多 14 张。
- Pro 与 Flash 支持 `layer_decomposition`，要求恰好一张参考图；不支持组图。
- Lite 支持 `sequential_image_generation` 与 `sequential_image_generation_options.max_images`。
- Seedream 的 `n` 不用于表达组图数量。
- `size` 支持模型对应的分辨率档位或合法的宽高像素值；Pro 与 Flash 的图片生成档位是 `1K` / `1.5K` / `2K`，Lite 是 `2K` / `3K` / `4K`。不要把 `--aspect-ratio` 伪装成未知的上游字段。
- `optimize_prompt_options.mode=fast` 只有 Pro 支持；Flash 与 Lite 仅支持 `standard`，传入 `fast` 会被 Skill 直接拒绝。
- `stream` 当前由 Skill 明确拒绝，避免误以为平台已支持 Seedream 流式输出。

## 响应规则

Seedream `data[]` 中既可能有成功图片，也可能有单图 `error`。解析器应保留成功图片的：

- `url` / `b64_json`
- `size`
- `output_format`
- `z_index`
- `name`
- `description`
- `bounding_box.absolute`
- `bounding_box.normalized`

URL 仅在生成后 24 小时内有效，必须在本地保存阶段立即下载。组图要保存所有成功图片，不得只取最后一张；图层拆分要在输出摘要中保留图层元数据。

## 模型别名

Skill 使用平台稳定模型名：

- `doubao-seedream-5-0-pro`
- `doubao-seedream-5-0-flash`
- `doubao-seedream-5-0-lite`

Ark 的版本化 Model ID 或 `ep-...` Endpoint ID 由 Sofunny-AIKey 后端渠道重定向处理，Skill 不应硬编码版本号。
