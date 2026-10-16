const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const { buildOpenAIImagesBody, resolveConfig } = require("./sofunny-image.js");
const { getModelProfile } = require("./model-registry.js");
const {
  buildSeedreamBody,
  getSeedreamModelCapabilities,
  parseSeedreamResponse,
} = require("./adapters/seedream.js");

function makeConfigFixture({ shared, env } = {}) {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "sofunny-image-config-"));
  const configPath = path.join(homeDir, ".sofunny", "aikey-config.json");
  const envPath = path.join(homeDir, ".sofunny-image.env");
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  if (shared !== undefined) {
    fs.writeFileSync(configPath, typeof shared === "string" ? shared : JSON.stringify(shared));
  }
  if (env !== undefined) {
    fs.writeFileSync(envPath, env);
  }
  return { homeDir, configPath, envPath };
}

test("adds an explicit resolution for OpenAI-compatible image models", () => {
  assert.deepEqual(
    buildOpenAIImagesBody(
      { prompt: "test", resolution: "2k", quality: "high" },
      "gpt-image-2.5-sunburst",
    ),
    {
      model: "gpt-image-2.5-sunburst",
      prompt: "test",
      resolution: "2K",
      quality: "high",
    },
  );
});

test("does not add provider-specific fields when resolution is omitted", () => {
  assert.deepEqual(
    buildOpenAIImagesBody({ prompt: "test", quality: "high" }, "gpt-image-2.5"),
    { model: "gpt-image-2.5", prompt: "test", quality: "high" },
  );
});

test("loads shared default and skill settings with field-level inheritance", () => {
  const fixture = makeConfigFixture({
    shared: {
      default: { base_url: "https://shared.example", api_key: "shared-key", model: "ignored" },
      "sofunny-image": { model: "qwen-image-3.0-pro" },
    },
    env: "SOFUNNY_BASE_URL=https://legacy.example\nSOFUNNY_API_KEY=legacy-key\nSOFUNNY_MODEL=gpt-image-2\n",
  });

  const config = resolveConfig({}, {
    ...fixture,
    processEnv: {},
  });

  assert.equal(config.baseUrl, "https://shared.example");
  assert.equal(config.apiKey, "shared-key");
  assert.equal(config.model, "qwen-image-3.0-pro");
  assert.equal(config.sharedConfigExists, true);
});

test("skill fields override shared defaults while missing fields inherit independently", () => {
  const fixture = makeConfigFixture({
    shared: {
      default: { base_url: "https://shared.example", api_key: "shared-key" },
      "sofunny-image": { api_key: "skill-key" },
    },
  });

  const config = resolveConfig({}, {
    ...fixture,
    processEnv: {},
  });

  assert.equal(config.baseUrl, "https://shared.example");
  assert.equal(config.apiKey, "skill-key");
  assert.equal(config.model, "gpt-image-2");
});

test("does not inherit model from the shared default section", () => {
  const fixture = makeConfigFixture({
    shared: { default: { model: "qwen-image-3.0-pro", api_key: "key" } },
  });

  const config = resolveConfig({}, {
    ...fixture,
    processEnv: {},
  });

  assert.equal(config.model, "gpt-image-2");
  assert.equal(config.apiKey, "key");
});

test("environment variables and CLI values override shared and legacy config", () => {
  const fixture = makeConfigFixture({
    shared: { default: { base_url: "https://shared.example", api_key: "shared-key" } },
    env: "SOFUNNY_BASE_URL=https://legacy.example\nSOFUNNY_API_KEY=legacy-key\n",
  });

  const config = resolveConfig({
    baseUrl: "https://cli.example/v1/",
    apiKey: "cli-key",
    model: "gpt-image-2.5",
  }, {
    ...fixture,
    processEnv: {
      SOFUNNY_BASE_URL: "https://env.example",
      SOFUNNY_API_KEY: "env-key",
      SOFUNNY_MODEL: "qwen-image-3.0-pro",
    },
  });

  assert.equal(config.baseUrl, "https://cli.example");
  assert.equal(config.apiKey, "cli-key");
  assert.equal(config.model, "gpt-image-2.5");
});

test("falls back to legacy env when shared config is absent", () => {
  const fixture = makeConfigFixture({
    env: "SOFUNNY_BASE_URL=https://legacy.example/v1\nSOFUNNY_API_KEY=legacy-key\nSOFUNNY_MODEL=gpt-image-2\n",
  });

  const config = resolveConfig({}, {
    ...fixture,
    processEnv: {},
  });

  assert.equal(config.baseUrl, "https://legacy.example");
  assert.equal(config.apiKey, "legacy-key");
  assert.equal(config.model, "gpt-image-2");
  assert.equal(config.sharedConfigExists, false);
});

test("rejects malformed shared config instead of silently falling back", () => {
  const fixture = makeConfigFixture({
    shared: "{broken",
    env: "SOFUNNY_API_KEY=legacy-key\n",
  });

  assert.throws(
    () => resolveConfig({}, { ...fixture, processEnv: {} }),
    /无法解析共享配置/,
  );
});

test("new shared config takes precedence over legacy env values", () => {
  const fixture = makeConfigFixture({
    shared: { default: { api_key: "new-key", base_url: "https://new.example" } },
    env: "SOFUNNY_API_KEY=legacy-key\nSOFUNNY_BASE_URL=https://legacy.example\n",
  });

  const config = resolveConfig({}, { ...fixture, processEnv: {} });

  assert.equal(config.apiKey, "new-key");
  assert.equal(config.baseUrl, "https://new.example");
});

test("routes Seedream models to their own protocol adapter", () => {
  assert.equal(getModelProfile("doubao-seedream-5-0-pro").protocol, "seedream");
  assert.equal(getModelProfile("doubao-seedream-5-0-lite").protocol, "seedream");
  assert.equal(getModelProfile("doubao-seedream-5-0-flash").protocol, "seedream");
  assert.equal(getModelProfile("doubao-seedream-5.0-flash").protocol, "seedream");
  assert.equal(getModelProfile("qwen-image-3.0-pro").protocol, "openai-images");
});

test("builds Seedream JSON for reference-image generation", () => {
  const fixture = path.join(os.tmpdir(), `seedream-input-${Date.now()}.png`);
  fs.writeFileSync(fixture, Buffer.from("fake-png"));
  try {
    const body = buildSeedreamBody({
      prompt: "a red kite",
      input: [fixture],
      imageSizeProvided: true,
      imageSize: "2K",
      responseFormat: "b64_json",
      watermark: "false",
    }, "doubao-seedream-5-0-pro");
    assert.equal(body.model, "doubao-seedream-5-0-pro");
    assert.equal(body.size, "2K");
    assert.equal(body.response_format, "b64_json");
    assert.equal(body.watermark, false);
    assert.match(body.image, /^data:image\/png;base64,/);
  } finally {
    fs.unlinkSync(fixture);
  }
});

test("enforces Seedream Pro and Lite capability boundaries", () => {
  assert.throws(
    () => buildSeedreamBody({ prompt: "test", input: [], layerDecomposition: "true" }, "doubao-seedream-5-0-lite"),
    /图层拆分仅支持 Seedream Pro/,
  );
  assert.throws(
    () => buildSeedreamBody({ prompt: "test", input: [], sequentialImageGeneration: "auto" }, "doubao-seedream-5-0-pro"),
    /组图模式仅支持 Seedream Lite/,
  );
});

test("parses Seedream group and layer metadata without dropping it", () => {
  const parsed = parseSeedreamResponse({
    created: 123,
    model: "doubao-seedream-5-0-pro",
    data: [
      { b64_json: "aGVsbG8=", size: "2048x2048", z_index: 0 },
      { url: "https://example.test/layer.png", name: "character", bounding_box: { absolute: [1, 2, 3, 4] } },
      { error: { code: "sensitive", message: "blocked" } },
    ],
    usage: { generated_images: 2 },
  });
  assert.equal(parsed.images.length, 2);
  assert.equal(parsed.images[1].name, "character");
  assert.deepEqual(parsed.images[1].boundingBox.absolute, [1, 2, 3, 4]);
  assert.equal(parsed.metadata.usage.generated_images, 2);
});

// Flash 与 Pro 共用同一段官方规格说明：1K/1.5K/2K 档位、最多 10 张参考图、
// 支持图层拆分。后端 relay/channel/volcengine 用 isSeedreamProLike 统一这两档，
// 这里的判据必须保持一致，否则 Skill 会在前端先拦下后端本来就接受的参数。
test("doubao-seedream-5-0-flash shares the Pro capability boundaries", () => {
  const fixture = path.join(os.tmpdir(), `seedream-flash-input-${Date.now()}.png`);
  fs.writeFileSync(fixture, Buffer.from("fake-png"));
  try {
    for (const size of ["1K", "1.5K", "2K"]) {
      assert.equal(
        buildSeedreamBody({ prompt: "a red kite", input: [], size }, "doubao-seedream-5-0-flash").size,
        size,
        `Flash 应接受 ${size} 尺寸档位`,
      );
    }
    assert.throws(
      () => buildSeedreamBody({ prompt: "a red kite", input: [], size: "4K" }, "doubao-seedream-5-0-flash"),
      /Seedream 的尺寸不支持/,
      "4K 属于 Lite 档位，Flash 不应接受",
    );

    const tenInputs = Array.from({ length: 10 }, () => fixture);
    assert.equal(buildSeedreamBody({ prompt: "a red kite", input: tenInputs }, "doubao-seedream-5-0-flash").image.length, 10);
    assert.throws(
      () => buildSeedreamBody({ prompt: "a red kite", input: [...tenInputs, fixture] }, "doubao-seedream-5-0-flash"),
      /最多支持 10 张参考图/,
    );

    assert.equal(
      buildSeedreamBody({ prompt: "a red kite", input: [fixture], layerDecomposition: "true" }, "doubao-seedream-5-0-flash")
        .layer_decomposition,
      true,
    );
    assert.throws(
      () => buildSeedreamBody({ prompt: "a red kite", input: [fixture, fixture], layerDecomposition: "true" }, "doubao-seedream-5-0-flash"),
      /只能传入一张参考图/,
    );

    assert.deepEqual(getSeedreamModelCapabilities("doubao-seedream-5-0-flash"), {
      protocol: "seedream",
      isPro: false,
      isLite: false,
      isFlash: true,
      maxInputs: 10,
    });
  } finally {
    fs.unlinkSync(fixture);
  }
});

// fast 提示词优化是 Flash 与 Pro 唯一的能力反向差异：官方明确 flash / lite / 4.5
// 都不支持，Pro 是唯一支持 fast 的。不要为了「和 Pro 一样」把它一起放开。
test("doubao-seedream-5-0-flash rejects fast mode and Lite-only features", () => {
  assert.equal(
    buildSeedreamBody({ prompt: "a red kite", input: [], optimizePromptMode: "standard" }, "doubao-seedream-5-0-flash")
      .optimize_prompt_options.mode,
    "standard",
  );
  assert.throws(
    () => buildSeedreamBody({ prompt: "a red kite", input: [], optimizePromptMode: "fast" }, "doubao-seedream-5-0-flash"),
    /不支持 fast 提示词优化/,
  );
  assert.throws(
    () => buildSeedreamBody({ prompt: "a red kite", input: [], sequentialImageGeneration: "auto" }, "doubao-seedream-5-0-flash"),
    /组图模式仅支持 Seedream Lite/,
  );
  assert.throws(
    () => buildSeedreamBody({ prompt: "a red kite", input: [], toolsWebSearch: true }, "doubao-seedream-5-0-flash"),
    /联网搜索工具仅支持 Seedream Lite/,
  );
});
