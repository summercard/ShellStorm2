const fs = require("node:fs");
const path = require("node:path");

function detectMimeType(filePath) {
  return ({
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".webp": "image/webp", ".gif": "image/gif",
  })[path.extname(filePath).toLowerCase()] || "application/octet-stream";
}

function buildMultipartBody(fields, files) {
  const boundary = `----sofunny-image-${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`;
  const chunks = [];
  for (const [name, value] of fields) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`, "utf8"));
  }
  for (const file of files) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${file.name}"; filename="${file.filename}"\r\nContent-Type: ${file.contentType}\r\n\r\n`, "utf8"));
    chunks.push(file.buffer, Buffer.from("\r\n", "utf8"));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`, "utf8"));
  return { boundary, bodyBuffer: Buffer.concat(chunks) };
}

function optionalImageParams(cliArgs) {
  return {
    has_size: Boolean(cliArgs.size), has_quality: Boolean(cliArgs.quality),
    has_background: Boolean(cliArgs.background), has_output_format: Boolean(cliArgs.outputFormat),
    has_output_compression: cliArgs.outputCompression !== undefined,
  };
}

function resolveOpenAIImageSize(cliArgs, model) {
  if (cliArgs.size) return cliArgs.size;
  if (!String(model || "").toLowerCase().startsWith("qwen-image-")) return "";
  const imageSize = String(cliArgs.imageSize || "").trim().toUpperCase();
  if (imageSize === "1K") return "1024x1024";
  if (imageSize === "2K") return "2048x2048";
  throw new Error("Qwen 图片模型的 --image-size 仅支持 1K 或 2K");
}

function buildOpenAIImagesBody(cliArgs, model) {
  const body = { model, prompt: cliArgs.prompt };
  const size = resolveOpenAIImageSize(cliArgs, model);
  if (size) body.size = size;
  if (cliArgs.resolution) {
    const resolution = String(cliArgs.resolution).trim().toUpperCase();
    if (!["1K", "2K", "4K"].includes(resolution)) throw new Error("resolution 仅支持 1K、2K 或 4K");
    body.resolution = resolution;
  }
  if (cliArgs.quality) body.quality = cliArgs.quality;
  if (cliArgs.outputFormat) body.output_format = cliArgs.outputFormat;
  if (cliArgs.outputCompression !== undefined) {
    body.output_compression = Number.parseInt(cliArgs.outputCompression, 10);
    if (Number.isNaN(body.output_compression)) throw new Error("--output-compression 必须是整数");
  }
  if (cliArgs.background) body.background = cliArgs.background;
  return body;
}

async function openAIImageResult(payload, endpoint, downloadBuffer) {
  const items = Array.isArray(payload?.data) ? payload.data.filter((item) => item?.b64_json || item?.url) : [];
  if (items.length === 0) throw new Error("响应里没有找到 b64_json 或 url 图片数据。");
  const finalImage = items[items.length - 1];
  return {
    imageBuffer: finalImage.b64_json ? Buffer.from(finalImage.b64_json, "base64") : await downloadBuffer(finalImage.url),
    returnedImageCount: items.length,
    revisedPrompt: finalImage.revised_prompt || "",
    endpoint,
  };
}

async function requestOpenAIImageGeneration(config, cliArgs, sendHttpRequest, downloadBuffer, debugLog) {
  const endpoint = `${config.baseUrl}/v1/images/generations`;
  const startedAt = Date.now();
  debugLog(cliArgs.debug, "request:start", {
    model_family: "openai-images", mode: "generation", endpoint, input_count: 0,
    optional_params: { ...optionalImageParams(cliArgs), size: resolveOpenAIImageSize(cliArgs, config.model) || undefined },
  });
  const requestBuffer = Buffer.from(JSON.stringify(buildOpenAIImagesBody(cliArgs, config.model)), "utf8");
  const response = await sendHttpRequest(endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${config.apiKey}`, "Content-Type": "application/json", "Content-Length": String(requestBuffer.length) },
    bodyBuffer: requestBuffer,
  });
  debugLog(cliArgs.debug, "request:response", { endpoint, status: response.status, ok: response.ok, duration_ms: Date.now() - startedAt });
  if (!response.ok) throw new Error(response.payload?.error?.message || `请求失败，状态码 ${response.status}`);
  return openAIImageResult(response.payload, endpoint, downloadBuffer);
}

async function requestOpenAIImageEdit(config, cliArgs, sendHttpRequest, downloadBuffer, debugLog) {
  const endpoint = `${config.baseUrl}/v1/images/edits`;
  const fields = [["model", config.model], ["prompt", cliArgs.prompt]];
  const size = resolveOpenAIImageSize(cliArgs, config.model);
  if (size) fields.push(["size", size]);
  if (cliArgs.resolution) {
    const resolution = String(cliArgs.resolution).trim().toUpperCase();
    if (!["1K", "2K", "4K"].includes(resolution)) throw new Error("--resolution 仅支持 1K、2K 或 4K");
    fields.push(["resolution", resolution]);
  }
  if (cliArgs.quality) fields.push(["quality", cliArgs.quality]);
  if (cliArgs.outputFormat) fields.push(["output_format", cliArgs.outputFormat]);
  if (cliArgs.outputCompression !== undefined) {
    const value = Number.parseInt(cliArgs.outputCompression, 10);
    if (Number.isNaN(value)) throw new Error("--output-compression 必须是整数");
    fields.push(["output_compression", String(value)]);
  }
  if (cliArgs.background) fields.push(["background", cliArgs.background]);
  const files = cliArgs.input.map((inputFile) => {
    const absolutePath = path.resolve(inputFile);
    if (!fs.existsSync(absolutePath)) throw new Error(`输入图片不存在：${absolutePath}`);
    return { name: "image[]", filename: path.basename(absolutePath), contentType: detectMimeType(absolutePath), buffer: fs.readFileSync(absolutePath) };
  });
  const { boundary, bodyBuffer } = buildMultipartBody(fields, files);
  debugLog(cliArgs.debug, "request:start", {
    model_family: "openai-images", mode: "edit", endpoint, input_count: cliArgs.input.length,
    optional_params: { ...optionalImageParams(cliArgs), size: size || undefined },
  });
  const response = await sendHttpRequest(endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${config.apiKey}`, "Content-Type": `multipart/form-data; boundary=${boundary}`, "Content-Length": String(bodyBuffer.length) },
    bodyBuffer,
  });
  if (!response.ok) throw new Error(response.payload?.error?.message || `请求失败，状态码 ${response.status}`);
  return openAIImageResult(response.payload, endpoint, downloadBuffer);
}

module.exports = { buildOpenAIImagesBody, requestOpenAIImageEdit, requestOpenAIImageGeneration, resolveOpenAIImageSize };
