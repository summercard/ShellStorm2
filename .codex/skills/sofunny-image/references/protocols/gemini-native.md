# Gemini 原生协议适配

`gemini-*` 模型调用 Sofunny-AIKey 的 Gemini 兼容入口：

```text
/v1beta/models/{model}:generateContent
```

参考图以内嵌 `inlineData` 传入，生成配置使用 `responseModalities: ["TEXT", "IMAGE"]`、`imageConfig.aspectRatio` 和 `imageConfig.imageSize`。响应从最后一个图片 `inlineData.data` 提取并保存。
