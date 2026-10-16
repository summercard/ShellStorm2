const fs = require("node:fs");
const path = require("node:path");

function detectMimeType(filePath) {
  return ({
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".webp": "image/webp", ".gif": "image/gif",
  })[path.extname(filePath).toLowerCase()] || "application/octet-stream";
}

function buildGeminiParts(prompt, inputFiles) {
  const parts = [{ text: prompt }];
  for (const inputFile of inputFiles) {
    const absolutePath = path.resolve(inputFile);
    if (!fs.existsSync(absolutePath)) throw new Error(`输入图片不存在：${absolutePath}`);
    parts.push({
      inlineData: {
        mimeType: detectMimeType(absolutePath),
        data: fs.readFileSync(absolutePath).toString("base64"),
      },
    });
  }
  return parts;
}

function buildGeminiBody(cliArgs) {
  return {
    contents: [{ role: "user", parts: buildGeminiParts(cliArgs.prompt, cliArgs.input) }],
    generationConfig: {
      responseModalities: ["TEXT", "IMAGE"],
      imageConfig: { aspectRatio: cliArgs.aspectRatio, imageSize: cliArgs.imageSize },
    },
  };
}

async function requestGeminiImage(config, cliArgs, sendHttpRequest, debugLog) {
  const endpoint = `${config.baseUrl}/v1beta/models/${encodeURIComponent(config.model)}:generateContent`;
  const startedAt = Date.now();
  debugLog(cliArgs.debug, "request:start", {
    model_family: "gemini", endpoint, input_count: cliArgs.input.length,
  });
  const requestBuffer = Buffer.from(JSON.stringify(buildGeminiBody(cliArgs)), "utf8");
  const response = await sendHttpRequest(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      "Content-Length": String(requestBuffer.length),
    },
    bodyBuffer: requestBuffer,
  });
  debugLog(cliArgs.debug, "request:response", {
    endpoint, status: response.status, ok: response.ok, duration_ms: Date.now() - startedAt,
  });
  if (!response.ok) throw new Error(response.payload?.error?.message || `请求失败，状态码 ${response.status}`);

  const parts = response.payload?.candidates?.[0]?.content?.parts || [];
  const imageParts = parts.filter((part) => part?.inlineData?.data);
  if (imageParts.length === 0) {
    const text = parts.filter((part) => part?.text).map((part) => part.text).join("\n");
    throw new Error(text || "响应里没有找到图片数据。");
  }
  return {
    imageBase64: imageParts[imageParts.length - 1].inlineData.data,
    returnedImageCount: imageParts.length,
    text: parts.filter((part) => part?.text).map((part) => part.text).join("\n").trim(),
    endpoint,
  };
}

module.exports = { buildGeminiBody, requestGeminiImage };
