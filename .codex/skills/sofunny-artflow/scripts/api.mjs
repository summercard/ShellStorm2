// ArtFlow HTTP 客户端：单 base URL 走前端 rewrites（/api/artflow/* → 33501，/api/canvas-lab/* → 33401）
// 429/5xx 指数退避（尊重 Retry-After），401 上抛 AUTH_EXPIRED，网络错误上抛 NETWORK。

import { CliError, progress } from "./output.mjs";

const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);
const MAX_RETRY_DELAY_MS = 30_000;

export class HttpError extends CliError {
  constructor(status, body, path) {
    const message =
      (body && (typeof body.detail === "string" ? body.detail : body.error)) || `HTTP ${status}`;
    super("HTTP", message, { status, path, body });
    this.status = status;
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class ArtFlowClient {
  constructor({ baseUrl, token = "", fetchImpl = fetch, sleeper = sleep, retries = 5, requestTimeoutMs = 60_000 }) {
    this.baseUrl = baseUrl;
    this.token = token;
    this.fetchImpl = fetchImpl;
    this.sleeper = sleeper;
    this.retries = retries;
    this.requestTimeoutMs = requestTimeoutMs;
  }

  setToken(token) {
    this.token = token;
  }

  buildUrl(path) {
    return `${this.baseUrl}${path}`;
  }

  async request(method, path, { body, auth = true, timeoutMs, retries } = {}) {
    const maxRetries = retries ?? this.retries;
    const timeout = timeoutMs ?? this.requestTimeoutMs;
    let attempt = 0;
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const headers = {};
      if (body !== undefined) headers["Content-Type"] = "application/json";
      if (auth && this.token) headers.Authorization = `Bearer ${this.token}`;
      let resp;
      try {
        resp = await this.fetchImpl(this.buildUrl(path), {
          method,
          headers,
          body: body === undefined ? undefined : JSON.stringify(body),
          signal: AbortSignal.timeout(timeout),
        });
      } catch (err) {
        // AbortSignal.timeout 超时在 Node 里是 TimeoutError（手动 abort 才是 AbortError）
        if (err.name === "AbortError" || err.name === "TimeoutError") {
          // 超时不重试：POST 可能已在服务端生效，重放会重复建单
          throw new CliError("NETWORK", `请求超时（${Math.round(timeout / 1000)}s）：${method} ${path}`, {
            hint: "可用 --timeout-per-request 调大",
          });
        }
        if (attempt < maxRetries) {
          await this.backoff(attempt);
          attempt += 1;
          continue;
        }
        throw new CliError("NETWORK", `无法连接 ${this.baseUrl}：${err.message}`, {
          hint: "检查网络 / base URL 是否可达（doctor 可自检）",
        });
      }

      if (resp.status === 401 && auth) {
        const payload = await safeJson(resp);
        throw new CliError(
          "AUTH_EXPIRED",
          (payload && (payload.detail || payload.error)) || "登录已失效",
          { hint: "登录已失效（JWT 30 天过期），请重新运行 login --feishu" },
        );
      }

      if (RETRYABLE_STATUS.has(resp.status) && attempt < maxRetries) {
        await this.backoff(attempt, resp);
        attempt += 1;
        continue;
      }

      if (!resp.ok) {
        throw new HttpError(resp.status, await safeJson(resp), path);
      }
      return safeJson(resp);
    }
  }

  async backoff(attempt, resp = null) {
    let delay = Math.min(1000 * 2 ** attempt, MAX_RETRY_DELAY_MS);
    if (resp) {
      const retryAfter = Number(resp.headers.get("retry-after"));
      if (Number.isFinite(retryAfter) && retryAfter > 0) {
        delay = Math.min(retryAfter * 1000, MAX_RETRY_DELAY_MS);
      }
    }
    delay += Math.floor(Math.random() * 250);
    if (resp) {
      progress(`[retry] HTTP ${resp.status}，${delay}ms 后重试（第 ${attempt + 1} 次）`);
    } else {
      progress(`[retry] 网络错误，${delay}ms 后重试（第 ${attempt + 1} 次）`);
    }
    await this.sleeper(delay);
  }

  // ---- auth（经前端 rewrite：/api/artflow/* → 33501 顶层路由）----
  async me() {
    return this.request("GET", "/api/artflow/auth/me");
  }

  // ---- 飞书设备码登录（RFC 8628，无需凭据头）----
  async feishuDeviceStart() {
    return this.request("POST", "/api/artflow/auth/feishu/device/start", {
      body: {},
      auth: false,
      retries: 1,
    });
  }

  async feishuDevicePoll(deviceCode) {
    return this.request("POST", "/api/artflow/auth/feishu/device/poll", {
      body: { device_code: deviceCode },
      auth: false,
      retries: 1,
    });
  }

  // ---- canvas-lab v2（/api/canvas-lab/v2/* → 33401）----
  async health() {
    return this.request("GET", "/api/canvas-lab/v2/health", { auth: false, retries: 1 });
  }

  async registry() {
    return this.request("GET", "/api/canvas-lab/v2/registry", { auth: false, retries: 1 });
  }

  async createJob(body, { timeoutMs } = {}) {
    return this.request("POST", "/api/canvas-lab/v2/jobs", { body, timeoutMs });
  }

  async listJobs({ mine = false } = {}) {
    // v2 任务接口要求登录；mine=1 服务端按归属过滤（旧服务端忽略该参数）。
    const query = mine ? "?mine=1" : "";
    return this.request("GET", `/api/canvas-lab/v2/jobs${query}`);
  }

  async getJob(id) {
    return this.request("GET", `/api/canvas-lab/v2/jobs/${encodeURIComponent(id)}`);
  }

  async cancelJob(id) {
    return this.request("POST", `/api/canvas-lab/v2/jobs/${encodeURIComponent(id)}/cancel`, {
      body: {},
    });
  }

  async rerunJob(id) {
    return this.request("POST", `/api/canvas-lab/v2/jobs/${encodeURIComponent(id)}/rerun`, {
      body: {},
    });
  }

  async recoverJob(id) {
    return this.request("POST", `/api/canvas-lab/v2/jobs/${encodeURIComponent(id)}/recover`, {
      body: {},
    });
  }

  async deleteJob(id) {
    return this.request("DELETE", `/api/canvas-lab/v2/jobs/${encodeURIComponent(id)}`);
  }

  // ---- 上传：{filename, display_name, data_url}，返回 {local_url, public_url, ...} ----
  async uploadMedia(filePath, kind, dataUrl) {
    const filename = filePath.split("/").pop();
    return this.request("POST", `/api/canvas-lab/uploads/${encodeURIComponent(kind)}`, {
      body: { filename, display_name: filename, data_url: dataUrl },
      timeoutMs: 300_000,
      retries: 2,
    });
  }

  async downloadToFile(url, destPath) {
    const target = /^https?:\/\//i.test(url) ? url : this.buildUrl(url);
    const resp = await this.fetchImpl(target, { signal: AbortSignal.timeout(600_000) });
    if (!resp.ok) throw new HttpError(resp.status, await safeJson(resp), target);
    const buffer = Buffer.from(await resp.arrayBuffer());
    const fs = await import("node:fs");
    fs.writeFileSync(destPath, buffer);
    return { size: buffer.length, path: destPath, url: target };
  }
}

async function safeJson(resp) {
  try {
    return await resp.json();
  } catch {
    return null;
  }
}
