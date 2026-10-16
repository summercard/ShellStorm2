# OpenAI Images 兼容协议适配

GPT Image 和 Qwen Image 使用 Sofunny-AIKey 的统一图片入口：

- 文生图：`/v1/images/generations` JSON
- 图生图：`/v1/images/edits` multipart

Qwen 的上游原生字段由平台渠道适配器负责转换。Skill 只负责 Qwen 的 `1K / 2K` 尺寸映射，不直接调用阿里百炼原生 API。

GPT Image 未显式传入 `size`、`quality`、`background` 等字段时，Skill 不主动补发，保持既有上游默认行为。
