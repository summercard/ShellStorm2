---
name: project-snapshot-collect
description: Use when collecting or writing up a project's current state into notes or a vault, when a finished day's work or a batch of judgment entries must be filed into the vault's formal record under the existing front matter and ledger, when a making task must keep a local step-by-step work log so its paths and rulings survive scratch cleanup, when a project has no vault entry yet and needs its record skeleton (entry page, creative-core page, daily log), or when several copies exist and you must pick which copy to read. Covers finding the live copy by activity, keeping facts and judgment separate, filing only what the user names, and recording deliberate omissions.
---

# Collect a Project's Current State

## When
- Asked to document what a project is and where it stands ("把这个项目的现状收进资料库").
- A finished day's write-up must be filed into the project's log and its judgment entries ("昨天的日志仍然要归入工作日志") — see the filing branch below.
- The same project exists on several machines or in several folders and you must decide which one to read.
- The user says the project is still being modified while the copy you found looks idle, finished, or low-activity.

## Steps
1. Find the live copy before reading anything. Enumerate every candidate (other hosts, sibling folders such as `<name>-backup` / `<name>-work`) and judge each by activity, not by name:
   - `git -C <copy> log -1 --format='%cI %h %s'` and `git -C <copy> rev-list --count HEAD` — newest commit time and commit count;
   - `git -C <copy> rev-parse --abbrev-ref HEAD` — the branch actually checked out;
   - `git -C <copy> status -s | wc -l` and the newest file mtime under the tree — work in progress today.
   The copy carrying today's commits and today's worktree edits is the source of truth. A copy with a single commit on `main` while the real work sits elsewhere is a **stale export**. Verified: a snapshot was written from a remote copy (`main`, 1 commit) while the live development copy was another machine's `ShellStorm2` on branch `0.1.2`, 611 commits, 1,218 files changed that day; the correction was "这个项目工程今天还在修改".
2. Confirm the target and the scope with the user before writing, when the project or the copy is ambiguous. One question now costs less than a whole collection pass on the wrong source.
3. Snapshot the source, not the process: record what the source actually shows (paths, versions, counts, commands that reproduce) and name the exact source in the document — machine + path + branch + tip commit.
4. Write observed facts only. Put your own inferences, risks and "what looks missing" in a **separate** document beside it; a fact file mixed with judgment can no longer be verified against the source.
5. When a draft turns out to be of the wrong source, mark it superseded in place — a dated line saying why and what replaces it — and write the new document alongside. Keep the old draft; do not delete it.
6. When the collection runs through delegated agents, give each its own output file, then re-check its source lines against the live copy yourself before publishing.

## Filing a finished day into the vault (branch)

When the draft is done and the user says it goes into the archive ("仍然归到工作日志"), file it — do not re-collect. Locate the home from an existing sibling file's front matter, not from the folder name: the daily log lives in the project's `04_研发记录/` beside the previous day's log, and judgment entries in `03_判断与决策/`.

- **Mirror the sibling's shape.** Copy the previous log's front matter (`type: daily-development-log`, `status`, `occurred`, `area`, `project`, `tags`) and its section pattern (当天总览 first, then one section per workstream, then 待定 / 当日未闭环 last). Judgment entries carry `type: judgment` (or `type: method` for a procedure/principle rather than a call) plus `created / occurred / area / project / priority / importance / tags`, and the body sections 场景 · 判断 · 原因 · 反例 / 边界 · 对未来影响 · 关联.
- **File the content, not the digest.** Numbers, paths, file sizes, assert counts, rejected options and the user's own wording stay in the log; compression that drops them makes the entry unverifiable later.
- **The user's narrowing list decides what gets elevated — nothing else.** When they say "只收这两点，其他不用", write entries for exactly those and leave the rest in the fact draft; do not file "the rest" anywhere, and say in the report what was left out. A creative-direction point the user names as 创作思路 belongs in a 创作偏好 entry, an engineering or process trade-off in a 判断 entry, and an approach/principle in a `method` entry.
- **Small details get recorded, not promoted.** The user's instruction "先记录，不确定会不会变成决策条目" means one list in the log (values, one-off layout fixes, open questions) and no entry. Never promote them yourself.
- **Append one row per file to the archive's 录入记录.** Each row: file → destination → handling, plus a trailing note naming the source instruction, what was deliberately excluded, and what remains 待定. This ledger is what makes a later "why is this not in the vault" answerable.
- **Log the day's non-project lines too, in their own section.** Work on other projects during the same day stays in the same log under a clearly separated section, so the log is the day, not one repo.

Done when: the log exists under the project's record folder with the sibling's front matter, each entry the user asked for exists with its priority, the 录入记录 has its rows, and the report states what was excluded and what is still per the user's call.

## Recording while the work runs (branch)

The user's standing instruction "在制作的时候，你最好保留本地的工作日志" makes the log part of the task, not a wrap-up. Details and the file format: `references/production-worklog.md`.

- **Open the log before the first artifact**: project, goal, expected output absolute path. A log written afterwards is a **回溯补录** — label it and name the evidence, never present it as live.
- **One line per verifiable step**: time · action · absolute path (bytes/spec) · `成功 / 失败 / 待判`. An output nobody has judged is `待判`, not `成功`. A failure keeps its command and ≤200 characters of the real error.
- **The final product leaves `tmp/`**: copy it into the project folder and log that path in the same line; scratch directories get cleaned, and an unrecorded artifact becomes unfindable.
- **Every delegated brief carries** 每完成一步，追加到 `worklogs/YYYY-MM-DD.md`; a subagent's summary alone loses the paths.
- **A project without an entry gets three things**: `项目入口.md`, `00_创作核心/` (what it is and what it feels like, with a 已确认 / 推定 / 缺口 split), and `04_研发记录/YYYY-MM-DD_每日工作日志.md`. State a missing piece as a gap; do not invent setting detail to fill it.

Done when: today's log has its 开工 line, a line per step with path and status, and a 当前状态 block; the final artifact sits outside `tmp/`; any new project has its three pieces or a named gap.

## Decision rules
- The first copy you find is not the source of truth; liveness (recent commits, same-day worktree changes) decides. Compare activity first, then ask the user which copy is canonical if it is still unclear.
- A tidy copy is not a live one. A shallow, single-commit, or build-host checkout is usually an export of the real repository.
- Keep the snapshot and the judgment apart — the user's rule is 收集为主，判断另出; the fact document holds only what was observed.
- **Stage first, file only on confirmation — and file the content, not the digest.** A collection write-up lands in the user's staging area (`01_待整理/…`, or the collection inbox `00_收件箱/`), never straight into a formal category, and nothing enters a formal directory until the user confirms it. When the user confirms, write the **concrete content** into the formal file — the facts, quotes and numbers — not just the compressed summary that was staged.
- A summary you are asked to **produce** is judged on its decision content, not on its activity log. The user's standing requirement: recording only 做了什么 builds no future decision direction. Group the judgment material under the user's three dimensions — **创作思路** (itself split into **动画创作** and **风格创作**／画面风格创作; the user's 2026-10-17 correction also moves creative-direction items that surfaced under 决策角度 up into here), **决策角度** (the angle taken, the evidence, the alternatives rejected and why) and **处理问题的方法** (the concrete problem, how it was solved, the direction adjusted, any reusable rule) — keeping the concrete elements (场景或问题 · 判断依据 · 备选与被否 · 调整方向 · 可复用规则) inside them, and quote the user's own words for a judgment instead of restating it. Write **what was actually done and how it was decided**, not a category label — the user's follow-up asks for that level of specificity, and the written summary must be self-contained enough to read on its own. (This governs the summary/source you write; the 收集为主，判断另出 split still governs what you *collect*.)
- **Give every judgment entry a 5-step priority, and report the calls you make yourself.** The user's standing rule (2026-10-17): each judgment entry carries `priority: P0`–`P4`, 0 highest — **P0** iron rule / safety-privacy boundary (follow unconditionally; on a conflict with current state, stop and report), **P1** an explicit creative or design direction, **P2** an unconfirmed preference or conditional rule (act on it; ask only when the blast radius is large), **P3** reference — engineering / numeric / process trade-offs (file it anyway, just triage it low), **P4** one-off or process noise. Creative-direction items are P0–P1, pure engineering trade-offs P3. **P3/P4 are decided by the agent without asking — but not asking is not the same as not telling**: report each call as 条目 → 优先级 → 定了什么 → 依据 → 影响面, and report a dropped P4 as “已忽略 + 原因”, never silently. Keep the tiers in the extraction prompt as well as in the vault rule document, or the run never sees them. A re-grade is written to the entry's 修订记录 with the old value kept.
- Do not raise a fact's confidence to fill a gap. If the source does not show why a decision was made, say it is not recorded rather than inferring the reason.

## Done when
The snapshot names the exact source (machine, path, branch, tip commit), every claim traces back to that source, judgments live in their own document, and any superseded draft is marked rather than removed.

## Related
Keeping the during-work log and standing up a project's record skeleton — `references/production-worklog.md`. Choosing which copy to keep and deleting the extras — `duplicate-copy-cleanup`. Reading a copy's branch/history state, or landing a checkout on another host — `git-clone-triage`. Reconstructing what the user actually asked for from the AI agent's own session archive (prompts, requirements, preferences) — `agent-session-log-mining`. Registering the folder as a vault or changing its settings — `obsidian-vault-config`. Renaming or moving a category without leaving stale links — `path-rename-reference-sweep`.
