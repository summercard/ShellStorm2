// 全部命令实现。每个命令签名：async (ctx) => { exitCode, result }
// ctx = { client, flags, positionals, runtime, saveConfig, emitNdjson }

import fs from "node:fs";
import path from "node:path";
import * as nodeChildProcess from "node:child_process";
import { CliError, TargetError, emitNdjson, progress, parseDuration } from "./output.mjs";
import { getStr, getNum, getBool, hasFlag } from "./args.mjs";
import { decodeJwtExp, saveConfig } from "./config.mjs";
import {
  TYPE_SPECS, buildJobBody, materializeRawBody, readAsDataUrl, inferKind,
} from "./spec.mjs";
import { waitForJobs, summarize, describeJob, isFailed } from "./jobs.mjs";

const DEFAULT_WAIT_TIMEOUT = parseDuration("4h");

function requirePositional(positionals, index, name, usage) {
  const value = positionals[index];
  if (!value) {
    throw new CliError("USAGE", `缺少 ${name}${usage ? `（用法：${usage}）` : ""}`);
  }
  return value;
}

async function readStdinAll() {
  if (process.stdin.isTTY) {
    throw new CliError("USAGE", "stdin 不是管道，无法读取（应通过管道或 --json-file 传入）");
  }
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function requireToken(ctx) {
  if (!ctx.client.token) {
    throw new CliError("AUTH", "未登录，请先运行 login --feishu", {
      hint: "登录后 JWT 自动保存到本机配置（30 天有效），与网页飞书登录同账号",
    });
  }
}

// 403 = 非本人任务且非超管：补充权限口径提示，避免 AI 反复重试。
function rethrowPermissionError(err) {
  if (err && err.status === 403 && !err.hint) {
    err.hint = "非本人任务且非超管无权操作；whoami 可确认当前身份与角色";
  }
  throw err;
}

// ---- 登录与凭据 ----

export async function cmdLogout(ctx) {
  saveConfig({ token: "", username: "" });
  return { exitCode: 0, result: { ok: true, message: "已清除本地凭据" } };
}

// 飞书设备码登录（RFC 8628）：打开授权链接 → 用户飞书确认 → 轮询换平台 JWT。
// 与网页飞书登录同一 app → 同一 open_id → 同一平台账号。
export async function cmdLogin(ctx) {
  const start = await ctx.client.feishuDeviceStart();
  const verifyUrl = start.verification_uri_complete || start.verification_uri;
  progress(`[login] 请在浏览器打开以下链接，用飞书确认登录：`);
  progress(`  ${verifyUrl}`);
  if (start.user_code) progress(`[login] 用户码：${start.user_code}（${start.expires_in}s 内完成）`);
  tryOpenBrowser(verifyUrl);

  const deadline = Date.now() + (start.expires_in || 600) * 1000;
  let interval = (start.interval || 5) * 1000;
  let resp = null;
  while (true) {
    if (Date.now() > deadline) {
      throw new CliError("AUTH", "飞书登录超时（未在有效期内确认），请重新运行 login --feishu");
    }
    await ctx.client.sleeper(interval);
    try {
      resp = await ctx.client.feishuDevicePoll(start.device_code);
    } catch (err) {
      if (err.status === 410) {
        throw new CliError("AUTH", "登录码已过期，请重新运行 login --feishu");
      }
      if (err.status === 400) {
        throw new CliError("AUTH", "用户拒绝了登录授权");
      }
      throw err;
    }
    if (resp && resp.status === "ok") break;
    if (resp && resp.slow_down) interval += 5000;
    progress(`[login] 等待在飞书完成确认…`);
  }

  const token = resp.token;
  if (!token) throw new CliError("AUTH", "登录响应中没有 token");
  ctx.client.setToken(token);
  const me = resp.user || {};
  saveConfig({ base_url: ctx.runtime.baseUrl, token, username: me.username || "" });
  return {
    exitCode: 0,
    result: {
      username: me.username || "",
      display_name: me.displayName || "",
      role: me.role,
      token_expires_at: new Date(decodeJwtExp(token) || Date.now() + 30 * 86400_000).toISOString(),
      hint: "飞书登录成功（与网页飞书登录同账号）；JWT 已保存到本机 config（30 天有效），过期重新 login --feishu",
    },
  };
}

function tryOpenBrowser(url) {
  try {
    const { execFile } = nodeChildProcess;
    const cmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
    execFile(cmd, [url], () => {});
  } catch {
    // 无 GUI 环境忽略，用户按 stderr 打印的链接手动打开
  }
}

export async function cmdWhoami(ctx) {
  requireToken(ctx);
  const me = await ctx.client.me();
  const exp = decodeJwtExp(ctx.client.token);
  return {
    exitCode: 0,
    result: {
      ...me,
      token_expires_at: exp ? new Date(exp).toISOString() : "unknown",
    },
  };
}

// ---- 诊断与信息 ----

export async function cmdDoctor(ctx) {
  const checks = [];

  const push = (name, ok, detail) => checks.push({ name, ok, detail });

  try {
    const health = await ctx.client.health();
    push("base_url 可达（canvas-lab /health）", true, `${ctx.client.baseUrl}`);
    push("canvas-lab 健康", Boolean(health && health.ok), health && health.ok ? "ok" : JSON.stringify(health));
  } catch (err) {
    push("base_url 可达（canvas-lab /health）", false, err.message);
  }

  if (!ctx.client.token) {
    push("鉴权", false, "未登录（请先运行 login --feishu）");
  } else {
    try {
      const me = await ctx.client.me();
      push("鉴权", true, `用户：${me.username}${me.isSuperAdmin ? "（超管）" : ""}`);
    } catch (err) {
      push("鉴权", false, err.message);
    }
  }

  try {
    const registry = await ctx.client.registry();
    const types = Object.keys((registry && registry.types) || {});
    push("任务注册表", true, types.length ? `${types.length} 种节点类型` : "已读取");
  } catch (err) {
    push("任务注册表", false, err.message);
  }

  const ok = checks.every((c) => c.ok);
  return { exitCode: ok ? 0 : 1, result: { ok, checks, base_url: ctx.client.baseUrl } };
}

export async function cmdTypes(ctx) {
  const type = ctx.positionals[0];
  if (!type) {
    const types = Object.entries(TYPE_SPECS).map(([name, spec]) => ({
      type: name,
      label: spec.label,
      media_inputs: Object.keys(spec.mediaFields),
      required: ["--prompt"],
    }));
    return {
      exitCode: 0,
      result: {
        types,
        note: "其他平台类型（seedance/happy_house/image2_real 等）可用 submit --json 原始模式提交，参数见平台文档或 GET /api/canvas-lab/v2/registry",
      },
    };
  }
  const spec = TYPE_SPECS[type];
  if (!spec) {
    throw new CliError("VALIDATION", `未知类型：${type}（当前友好模式支持 ${Object.keys(TYPE_SPECS).join(" / ")}）`, {
      hint: "其他类型用 submit --json 原始模式",
    });
  }
  return {
    exitCode: 0,
    result: {
      type,
      label: spec.label,
      enums: spec.enums || {},
      media_inputs: Object.entries(spec.mediaFields).map(([field, info]) => ({
        field,
        kind: info.kind,
        multiple: Boolean(info.multiple),
        accepts: "http(s):// URL / 服务器路径 / @本地文件（自动上传）",
      })),
      required: ["--prompt"],
      example: `node \${SKILL_DIR}/scripts/artflow.mjs submit --type ${type} --prompt "描述画面"`,
    },
  };
}

// ---- 上传与提交 ----

export async function cmdUpload(ctx) {
  requireToken(ctx);
  const files = ctx.positionals;
  if (!files.length) throw new CliError("USAGE", "upload <文件...>");
  const kindOverride = getStr(ctx.flags, "kind", "auto");
  const uploads = [];
  for (const file of files) {
    const kind = kindOverride !== "auto" ? kindOverride : inferKind(file);
    if (!kind) {
      throw new CliError("VALIDATION", `无法识别素材类型（扩展名未知）：${file}`, { hint: "用 --kind image|video|audio 指定" });
    }
    const dataUrl = await readAsDataUrl(file);
    const resp = await ctx.client.uploadMedia(file, kind, dataUrl);
    uploads.push({
      file,
      kind,
      url: (resp && (resp.local_url || resp.url)) || "",
      local_url: (resp && resp.local_url) || "",
      public_url: (resp && resp.public_url) || "",
      size: fs.statSync(file).size,
    });
    progress(`[upload] ${file} → ${uploads[uploads.length - 1].url}`);
  }
  return { exitCode: 0, result: { uploads } };
}

async function buildSubmitBody(ctx) {
  const flags = ctx.flags;
  if (hasFlag(flags, "json") || hasFlag(flags, "json-file")) {
    let raw;
    if (hasFlag(flags, "json-file")) {
      const file = String(getStr(flags, "json-file"));
      if (file === "-") raw = await readStdinAll();
      else raw = fs.readFileSync(file, "utf8");
    } else {
      const inline = String(getStr(flags, "json"));
      raw = inline === "-" ? await readStdinAll() : inline;
    }
    let body;
    try {
      body = JSON.parse(raw);
    } catch (err) {
      throw new CliError("VALIDATION", `--json 内容不是合法 JSON：${err.message}`);
    }
    if (!body || typeof body !== "object" || !body.type) {
      throw new CliError("VALIDATION", "原始模式 body 必须是含 type 字段的 JSON 对象");
    }
    return materializeRawBody(body, ctx.mediaHelpers());
  }
  const type = String(getStr(flags, "type", "") || "");
  if (!type) {
    throw new CliError("USAGE", "submit 需要 --type（或用 --json/--json-file 原始模式）", {
      hint: "先运行 types 查看类型与参数",
    });
  }
  return buildJobBody(type, flags, ctx.mediaHelpers());
}

export async function cmdSubmit(ctx) {
  if (!getBool(ctx.flags, "dry-run", false)) {
    requireToken(ctx);
  }
  const body = await buildSubmitBody(ctx);
  if (getBool(ctx.flags, "dry-run", false)) {
    return { exitCode: 0, result: { dry_run: true, body } };
  }
  const job = await ctx.client.createJob(body);
  progress(`[submit] ${describeJob(job)}`);
  return { exitCode: 0, result: summarize(job) || job };
}

// ---- 任务查询与操作 ----

export async function cmdStatus(ctx) {
  requireToken(ctx);
  const ids = ctx.positionals;
  if (!ids.length) throw new CliError("USAGE", "status <jobId...>");
  const jobs = [];
  let anyMissing = false;
  for (const id of ids) {
    try {
      const job = await ctx.client.getJob(id);
      jobs.push(summarize(job));
    } catch (err) {
      anyMissing = true;
      jobs.push({
        id,
        status: "not_found",
        error: err.status === 404 ? "任务不存在（超过保留条数被清理，或已被删除）" : err.message,
      });
    }
  }
  return { exitCode: anyMissing ? 2 : 0, result: { jobs } };
}

export async function cmdList(ctx) {
  requireToken(ctx);
  const mine = getBool(ctx.flags, "mine", false);
  const resp = await ctx.client.listJobs({ mine });
  let jobs = (resp && resp.jobs) || [];
  const type = getStr(ctx.flags, "type");
  const status = getStr(ctx.flags, "status");
  if (type) jobs = jobs.filter((j) => j.type === type);
  if (status) jobs = jobs.filter((j) => String(j.status).toLowerCase() === status.toLowerCase());
  // 服务端 mine=1 已按 owner_user_id 过滤；本地按用户名再滤一遍兜底旧服务端。
  if (mine && ctx.runtime.username) {
    jobs = jobs.filter((j) => j.owner_username === ctx.runtime.username);
  }
  const limit = getNum(ctx.flags, "limit", 20);
  jobs = jobs.slice(0, limit);
  return { exitCode: 0, result: { count: jobs.length, jobs: jobs.map(summarize) } };
}

export async function cmdWait(ctx) {
  requireToken(ctx);
  const ids = ctx.positionals;
  if (!ids.length) throw new CliError("USAGE", "wait <jobId...> [--timeout 4h] [--download <dir>]");
  const timeoutMs = parseDuration(getStr(ctx.flags, "timeout"), DEFAULT_WAIT_TIMEOUT);
  const pollMs = parseDuration(getStr(ctx.flags, "poll-interval"), 5000);
  const downloadDir = getStr(ctx.flags, "download");

  const { jobs, pending } = await waitForJobs(ctx.client, ids, {
    timeoutMs,
    pollMs,
    onTick: (job) => progress(`[wait] ${describeJob(job)}${isFailed(job) && job.error ? ` — ${job.error}` : ""}`),
  });

  const results = ids.map((id) => summarize(jobs.get(id) || { id, status: "pending" }));
  let downloads = [];
  if (downloadDir) {
    downloads = await downloadJobs(ctx.client, results.filter((j) => j.status === "succeeded" && j.media_url), downloadDir, getBool(ctx.flags, "no-clobber", false));
  }

  const anyFailed = results.some((j) => isFailed(j) || j.status === "not_found");
  const anyPending = pending.length > 0 || results.some((j) => j.status === "pending");
  const exitCode = anyFailed || anyPending ? 2 : 0;
  const output = { jobs: results };
  if (anyPending) output.pending = pending.length ? pending : results.filter((j) => j.status === "pending").map((j) => j.id);
  if (downloads.length) output.downloads = downloads;
  return { exitCode, result: output };
}

export async function cmdCancel(ctx) {
  requireToken(ctx);
  const id = requirePositional(ctx.positionals, 0, "jobId", "cancel <jobId>");
  try {
    const resp = await ctx.client.cancelJob(id);
    return { exitCode: 0, result: resp };
  } catch (err) {
    rethrowPermissionError(err);
  }
}

export async function cmdRerun(ctx) {
  requireToken(ctx);
  const id = requirePositional(ctx.positionals, 0, "jobId", "rerun <jobId>");
  try {
    const job = await ctx.client.rerunJob(id);
    return { exitCode: 0, result: summarize(job) || job };
  } catch (err) {
    rethrowPermissionError(err);
  }
}

export async function cmdRecover(ctx) {
  requireToken(ctx);
  const id = requirePositional(ctx.positionals, 0, "jobId", "recover <jobId>");
  const resp = await ctx.client.recoverJob(id);
  return { exitCode: 0, result: resp };
}

export async function cmdDelete(ctx) {
  requireToken(ctx);
  const id = requirePositional(ctx.positionals, 0, "jobId", "delete <jobId>");
  try {
    const resp = await ctx.client.deleteJob(id);
    return { exitCode: 0, result: resp };
  } catch (err) {
    rethrowPermissionError(err);
  }
}

async function downloadJobs(client, jobSummaries, outDir, noClobber) {
  fs.mkdirSync(outDir, { recursive: true });
  const downloads = [];
  for (const job of jobSummaries) {
    const mediaUrl = job.media_url || "";
    if (!mediaUrl) continue;
    const ext = path.extname(new URL(mediaUrl, client.baseUrl).pathname) || ".mp4";
    let dest = path.join(outDir, `${job.id}${ext}`);
    if (noClobber && fs.existsSync(dest)) {
      dest = path.join(outDir, `${job.id}-${Date.now()}${ext}`);
    }
    progress(`[download] ${job.id} → ${dest}`);
    const saved = await client.downloadToFile(mediaUrl, dest);
    downloads.push({ job_id: job.id, path: saved.path, size: saved.size });
  }
  return downloads;
}

export async function cmdDownload(ctx) {
  requireToken(ctx);
  const ids = ctx.positionals;
  if (!ids.length) throw new CliError("USAGE", "download <jobId...> --out-dir <dir>");
  const outDir = String(getStr(ctx.flags, "out-dir", ".") || ".");
  const summaries = [];
  for (const id of ids) {
    const job = await ctx.client.getJob(id);
    summaries.push(summarize(job));
  }
  const target = summaries.filter((j) => j.media_url);
  if (!target.length) {
    throw new TargetError("JOB_FAILED", "没有可下载的成品（media_url 为空，任务可能未成功）", { jobs: summaries });
  }
  const downloads = await downloadJobs(ctx.client, target, outDir, getBool(ctx.flags, "no-clobber", false));
  return { exitCode: 0, result: { downloads, jobs: summaries } };
}

// ---- 批量 ----

function readJsonl(file) {
  const raw = file === "-" ? fs.readFileSync(0, "utf8") : fs.readFileSync(file, "utf8");
  const lines = [];
  raw.split("\n").forEach((text, index) => {
    const lineNo = index + 1;
    const trimmed = text.trim();
    if (!trimmed || trimmed.startsWith("#")) return;
    try {
      const body = JSON.parse(trimmed);
      if (!body || typeof body !== "object" || !body.type) {
        lines.push({ lineNo, body: null, error: "每行必须是含 type 字段的 JSON 对象" });
      } else {
        lines.push({ lineNo, body, error: null });
      }
    } catch (err) {
      lines.push({ lineNo, body: null, error: `JSON 解析失败：${err.message}` });
    }
  });
  return lines;
}

async function runPool(items, concurrency, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  const runners = Array.from({ length: Math.max(1, Math.min(concurrency, items.length)) }, async () => {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await worker(items[index], index);
    }
  });
  await Promise.all(runners);
  return results;
}

export async function cmdBatch(ctx) {
  requireToken(ctx);
  const file = requirePositional(ctx.positionals, 0, "jobs.jsonl 文件", "batch <jobs.jsonl> [--wait] [--out results.jsonl]");
  const flags = ctx.flags;
  const doWait = getBool(flags, "wait", false);
  const timeoutMs = parseDuration(getStr(flags, "timeout"), DEFAULT_WAIT_TIMEOUT);
  const pollMs = parseDuration(getStr(flags, "poll-interval"), 5000);
  const concurrency = Math.max(1, getNum(flags, "concurrency", 2));
  const failFast = getBool(flags, "fail-fast", false);
  const stream = getBool(flags, "stream", false);
  const outFile = getStr(flags, "out");

  const lines = readJsonl(file);
  if (!lines.length) throw new CliError("USAGE", "文件里没有有效的任务行");

  const outStream = outFile ? fs.createWriteStream(outFile, { flags: "a" }) : null;
  const writeOut = (value) => {
    if (outStream) outStream.write(JSON.stringify(value) + "\n");
  };
  const emit = (value) => {
    if (stream) emitNdjson(value);
  };

  const jobs = [];
  let stopped = false;

  await runPool(lines, concurrency, async (line, index) => {
    if (stopped) return;
    if (line.error || !line.body) {
      const record = { line_no: line.lineNo, status: "submit_failed", error: line.error };
      jobs[index] = record;
      emit({ event: "submit_failed", ...record });
      writeOut(record);
      if (failFast) stopped = true;
      return;
    }
    try {
      const body = await materializeRawBody(line.body, ctx.mediaHelpers());
      const job = await ctx.client.createJob(body);
      const record = { line_no: line.lineNo, status: "submitted", id: job.id, type: job.type };
      jobs[index] = record;
      emit({ event: "submitted", ...record });
      writeOut(record);
      progress(`[batch] L${line.lineNo} 提交成功 ${job.id}`);
    } catch (err) {
      const record = {
        line_no: line.lineNo,
        status: "submit_failed",
        error: err.message,
        code: err.code || "HTTP",
      };
      jobs[index] = record;
      emit({ event: "submit_failed", ...record });
      writeOut(record);
      progress(`[batch] L${line.lineNo} 提交失败：${err.message}`);
      if (failFast) stopped = true;
    }
  });

  const submittedIds = jobs.filter((j) => j && j.id).map((j) => j.id);
  const failedSubmit = jobs.filter((j) => j && j.status === "submit_failed").length;

  let finalJobs = [...jobs];
  let pending = [];
  if (doWait && submittedIds.length && !stopped) {
    const { jobs: finished, pending: pendingIds } = await waitForJobs(ctx.client, submittedIds, {
      timeoutMs,
      pollMs,
      onTick: (job) => {
        progress(`[batch] ${describeJob(job)}`);
        const record = { id: job.id, status: job.status, media_url: (job.result && job.result.media_url) || "", error: job.error || "" };
        emit({ event: "done", ...record });
        writeOut(record);
      },
    });
    finalJobs = jobs.map((entry) => {
      if (!entry || !entry.id) return entry;
      const job = finished.get(entry.id);
      if (!job) return { ...entry, status: "pending" };
      return {
        ...entry,
        status: job.status,
        media_url: (job.result && job.result.media_url) || "",
        error: job.error || "",
      };
    });
    pending = pendingIds;
  }

  if (outStream) await new Promise((resolve) => outStream.end(resolve));

  const summary = {
    total: lines.length,
    submitted: submittedIds.length,
    failed_submit: failedSubmit,
    skipped: finalJobs.filter((j) => !j).length,
    succeeded: finalJobs.filter((j) => j && j.status === "succeeded").length,
    failed: finalJobs.filter((j) => j && (isFailed(j) || j.status === "submit_failed")).length,
    pending: pending.length,
  };

  let exitCode = 0;
  if (summary.submitted === 0) exitCode = 1;
  else if (summary.failed > 0 || summary.pending > 0 || summary.skipped > 0) exitCode = 2;

  return {
    exitCode,
    result: {
      summary,
      pending,
      jobs: finalJobs,
      ...(outFile ? { out_file: outFile } : {}),
    },
  };
}
