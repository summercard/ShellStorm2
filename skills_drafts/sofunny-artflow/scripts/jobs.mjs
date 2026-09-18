// 任务等待与摘要：轮询 GET /v2/jobs（单请求覆盖最近 120 条），缺失 id 回退逐个 GET /jobs/:id

import { progress, formatDuration } from "./output.mjs";

export const TERMINAL_STATUSES = new Set(["succeeded", "failed", "canceled"]);
export const FAILED_STATUSES = new Set(["failed", "error", "cancelled", "canceled", "timeout"]);

export function isTerminal(job) {
  return TERMINAL_STATUSES.has(String(job && job.status).toLowerCase());
}

export function isFailed(job) {
  return FAILED_STATUSES.has(String(job && job.status).toLowerCase());
}

export function summarize(job) {
  if (!job) return null;
  const result = job.result || {};
  const summary = {
    id: job.id,
    job_no: job.job_no,
    type: job.type,
    status: job.status,
    progress: job.progress,
    message: job.message || "",
    error: job.error || "",
    media_url: result.media_url || "",
    owner_username: job.owner_username || "",
    created_at: job.created_at || "",
    updated_at: job.updated_at || "",
  };
  if (job.queue_position !== undefined && job.queue_position !== null) {
    summary.queue_position = job.queue_position;
  }
  if (job.generation_seconds !== undefined && job.generation_seconds !== null) {
    summary.generation_seconds = job.generation_seconds;
  }
  if (job.wait_seconds !== undefined && job.wait_seconds !== null) {
    summary.wait_seconds = job.wait_seconds;
  }
  return summary;
}

export function describeJob(job) {
  const parts = [job.id, job.status];
  if (typeof job.progress === "number") parts.push(`${job.progress}%`);
  if (typeof job.queue_position === "number" && job.queue_position > 0) parts.push(`queue#${job.queue_position}`);
  return parts.join(" ");
}

// 轮询直到全部终态或超时。返回 { jobs: Map<id, job>, pending: string[], notFound: string[] }
export async function waitForJobs(client, ids, { timeoutMs, pollMs = 5000, onTick, sleeper, startedAt = Date.now() } = {}) {
  const sleep = sleeper || ((ms) => new Promise((r) => setTimeout(r, ms)));
  const targets = [...new Set(ids)];
  const results = new Map();
  const notFound = new Set();
  const deadline = startedAt + timeoutMs;
  let firstTick = true;

  while (true) {
    const remaining = targets.filter((id) => !results.has(id));
    if (remaining.length === 0) break;

    // 列表一次覆盖多个 id；不在列表里的再逐个查
    let list = [];
    try {
      const resp = await client.listJobs();
      list = (resp && resp.jobs) || [];
    } catch {
      // 列表失败不致命，逐个查询兜底
    }
    const byId = new Map(list.map((job) => [job.id, job]));
    for (const id of remaining) {
      let job = byId.get(id);
      if (!job) {
        try {
          job = await client.getJob(id);
        } catch (err) {
          if (err.status === 404) {
            notFound.add(id);
            results.set(id, { id, status: "not_found", error: "任务不存在（可能已被清理或删除）" });
            continue;
          }
          throw err;
        }
      }
      if (job && isTerminal(job)) {
        results.set(id, job);
        if (onTick) onTick(job);
      }
    }

    const stillWaiting = targets.filter((id) => !results.has(id));
    if (stillWaiting.length === 0) break;

    if (firstTick) {
      for (const job of list) {
        if (targets.includes(job.id) && !isTerminal(job)) {
          progress(`[wait] ${describeJob(job)}`);
        }
      }
      firstTick = false;
    }

    if (Date.now() >= deadline) {
      return { jobs: results, pending: stillWaiting, notFound: [...notFound] };
    }
    await sleep(Math.min(pollMs, Math.max(deadline - Date.now(), 0)));
  }

  const pending = targets.filter((id) => !results.has(id));
  return { jobs: results, pending, notFound: [...notFound], elapsedMs: Date.now() - startedAt };
}

export { formatDuration };
