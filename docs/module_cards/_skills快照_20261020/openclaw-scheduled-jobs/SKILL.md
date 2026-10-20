---
name: openclaw-scheduled-jobs
description: Use when setting up, test-firing, debugging, or **rewriting an existing** time-based OpenClaw automation — a recurring collection/reminder/report that runs an agent turn on a schedule and delivers it to a chat, a one-shot "check back later" job, or re-pointing/retiming/re-prompting one already created — i.e. `automations` jobs driven by cron/every/at rather than by a change condition. Covers the `delivery`/`failureAlert` field placement that makes `add` fail, the partial-`update` trap where `payload` is replaced whole, forcing a first run, and how to verify a run when the job's run history comes back empty. Also covers the same job when it lives in another desktop app's own SQLite job table (e.g. WorkBuddy `automations`) instead of in OpenClaw, and a multi-hop chain (app job → OpenClaw collector → delivered report) where raising what the report says means changing every prompt in the chain, not just the reporter's.
---

# Author and Verify a Scheduled OpenClaw Automation

## When
- "每晚 23:00 收一遍，第二天早上 08:00 发给我" — a recurring job whose agent turn produces something and delivers it to a chat.
- An existing job must be **retimed, re-pointed, or re-prompted** ("把总结改到 22:30", "提示词写得具体些") — same `jobId`, in-place `update`.
- A one-shot "过 N 分钟回来看结果 / 提醒我" job.
- A job you created seems not to have run, or `automations runs` returns nothing.

## Key rules
- **`failureAlert` is a top-level job field, not part of `delivery`.** Placing it inside `delivery` fails the whole `add` with `invalid cron.add params: at /delivery: unexpected property 'failureAlert'; at /delivery/mode: must be equal to constant; at /delivery: must have required property 'to'`. `delivery` is exactly `{mode, to}`: `mode` a fixed value (`announce` posts the job's own output to that chat, `none` runs silently), `to` an explicit target (`user:<open_id>` / `chat:<chat_id>`).
- **`schedule` is `{kind:"cron", expr, tz}` / `{kind:"every", everyMs}` / `{kind:"at", at:<ISO>}`.** Give cron a `tz` (`Asia/Shanghai` here) and give the one-shot its full offset (`2026-10-17T01:42:00+08:00`).
- **An `at` schedule echoes back in UTC** — a job requested for `+08:00 01:42` reports `"at":"2026-10-16T17:42:00.000Z"`. Same instant, not a wrong time.
- **`deleteAfterRun:true` makes a one-shot disposable** — the right shape for a self-check ("verify the 23:00 job wrote its files, then report"), which removes itself after the run.
- **`automations runs` can be empty for a run that really happened** (`{"entries": [], "total": 0}` immediately after a forced run). Do not read that as "never ran" — verify by evidence.
- **`sessionTarget`**: `isolated` for a standalone job that reports through `delivery`; `current` for a job that should continue this session.
- **`update` is a partial patch for everything except `payload`, which is replaced whole.** Send only the fields you mean to change (`name`, `schedule`, `delivery`, `payload`), and omit `toolsAllow` to keep the job's existing allow-list; but any `payload` you send must be complete, so a change to `payload.message` has to re-send `payload.timeoutSeconds` (and `kind`) alongside it or the timeout is silently dropped. `update` echoes the job back — read the returned `configRevision` to prove the write landed (it changes on every update) and confirm `schedule`/`delivery` are still what you left.
- **Re-prompting a job is an in-place `update`, not a new job.** Keep the same `jobId` so its run history and `nextRunAtMs` carry over; the stored `payload.message` is exactly what the next run reads, so a prompt rewrite takes effect on the following fire with no restart of anything.
- `add` fills a default tool allow-list; the `payload.message` is what steers the run. Never `sleep`/poll to wait for a schedule — the scheduler is the timer.

## Steps
1. Create it: `automations` `add` with `name`, `schedule`, `payload:{kind:"agentTurn", message:"…"}`, `delivery`, `sessionTarget`, `enabled:true`. Make the message self-contained: the run date, the exact sources/paths to read, the files to write, and what to report.
2. Force the first run instead of waiting for the clock: `automations` `run` with `runMode:"force"` returns a runId shaped `manual:<jobId>:<ms>:<n>`.
3. Verify **by effect**, in this order:
   - the artifacts the payload was told to write — read them yourself (exists, non-trivial size, content sane);
   - the job's own session — `sessions_list` shows `agent:main:cron:<jobId>` (label `Automation: <name>`), and `sessions_history {sessionKey:"agent:main:cron:<jobId>"}` returns that run's transcript. This is the reliable "did it run, and what happened" source exactly when `runs` is empty;
   - `automations get {jobId}` for `state.nextRunAtMs`.
4. A payload that mines raw events or walks several hosts can run tens of minutes: do not start a second pass over the same sources meanwhile, and do not call it failed while its session status is still `running`.
5. Report the outcome with the artifact paths/links, then clean up throwaway jobs with `automations` `remove` (`{ok:true, removed:true}`).

## Decision rules
- No files produced **plus** a `running` cron session = still running, not failed.
- Keep the artifact check independent of the job's own self-report; do not repeat a run just because `runs` looks empty.
- A scheduled payload is stored config — keep credentials and secrets out of `message`.
- "Fire only when something changes" is a trigger script, i.e. `automation-condition-watcher`, not a fixed schedule.

## When the schedule lives in another app's own DB
Not every recurring job is an OpenClaw automation. A desktop app can keep its own scheduler in its own SQLite file — verified with WorkBuddy: `~/.workbuddy/workbuddy.db`, table `automations`, one row per task holding its `name`, `rrule`, `next_run_at`, `updated_at` and the task prompt. Changing the time is a **row edit**, and the discipline differs from `automations add`:
1. Dump that one row to JSON in a backup directory first (used here: `I:\workbuddy\_backup\`), prompt included — the row is the only copy of the task.
2. `rrule` is a plain RFC-5545 rule evaluated in the app's **local** zone (CST on this host), e.g. `FREQ=DAILY;BYHOUR=22;BYMINUTE=30`. Edit it **together with** `next_run_at` (epoch **milliseconds**) and `updated_at`; changing `rrule` alone leaves the old next fire in place.
3. Access the DB with the **app's own bundled interpreter** when the host has no usable `sqlite3` — verified on Windows: `"<app>\binaries\python\versions\<ver>\python.exe"` running a small script you `scp` over (see the Windows execution routes in `tailnet-host-control`). Open it **read-only** for the verification pass — `sqlite3.connect("file:<path>?mode=ro", uri=True)` — so a check can never write, and delete the temp script when done.
4. Re-read the row afterwards and confirm the new values; for a text/prompt field, compare the stored value's SHA-256 with the local source file so "the write landed" is proven rather than assumed. A read-back that also reports the row's `rrule` / `next_run_at` in the same pass confirms the retiming and the prompt landed together.
5. The stored payload is exactly what the job will read, so make the *upstream* job hand its downstream consumer **one self-contained file** (absolute path written into the prompt) rather than making the consumer re-walk the app's own task/session history.

## A chain of jobs that feeds one report
A report job is usually the last hop of a chain: an app writes its own source file, one OpenClaw job collects it, another formats and delivers it (here: PC app 22:30 summary → 23:00 collection job → 08:00 brief). **The delivered report can never be more concrete than the earliest hop**, so raising its depth is a change to *every* prompt in the chain in one pass — producer first, then collector, then report — plus the plan/template documents that describe the chain, so the written spec and the stored prompts do not drift.
- **A collection/report payload must demand concrete facts and forbid filler.** Ask each item for object + action + result with the file / module / number / version / error / path, and quote the source's own words where it has them; without that rule the model writes "推进了某项目" and the report is worthless. Put the rule in the payload, not only in the plan document.
- **Put the delivered report's format in the payload too**: bold the key lines, and give each item a clickable note link (`obsidian://open?vault=…&file=…` — see `obsidian-vault-config`).

## Done when
The job exists with a valid `schedule`/`delivery`, a forced run has been confirmed by its produced artifacts (and, when needed, by its cron-session transcript), and any one-shot test job has been removed.

## Related
Firing only on a real change (`trigger.script`, reading `res.aggregated`, the `{fire,message,state}` contract) — `automation-condition-watcher`. Hand-editing another kind of app-owned SQLite state (a CLI agent's desktop sessions) — `cli-agent-delegation`. Putting a clickable note link in the report — `obsidian-vault-config`.
