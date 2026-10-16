#!/usr/bin/env node

// 通过 Sofunny-AIKey 平台的 Gemini、OpenAI Images 或 Seedream 协议生成/编辑图片。
// 配置优先级：命令行参数 > 进程环境变量 > 共享 JSON > 旧 ~/.sofunny-image.env。

const fs = require("node:fs");
const http = require("node:http");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");
const { getModelFamily, getModelProfile } = require("./model-registry.js");
const { requestSeedream } = require("./adapters/seedream.js");
const geminiAdapter = require("./adapters/gemini.js");
const openAIImagesAdapter = require("./adapters/openai-images.js");
const HOME = os.homedir();
const SOFUNNY_ENV_PATH = path.join(HOME, ".sofunny-image.env");
const AIKEY_CONFIG_PATH = path.join(HOME, ".sofunny", "aikey-config.json");
const AIKEY_SKILL_SECTION = "sofunny-image";
const AIKEY_DEFAULT_SECTION = "default";
const DEFAULT_BASE_URL = "https://llm-api-proxy.hnfunny.com";
const DEFAULT_MODEL = "gpt-image-2";
let debugEnabled = false;

function printHelp() {
  console.log(`sofunny-image

使用：
  node scripts/sofunny-image.js --prompt "生成一张 16:9 的极简香蕉海报"

参数：
  --prompt         必填，图片生成或编辑指令
  --input          可重复传入，一张或多张参考图
  --output         输出文件路径
  --size           OpenAI 图片尺寸；未传时交由上游使用默认 auto
  --resolution     图片分辨率档位；支持 1K、2K、4K（仅在目标渠道支持时使用）
  --quality        OpenAI 图片质量；未传时不发送
  --background     OpenAI 背景参数
  --output-format  OpenAI 输出格式；未传时不发送
  --output-compression OpenAI 输出压缩率；未传时不发送
  --aspect-ratio   图片比例，默认 16:9
  --image-size     Gemini/Qwen 图片分辨率，默认 1K；Qwen 映射为 1024x1024/2048x2048
  --response-format Seedream/OpenAI Images 返回 url 或 b64_json
  --sequential-image-generation Seedream 组图模式 auto/disabled
  --max-images     Seedream 组图最大生成数量
  --watermark      Seedream 水印开关 true/false
  --layer-decomposition Seedream Pro/Flash 图层拆分 true/false
  --optimize-prompt-mode Seedream 提示词优化 standard/fast
  --model          覆盖模型
  --base-url       覆盖服务根地址
  --api-key        覆盖 Sofunny-AIKey 平台令牌
  --debug          输出调试日志到 stderr
  --help           显示帮助
`);
}

function parseArgs(argv) {
  const result = {
    input: [],
    aspectRatio: "16:9",
    imageSize: "1K",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--prompt":
        result.prompt = argv[++i];
        break;
      case "--input":
        result.input.push(argv[++i]);
        break;
      case "--output":
        result.output = argv[++i];
        break;
      case "--size":
        result.size = argv[++i];
        break;
      case "--resolution":
        result.resolution = argv[++i];
        break;
      case "--quality":
        result.quality = argv[++i];
        break;
      case "--background":
        result.background = argv[++i];
        break;
      case "--output-format":
        result.outputFormat = argv[++i];
        break;
      case "--output-compression":
        result.outputCompression = argv[++i];
        break;
      case "--aspect-ratio":
        result.aspectRatio = argv[++i];
        break;
      case "--image-size":
        result.imageSize = argv[++i];
        result.imageSizeProvided = true;
        break;
      case "--response-format":
        result.responseFormat = argv[++i];
        break;
      case "--sequential-image-generation":
        result.sequentialImageGeneration = argv[++i];
        break;
      case "--max-images":
        result.maxImages = argv[++i];
        break;
      case "--watermark":
        result.watermark = argv[++i];
        break;
      case "--layer-decomposition":
        result.layerDecomposition = argv[++i];
        break;
      case "--optimize-prompt-mode":
        result.optimizePromptMode = argv[++i];
        break;
      case "--tools-web-search":
        result.toolsWebSearch = true;
        break;
      case "--stream":
        result.stream = true;
        break;
      case "--model":
        result.model = argv[++i];
        break;
      case "--base-url":
        result.baseUrl = argv[++i];
        break;
      case "--api-key":
        result.apiKey = argv[++i];
        break;
      case "--help":
      case "-h":
        result.help = true;
        break;
      case "--debug":
        result.debug = true;
        break;
      default:
        throw new Error(`不支持的参数：${arg}`);
    }
  }

  return result;
}

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }

  const content = fs.readFileSync(filePath, "utf8");
  const env = {};

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const index = line.indexOf("=");
    if (index === -1) {
      continue;
    }
    const key = line.slice(0, index).trim();
    let value = line.slice(index + 1).trim();
    value = value.replace(/^['"]|['"]$/g, "");
    env[key] = value;
  }

  return env;
}

function normalizeBaseUrl(rawBaseUrl) {
  if (!rawBaseUrl) {
    return "";
  }

  let baseUrl = rawBaseUrl.trim().replace(/\/+$/, "");
  if (baseUrl.endsWith("/v1")) {
    baseUrl = baseUrl.slice(0, -3);
  }
  return baseUrl;
}

function applyConfigOverlay(target, source) {
  if (!source) {
    return;
  }

  if (source.SOFUNNY_BASE_URL) {
    target.baseUrl = source.SOFUNNY_BASE_URL;
  }
  if (source.SOFUNNY_API_KEY) {
    target.apiKey = source.SOFUNNY_API_KEY;
  }
  if (source.SOFUNNY_MODEL) {
    target.model = source.SOFUNNY_MODEL;
  }
}

function readSharedConfig(configPath) {
  if (!fs.existsSync(configPath)) {
    return { exists: false, payload: {} };
  }

  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch (error) {
    throw new Error(`无法解析共享配置 ${configPath}: ${error.message}`);
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error(`共享配置 ${configPath} 必须是 JSON 对象`);
  }

  for (const sectionName of [AIKEY_DEFAULT_SECTION, AIKEY_SKILL_SECTION]) {
    const section = payload[sectionName];
    if (section !== undefined && (!section || typeof section !== "object" || Array.isArray(section))) {
      throw new Error(`共享配置 ${configPath} 的 ${sectionName} 段必须是 JSON 对象`);
    }
  }
  return { exists: true, payload };
}

function applySharedConfigOverlay(target, sharedPayload) {
  const defaults = sharedPayload?.[AIKEY_DEFAULT_SECTION] || {};
  const skill = sharedPayload?.[AIKEY_SKILL_SECTION] || {};

  // base_url 与 api_key 按字段继承：Skill 段只覆盖自己明确填写的字段。
  for (const source of [defaults, skill]) {
    if (typeof source.base_url === "string" && source.base_url.trim()) {
      target.baseUrl = source.base_url;
    }
    if (typeof source.api_key === "string" && source.api_key.trim()) {
      target.apiKey = source.api_key;
    }
  }

  // model 是 Skill 专属设置，不从公共 default 段继承。
  if (typeof skill.model === "string" && skill.model.trim()) {
    target.model = skill.model;
  }
}

function resolveConfig(cliArgs, options = {}) {
  const homeDir = options.homeDir || HOME;
  const envPath = options.envPath || path.join(homeDir, ".sofunny-image.env");
  const configPath = options.configPath || path.join(homeDir, ".sofunny", "aikey-config.json");
  const processEnv = options.processEnv || process.env;
  const envFileExists = fs.existsSync(envPath);
  const sharedConfig = readSharedConfig(configPath);
  const fileEnv = parseEnvFile(envPath);
  const merged = {
    baseUrl: DEFAULT_BASE_URL,
    apiKey: "",
    model: DEFAULT_MODEL,
  };

  // 旧 .env 保留兼容性；共享 JSON 覆盖旧文件，进程环境变量再覆盖共享配置。
  applyConfigOverlay(merged, fileEnv);
  applySharedConfigOverlay(merged, sharedConfig.payload);
  applyConfigOverlay(merged, processEnv);

  if (cliArgs.baseUrl) {
    merged.baseUrl = cliArgs.baseUrl;
  }
  if (cliArgs.apiKey) {
    merged.apiKey = cliArgs.apiKey;
  }
  if (cliArgs.model) {
    merged.model = cliArgs.model;
  }

  return {
    baseUrl: normalizeBaseUrl(merged.baseUrl),
    apiKey: merged.apiKey,
    model: merged.model,
    envFileExists,
    sharedConfigExists: sharedConfig.exists,
    configPath,
    envPath,
  };
}

function buildEnvFileHint(config = {}) {
  return [
    `未找到图片 Skill 的 API Key。请配置共享文件 ${config.configPath || AIKEY_CONFIG_PATH}：`,
    '{"default":{"base_url":"https://llm-api-proxy.hnfunny.com","api_key":"你的 Sofunny-AIKey 平台令牌"},"sofunny-image":{"model":"gpt-image-2"}}',
  ].join("\n");
}

function chooseHttpClient(protocol) {
  if (protocol === "https:") {
    return https;
  }
  if (protocol === "http:") {
    return http;
  }
  throw new Error(`不支持的协议：${protocol}`);
}

function readJsonResponse(responseBuffer, endpoint, statusCode) {
  if (responseBuffer.length === 0) {
    return {};
  }

  try {
    return JSON.parse(responseBuffer.toString("utf8"));
  } catch (error) {
    throw new Error(`无法解析上游 JSON 响应：${endpoint} (status=${statusCode})`);
  }
}

function sendHttpRequest(endpoint, { method, headers, bodyBuffer }) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint);
    const client = chooseHttpClient(url.protocol);

    const request = client.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || undefined,
        path: `${url.pathname}${url.search}`,
        method,
        headers,
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => {
          chunks.push(Buffer.from(chunk));
        });
        response.on("end", () => {
          const responseBuffer = Buffer.concat(chunks);
          resolve({
            status: response.statusCode || 0,
            ok: (response.statusCode || 0) >= 200 && (response.statusCode || 0) < 300,
            headers: response.headers,
            payload: readJsonResponse(responseBuffer, endpoint, response.statusCode || 0),
          });
        });
      },
    );

    request.setTimeout(0);
    request.on("timeout", () => {
      request.destroy(new Error("请求超时"));
    });
    request.on("error", (error) => {
      reject(error);
    });

    if (bodyBuffer && bodyBuffer.length > 0) {
      request.write(bodyBuffer);
    }
    request.end();
  });
}

function downloadBuffer(endpoint) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint);
    const client = chooseHttpClient(url.protocol);
    client
      .get(url, (response) => {
        if ((response.statusCode || 0) < 200 || (response.statusCode || 0) >= 300) {
          response.resume();
          reject(new Error(`下载图片失败，状态码 ${response.statusCode || 0}`));
          return;
        }
        const chunks = [];
        response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        response.on("end", () => resolve(Buffer.concat(chunks)));
      })
      .on("error", reject);
  });
}

function ensureOutputDir(outputPath) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
}

function defaultOutputPath() {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  // 未指定输出路径时，默认把图片写到当前工作目录，便于在调用方当前项目中直接查看产物。
  return path.join(process.cwd(), `sofunny-image-${stamp}.png`);
}

function buildOutputPath(requestedOutput) {
  return requestedOutput ? path.resolve(requestedOutput) : defaultOutputPath();
}

function debugLog(enabled, message, extra) {
  if (!enabled) {
    return;
  }
  const prefix = `[sofunny-image ${new Date().toISOString()}]`;
  if (extra === undefined) {
    console.error(`${prefix} ${message}`);
    return;
  }
  console.error(`${prefix} ${message} ${JSON.stringify(extra)}`);
}

async function saveImageResults(result, outputPath) {
  const images = result.images || [{ imageBuffer: result.imageBuffer || Buffer.from(result.imageBase64, "base64") }];
  const outputPaths = [];
  for (let index = 0; index < images.length; index += 1) {
    const image = images[index];
    const target = images.length === 1
      ? outputPath
      : outputPath.replace(/(\.[^./]+)?$/, `-${index + 1}$1`);
    ensureOutputDir(target);
    fs.writeFileSync(target, image.imageBuffer);
    outputPaths.push(target);
  }
  let metadataPath = "";
  if (result.metadata?.items?.length) {
    metadataPath = outputPath.replace(/(\.[^./]+)?$/, ".metadata.json");
    ensureOutputDir(metadataPath);
    fs.writeFileSync(metadataPath, JSON.stringify(result.metadata, null, 2));
  }
  return { outputPaths, metadataPath };
}

async function main() {
  const cliArgs = parseArgs(process.argv.slice(2));
  debugEnabled = Boolean(cliArgs.debug);
  if (cliArgs.help) {
    printHelp();
    return;
  }

  if (!cliArgs.prompt) {
    throw new Error("缺少 --prompt");
  }

  const config = resolveConfig(cliArgs);
  const modelFamily = getModelFamily(config.model);
  if (modelFamily === "unknown") {
    throw new Error(`当前只支持 Gemini、GPT Image、Qwen Image 或 Doubao Seedream 模型，收到：${config.model}`);
  }

  if (!config.apiKey) {
    if (!config.envFileExists && !process.env.SOFUNNY_API_KEY && !cliArgs.apiKey) {
      throw new Error(buildEnvFileHint(config));
    }
    throw new Error(
      `未找到 SOFUNNY_API_KEY，请通过环境变量、${config.configPath} 或 --api-key 提供。旧版 ${config.envPath} 仅作兼容读取。`,
    );
  }

  let result;
  if (modelFamily === "gemini") {
    result = await geminiAdapter.requestGeminiImage(config, cliArgs, sendHttpRequest, debugLog);
  } else if (modelFamily === "seedream") {
    result = await requestSeedream(config, cliArgs, sendHttpRequest, downloadBuffer, debugLog);
  } else if (cliArgs.input.length > 0) {
    result = await openAIImagesAdapter.requestOpenAIImageEdit(config, cliArgs, sendHttpRequest, downloadBuffer, debugLog);
  } else {
    result = await openAIImagesAdapter.requestOpenAIImageGeneration(config, cliArgs, sendHttpRequest, downloadBuffer, debugLog);
  }

  const outputPath = buildOutputPath(cliArgs.output);
  const saved = await saveImageResults(result, outputPath);
  debugLog(cliArgs.debug, "output:saved", saved);

  const summary = {
    model: config.model,
    base_url: config.baseUrl,
    endpoint: result.endpoint,
    protocol: getModelProfile(config.model).protocol,
    returned_image_count: result.returnedImageCount || result.images?.length || 1,
    saved_image_count: saved.outputPaths.length,
    outputs: saved.outputPaths,
  };

  if (result.metadata) summary.metadata = result.metadata;
  if (saved.metadataPath) summary.metadata_path = saved.metadataPath;

  if (result.text) {
    summary.text = result.text;
  }
  if (result.revisedPrompt) {
    summary.revised_prompt = result.revisedPrompt;
  }

  console.log(JSON.stringify(summary, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    debugLog(debugEnabled, "request:error", {
      message: error.message || String(error),
      cause: error.cause ? String(error.cause) : undefined,
      code: error.code,
      stack: error.stack ? error.stack.split("\n").slice(0, 3).join(" | ") : undefined,
    });
    console.error(error.message || String(error));
    process.exit(1);
  });
}

module.exports = {
  buildOpenAIImagesBody: openAIImagesAdapter.buildOpenAIImagesBody,
  getModelFamily,
  getModelProfile,
  readSharedConfig,
  resolveConfig,
  resolveOpenAIImageSize: openAIImagesAdapter.resolveOpenAIImageSize,
};
