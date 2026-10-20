# Production Work Log and Project Record Skeleton

Trigger: the user's standing instruction **"在制作的时候，你最好保留本地的工作日志"** — given after a day of renders, edits and generation runs left nothing but scattered `tmp/` folders. Applies to any making task (render batch, video assembly, image generation, board build, document production), not just 3D.

## Where
- `<workspace>/worklogs/YYYY-MM-DD.md`, one file per day, one `##` section per project; rules live in `worklogs/README.md`.
- A multi-day project may open `worklogs/YYYY-MM-DD_<project>.md` and link it from the day file.

## Before the first artifact
Write a 开工 line: project, goal, expected output absolute path. A log started after the artifacts already exist is a reconstruction — label it **回溯补录** and name the evidence used (conversation, product directory). Never present a backfilled day as live.

## One line per verifiable step
`- HH:MM 【项目】做了什么 → 绝对路径 (bytes / spec) — 成功 / 失败 / 待判`

- Time, action, path, measured size or spec, status. "试了好几次" is process noise; the path and the outcome are the content.
- **待判 is its own status.** An output nobody has judged yet is not 成功; use 待判 so the open decision stays visible.
- A failure line keeps the command and ≤200 characters of the real error, so the next run does not re-trip on it.
- Record the ruling that changed a direction too (a price model corrected from 家具 to 命运卡, an exposure pulled back): the log is where "why it is like this" survives.

## Delegation
Every subagent brief carries one line: 每完成一步，追加到 `worklogs/YYYY-MM-DD.md`. A subagent that reports only a summary leaves the paths unrecoverable.

## Close of day
A 当前状态 block: usable artifacts with paths, what is 待判 and who decides it, and which step comes next. This is what a later session reads first.

## Final product leaves scratch
`tmp/` is disposable. Copy the final artifact into the project folder (`pixel3d/`, `blender_queue/`, the project's `final/`, or the vault's asset folder) and log the formal path in the same line. Verified cost of skipping it: a character sheet from two days earlier was findable only by scanning `tmp/sea_wf/char/`, because nothing recorded where the finished product went.

## Project record skeleton
When a project has no entry yet, stand up three things — a missing one is a gap stated in the entry, not a reason to skip it:
1. **`项目入口.md`** — status, 大类, 建立日期, 项目概况, 当前重点, directory tree, record table.
2. **`00_创作核心/`** — what the thing is and what it feels like. Shape: one-line pitch; background setting (world rules, protagonist, what must never appear); experience/game feel (core emotion, emotional arc, pacing, visual and audio tone); a core → mechanics/visuals mapping table; a **已确认 / 推定 / 缺口** split; sources.
   - Derive from the design document and the generation code's own constants (`WORLD`, `CHAR`), not from memory. Restate those constants as hard constraints so one page can gate every later prompt.
   - Label inference as 推定; turn unknowns into a numbered 缺口 list for the user. Never fill a setting gap by invention — a fictional reason for the flood reads as canon forever.
   - Include **反目标** (what it must not become). It is the fastest part of the page to reuse when reviewing a later asset.
3. **`04_研发记录/YYYY-MM-DD_每日工作日志.md`** — the day's record; link the worklog instead of restating it.

Then register the project in the category `README.md` project table and add the vault 录入记录 rows.

Done when: today's log has a 开工 line, one line per step with absolute path and status, and a 当前状态 block; the final artifact sits outside `tmp/`; and any new project has its entry, creative-core page and daily record — or each gap is named.
