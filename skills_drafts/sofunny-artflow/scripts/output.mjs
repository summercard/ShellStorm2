// 输出契约：stdout 恰好一个 JSON（--stream 时 NDJSON），stderr 放进度与错误 JSON。
// 退出码：0 成功；1 CLI/用法/鉴权/网络错误；2 目标级失败（任务 failed / batch 部分失败）。

export class CliError extends Error {
  constructor(code, message, extra = {}) {
    super(message);
    this.code = code;
    this.extra = extra;
    this.exitCode = 1;
  }
}

export class TargetError extends Error {
  // 目标级失败（任务本身 failed 等）：数据走 stdout，退出码 2
  constructor(code, message, extra = {}) {
    super(message);
    this.code = code;
    this.extra = extra;
    this.exitCode = 2;
  }
}

export function emitJson(value) {
  process.stdout.write(JSON.stringify(value, null, 2) + "\n");
}

export function emitNdjson(value) {
  process.stdout.write(JSON.stringify(value) + "\n");
}

export function progress(line) {
  if (process.env.ARTFLOW_CLI_QUIET === "1") return;
  process.stderr.write(`${line}\n`);
}

export function emitError(err) {
  const payload = {
    error: {
      code: err.code || "UNKNOWN",
      message: err.message,
      ...(err.extra || {}),
    },
  };
  process.stderr.write(JSON.stringify(payload) + "\n");
}

// "30s" | "5m" | "4h" | 数字（秒）→ 毫秒
export function parseDuration(raw, def = undefined) {
  if (raw === undefined || raw === null || raw === "") return def;
  const text = String(raw).trim();
  const m = /^(\d+(?:\.\d+)?)(ms|s|m|h|d)?$/i.exec(text);
  if (!m) {
    if (/^\d+$/.test(text)) return Number(text) * 1000;
    throw new CliError("USAGE", `无效的时长格式：${raw}（支持 30s / 5m / 4h / 90d）`);
  }
  const n = Number(m[1]);
  const unit = (m[2] || "s").toLowerCase();
  const scale = { ms: 1, s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[unit];
  return n * scale;
}

export function formatDuration(ms) {
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m${s % 60 ? `${s % 60}s` : ""}`;
  const h = Math.floor(m / 60);
  return `${h}h${m % 60 ? `${m % 60}m` : ""}`;
}
