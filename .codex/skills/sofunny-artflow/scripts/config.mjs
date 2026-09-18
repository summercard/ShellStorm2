// 配置与凭据：~/.artflow-cli/config.json（chmod 600）
// 所有 env 一律 ARTFLOW_CLI_ 前缀——canvas-lab 容器内 ARTFLOW_BASE_URL 指向后端，同名会冲突。

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { CliError } from "./output.mjs";

export const DEFAULT_BASE_URL = "https://artflow.hnfunny.com";

export function configPath() {
  if (process.env.ARTFLOW_CLI_CONFIG) return process.env.ARTFLOW_CLI_CONFIG;
  return path.join(os.homedir(), ".artflow-cli", "config.json");
}

export function loadConfig() {
  const file = configPath();
  try {
    const raw = fs.readFileSync(file, "utf8");
    const data = JSON.parse(raw);
    return typeof data === "object" && data !== null ? data : {};
  } catch (err) {
    if (err.code === "ENOENT") return {};
    throw new CliError("USAGE", `配置文件不可读（${file}）：${err.message}`);
  }
}

export function saveConfig(patch) {
  const merged = { ...loadConfig(), ...patch };
  const file = configPath();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(merged, null, 2) + "\n", { mode: 0o600 });
  fs.renameSync(tmp, file);
  try {
    fs.chmodSync(file, 0o600);
  } catch {
    // 某些文件系统不支持 chmod，尽力而为
  }
  return merged;
}

// 解析运行时：base_url 优先级 flag > env > saved config > 默认；
// 凭据只来自 saved config（login --feishu 写入），不再支持 env/flag 分发
export function resolveRuntime(flags = {}) {
  const saved = loadConfig();
  const baseUrl = normalizeBaseUrl(
    flags.baseUrl
      || process.env.ARTFLOW_CLI_BASE_URL
      || saved.base_url
      || DEFAULT_BASE_URL,
  );
  const token = (typeof saved.token === "string" ? saved.token : "") || "";
  const username =
    flags.username
    || process.env.ARTFLOW_CLI_USERNAME
    || (typeof saved.username === "string" ? saved.username : "")
    || "";
  return { baseUrl, token, username };
}

export function normalizeBaseUrl(url) {
  let text = String(url || "").trim().replace(/\/+$/, "");
  if (!text) return DEFAULT_BASE_URL;
  if (!/^https?:\/\//i.test(text)) text = `http://${text}`;
  return text;
}

// 无依赖解码 JWT payload.exp（秒级时间戳）
export function decodeJwtExp(token) {
  if (typeof token !== "string" || !token.includes(".")) return null;
  try {
    const part = token.split(".")[1];
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
    const json = JSON.parse(Buffer.from(b64, "base64").toString("utf8"));
    const exp = Number(json.exp);
    return Number.isFinite(exp) ? exp * 1000 : null;
  } catch {
    return null;
  }
}
