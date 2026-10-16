const fs = require("node:fs");
const path = require("node:path");

function isSeedreamModel(model) {
  return typeof model === "string" && /^doubao-seedream-/i.test(model.trim());
}

function isSeedreamPro(model) {
  return /seedream-5(?:\.0|-0)-pro/i.test(String(model || ""));
}

function isSeedreamLite(model) {
  return /seedream-5(?:\.0|-0)-(?:lite|260128)/i.test(String(model || ""));
}

function isSeedreamFlash(model) {
  return /seedream-5(?:\.0|-0)-flash/i.test(String(model || ""));
}

// Flash 的图片生成档位（1K/1.5K/2K）、参考图上限（10 张）和图层拆分能力与 Pro
// 完全一致（官方文档里两者共用同一段规格说明），因此「Pro 档能力」统一走这个
// 判据，避免两条平行分支各自漂移。唯一反向差异是 fast 提示词优化，单独判。
function isSeedreamProLike(model) {
  return isSeedreamPro(model) || isSeedreamFlash(model);
}

function dataUrlForFile(inputFile) {
  const absolutePath = path.resolve(inputFile);
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`输入图片不存在：${absolutePath}`);
  }
  const ext = path.extname(absolutePath).toLowerCase();
  const mime = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".bmp": "image/bmp",
    ".gif": "image/gif",
    ".tif": "image/tiff",
    ".tiff": "image/tiff",
    ".heic": "image/heic",
    ".heif": "image/heif",
  }[ext] || "application/octet-stream";
  return `data:${mime};base64,${fs.readFileSync(absolutePath).toString("base64")}`;
}

function resolveSeedreamSize(cliArgs, model) {
  if (cliArgs.size && cliArgs.resolution && String(cliArgs.size).trim().toUpperCase() !== String(cliArgs.resolution).trim().toUpperCase()) {
    throw new Error("Seedream 的 --size 和 --resolution 不能同时设置不同值");
  }
  const size = cliArgs.size || cliArgs.resolution || (cliArgs.imageSizeProvided ? cliArgs.imageSize : "");
  if (!size) return "";
  const normalized = String(size).trim();
  const upper = normalized.toUpperCase();
  const allowed = isSeedreamProLike(model) ? ["1K", "1.5K", "2K"] : ["2K", "3K", "4K"];
  if (allowed.includes(upper)) return upper;
  if (!/^\d+(?:\.\d+)?[xX*]\d+(?:\.\d+)?$/.test(normalized)) {
    throw new Error(`Seedream 的尺寸不支持：${size}`);
  }
  return normalized.replace("*", "x");
}

function parseBoolean(value, field) {
  if (value === undefined) return undefined;
  if (value === true || value === false) return value;
  if (value === "true" || value === "false") return value === "true";
  throw new Error(`${field} 必须是 true 或 false`);
}

function buildSeedreamBody(cliArgs, model) {
  if (!isSeedreamModel(model)) throw new Error(`不是 Seedream 模型：${model}`);
  if (!cliArgs.prompt) throw new Error("缺少 --prompt");
  const inputs = (cliArgs.input || []).map(dataUrlForFile);
  const maxInputs = isSeedreamProLike(model) ? 10 : 14;
  if (inputs.length > maxInputs) throw new Error(`Seedream 最多支持 ${maxInputs} 张参考图`);

  const body = { model, prompt: cliArgs.prompt };
  if (inputs.length === 1) body.image = inputs[0];
  if (inputs.length > 1) body.image = inputs;
  const size = resolveSeedreamSize(cliArgs, model);
  if (size) body.size = size;
  if (cliArgs.outputFormat) body.output_format = cliArgs.outputFormat;
  if (cliArgs.background) body.background = cliArgs.background;
  if (cliArgs.responseFormat) {
    if (!["url", "b64_json"].includes(cliArgs.responseFormat)) {
      throw new Error("--response-format 仅支持 url 或 b64_json");
    }
    body.response_format = cliArgs.responseFormat;
  }
  const watermark = parseBoolean(cliArgs.watermark, "--watermark");
  if (watermark !== undefined) body.watermark = watermark;
  const layerDecomposition = parseBoolean(cliArgs.layerDecomposition, "--layer-decomposition");
  if (layerDecomposition !== undefined) {
    if (!isSeedreamProLike(model)) throw new Error("图层拆分仅支持 Seedream Pro 与 Flash");
    if (inputs.length !== 1) throw new Error("图层拆分必须且只能传入一张参考图");
    body.layer_decomposition = layerDecomposition;
  }
  if (cliArgs.sequentialImageGeneration !== undefined) {
    if (!isSeedreamLite(model)) throw new Error("组图模式仅支持 Seedream Lite");
    if (!["auto", "disabled"].includes(cliArgs.sequentialImageGeneration)) {
      throw new Error("--sequential-image-generation 仅支持 auto 或 disabled");
    }
    body.sequential_image_generation = cliArgs.sequentialImageGeneration;
  }
  if (cliArgs.maxImages !== undefined) {
    if (!isSeedreamLite(model)) throw new Error("--max-images 仅支持 Seedream Lite");
    if (cliArgs.sequentialImageGeneration !== "auto") {
      throw new Error("--max-images 只能与 --sequential-image-generation auto 一起使用");
    }
    const maxImages = Number.parseInt(cliArgs.maxImages, 10);
    if (!Number.isInteger(maxImages) || maxImages < 1 || maxImages > 15) {
      throw new Error("--max-images 必须是 1 到 15 之间的整数");
    }
    if (inputs.length + maxImages > 15) throw new Error("参考图数量与 max_images 之和不能超过 15");
    body.sequential_image_generation_options = { max_images: maxImages };
  }
  if (cliArgs.optimizePromptMode !== undefined) {
    if (!["standard", "fast"].includes(cliArgs.optimizePromptMode)) {
      throw new Error("--optimize-prompt-mode 仅支持 standard 或 fast");
    }
    if (cliArgs.optimizePromptMode === "fast" && (isSeedreamLite(model) || isSeedreamFlash(model))) {
      throw new Error("Seedream Lite 与 Flash 不支持 fast 提示词优化");
    }
    body.optimize_prompt_options = { mode: cliArgs.optimizePromptMode };
  }
  if (cliArgs.toolsWebSearch) {
    if (!isSeedreamLite(model)) throw new Error("联网搜索工具仅支持 Seedream Lite");
    body.tools = [{ type: "web_search" }];
  }
  if (cliArgs.stream === true || cliArgs.stream === "true") {
    throw new Error("当前 Skill 暂不支持 Seedream 流式输出");
  }
  return body;
}

function parseSeedreamResponse(payload) {
  const items = Array.isArray(payload?.data) ? payload.data : [];
  const usable = items.filter((item) => item?.b64_json || item?.url);
  if (usable.length === 0) {
    const message = payload?.error?.message || "Seedream 响应里没有找到图片数据。";
    throw new Error(message);
  }
  return {
    images: usable.map((item) => ({
      b64Json: item.b64_json || "",
      url: item.url || "",
      size: item.size || "",
      outputFormat: item.output_format || "",
      error: item.error || null,
      zIndex: item.z_index,
      name: item.name || "",
      description: item.description || "",
      boundingBox: item.bounding_box || null,
    })),
    metadata: {
      created: payload.created,
      model: payload.model,
      usage: payload.usage || {},
      tools: payload.tools || [],
      errors: items.filter((item) => item?.error).map((item) => item.error),
    },
  };
}

async function requestSeedream(config, cliArgs, sendHttpRequest, downloadBuffer, debugLog) {
  const endpoint = `${config.baseUrl}/v1/images/generations`;
  const body = buildSeedreamBody(cliArgs, config.model);
  const requestBuffer = Buffer.from(JSON.stringify(body), "utf8");
  debugLog(cliArgs.debug, "request:start", {
    model_family: "seedream",
    endpoint,
    input_count: cliArgs.input.length,
    fields: Object.keys(body).filter((key) => key !== "image"),
  });
  const response = await sendHttpRequest(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      "Content-Length": String(requestBuffer.length),
    },
    bodyBuffer: requestBuffer,
  });
  if (!response.ok) {
    throw new Error(response.payload?.error?.message || `请求失败，状态码 ${response.status}`);
  }
  const parsed = parseSeedreamResponse(response.payload);
  const images = [];
  for (const item of parsed.images) {
    images.push({
      imageBuffer: item.b64Json ? Buffer.from(item.b64Json, "base64") : await downloadBuffer(item.url),
      extension: item.outputFormat === "jpeg" ? "jpg" : "png",
      metadata: item,
    });
  }
  return {
    ...parsed,
    images,
    metadata: {
      ...parsed.metadata,
      items: parsed.images.map(({ b64Json, ...item }) => item),
    },
    endpoint,
  };
}

module.exports = {
  buildSeedreamBody,
  getSeedreamModelCapabilities: (model) => ({
    protocol: "seedream",
    isPro: isSeedreamPro(model),
    isLite: isSeedreamLite(model),
    isFlash: isSeedreamFlash(model),
    maxInputs: isSeedreamProLike(model) ? 10 : 14,
  }),
  isSeedreamModel,
  parseSeedreamResponse,
  requestSeedream,
};
