# Whole-Codebase Module Map (many modules, one document)

Read this instead of steps 2–3 of `SKILL.md` when the ask is an **overview of a whole project** — "每个模块的制作链路 / 工具 / 实用逻辑 / 评判维度", "把这个工程整理成一份模块说明" — rather than one feature. Steps 1, 5–8 of `SKILL.md` still apply: snapshot, cite, gaps, verify.

A 100k-line tree cannot be read line by line in one turn, so the procedure changes from *read then write* to **measure, rank, then read only what carries the risk**. Depth per module is a decision you make from numbers, and it must be visible in the document.

## 1. Measure before reading
Per top-level module directory: file count and line count; then the largest individual files.
```bash
find <root>/src -mindepth 1 -maxdepth 1 -type d | while read d; do
  n=$(find "$d" -name '*.gd' -type f | wc -l | tr -d ' ')
  l=$(find "$d" -name '*.gd' -type f -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
  printf '%s\t%s\t%s\n' "$(basename "$d")" "$n" "$l"
done | sort -k3 -n -r
find <root>/src -name '*.gd' -type f -size +60k -exec ls -l {} + | awk '{print $5, $9}' | sort -rn | head -15
```
Verified on a Godot project: 296 `.gd` files / ~103,538 lines, with three directories holding 56 % of it and one file at 9,482 lines. Those two numbers produced the document's whole structure — everything else was confirmation.

Also count what the runtime loads but nobody counts: `find <root>/data -mindepth 1 -type d -exec sh -c 'echo "$(ls -1 "$1" | wc -l) $1"' _ {} \;` — a directory the code reads that holds **0 files** is a finding, not a detail.

## 2. Rank the detail budget
- **Top three by lines** get the full four fields from source (entry file read whole, debug constants grepped, design doc read).
- **Middle** gets entry file + design doc + delivery records; no line-by-line read.
- **Bottom (< 1k lines, or a single file)** gets a row in the table and one line of purpose. Do not spend a paragraph on 45 lines of legacy code.

## 3. The four fields, same order every module
| Field | What goes in it |
|---|---|
| 链路 | The chain of files from authoring input to runtime result — named files, in order |
| 工具 | The probe / script / editor surface actually used to verify that module |
| 实用逻辑 | The constants, key bindings, formulas and thresholds that a future editor must not break |
| 评判 | What "done" means for that module, plus its known historical failure |

A table (module → directory → files → lines → entry file → design doc) carries the inventory; the per-module prose carries only the four fields. A module with no design doc says so ("实验性，无独立设计文档") instead of borrowing another module's rules.

## 4. Do not rewrite the ledger that already exists
A repo usually already has an index keyed by **feature id** recording *what shipped and when* (delivery records, changelog, `MODULE_INDEX.md`). The map you are writing answers *how it is built and how it is judged*. Say the split in the header — one line each — so a reader knows which document to open, and neither document restates the other. Do not merge them: a delivery ledger with a build procedure inside stops being a ledger.

## 5. Run the cheap structural checks — they are the most useful section
These cost minutes and find real work; they became the section the reader acted on first:
- **One file above ~3k lines** in a module that also owns many flows → name it as the single point of risk and say which flows are entangled in it.
- **A data directory the loader reads is empty** → "改这块之前先确认数据从哪来".
- **Two implementations of one concept** (old `src/fx/x.gd` beside `src/vfx/x.gd`) → whoever edits next picks the wrong file.
- **A comment contradicting its own constant** (`6×6=36` in the header, `5×5=25` in the code) → report the constant as truth and the comment as stale; never repeat the comment into the doc.
- **No test runner** — 130 probe scripts launched by hand is a regression cost, not a detail.

## 6. Label the evidence level per section
Two labels, used honestly in the document itself:
- **实测** — you counted it, read the file, or quoted a `file:line`.
- **推断 / 仅入口级** — derived from the entry filename, the design-doc title and the delivery records, with no line-by-line read.

State which modules were read in full and which only at entry level, in the document and in the reply that delivers it. A module map that reads as fully verified when half of it was inferred is worse than a shorter map that is labelled — the reader will tune values against prose that never saw the source.

## 7. Close with the reproduction command and the date
End with the commands from step 1 and the date + machine the numbers came from, plus "数字对不上就说明代码变了，以新数为准". Line counts drift within days; a map without its measurement date becomes a rumour the moment someone refactors.

## 8. When the map must become one card per module

Trigger: "按照这张表，把每个模块的链路、skill、流程文档独立整理成卡片，卡片之间可互相链接、未来可迭代、可复刻".

One map document is for reading; a card set is for maintaining. Split only when the user intends to edit
one module without re-reading the others — otherwise the single document is cheaper.

- **Files**: `00_索引.md`, `_模板_模块卡片.md`, then one card per module named `{分类}-{序号}_{模块名}.md`
  (`玩法-01_功能.md`, `包装-04_音效.md`). The category vocabulary is exactly the map's two groups; never
  invent a third category per module.
- **Stable id**: `MOD-<ABBR>` (`MOD-FUNC`, `MOD-3C`, `MOD-AUDIO`) is assigned once and never renamed. The
  filename may change later; the id is what other cards and the gap list point at.
- **Skeleton, same order in every card**: 边界 / 链路（六步）/ 工具 / Skill / 流程文档 / 大模型分工 /
  验收 L1–L4 / 常见坑 / 复刻清单 / 迭代记录 / 备注. A card carrying ten of the eleven stops being comparable
  to the others — the missing section is itself the finding, not a reason to drop the heading. The 链路
  section holds **two** tables: the six-step flow, and the per-step tool/standard/document table in §8.1.
- **The index carries what no single card can**: card list with a one-line status, dependency order, the
  model-split table with the escalation criteria, naming and iteration rules, how to add a new module, and
  the global gap list. Do not restate per-card detail there.
- **Links are relative** (`玩法-02_3C.md`), never absolute. The set gets copied to the Desktop, into the
  repo's `docs/`, and opened on another machine; absolute paths resolve in exactly one copy.
- **A card is a judgement, not an inventory**: "能用，回归靠人工" / "覆盖广，不常跑" beats a file list, and
  each verdict keeps the number behind it (规范 102,545 字符 / 114 动作 / 51 个界面).
- **Distribution is part of the job, and its check runs on the receiver.** The vault directory is the only
  source; after copying, verify name + byte length *there*, never the sender's exit status. On Windows that
  is PowerShell `Get-ChildItem <dir> -File | % { "$($_.Name) :: $($_.Length)" }` — `dir /b` returns GBK
  mojibake and proves nothing (`tailnet-host-control` → `references/windows-remote-execution.md`).

## 8.1 Every step row names its tool, its standard and its document

A 链路 table of only 输入 / 动作 / 产物 is not reproducible: the next editor still has to guess which tool,
what "good" means, and which document governs the step. The correction that came back after the first
delivered set was exactly this — "每个链路里的相关 skill 和工具使用标准、文档也要加入". So each card gets a
second table under 链路:

| 步 | 工具 / Skill | 使用标准（做到什么算对） | 依据文档 |
|---|---|---|---|

- **标准 carries a number or an executable check** — "同构件尺寸差 ≤3 倍", "连听三次", "51 屏全部勾完".
  "做好一点" is not a standard and hides the fact that none exists. One standard per row; split the row
  rather than writing two into one cell.
- **Document names come from a real listing, never from memory.** List the owning machine's docs directory
  with byte sizes and take the names from that output. A remembered title can be exactly right by luck
  (`UI与UX全局设计及全界面清单.md`, 79,726 B, did exist) — the point is that only the listing tells you, and
  one wrong character in a filename is a dead reference for the reader.
- **A truncated listing is not evidence of absence.** Verified: a `tail`-cut directory listing hid that
  79,726 B UI document, and it briefly read as missing. Re-query by name (`Get-ChildItem -Recurse -Filter
  *UI*.md`) or print the whole listing before writing 缺 into a cell or telling the user a document does not
  exist.
- **A missing document is written 缺, never omitted.** Mark the cell 缺, close the section with
  "本卡最该补的文档是 ____，因为 ____", and collect those rows into the index's 该建的表 table. An omitted
  cell silently turns a gap into a claim of coverage.
- **Declare the path root once** at the top of the section (`文档根 = docs/v0.1/`); cells then carry
  filenames only, so moving the docs tree does not invalidate every cell.
- **The index carries the reverse index**: one table per group (全局 / 玩法 / 包装 / 模板) with rows
  `文档 | 字节 | 管哪张卡的哪几步`. That is what makes twelve cards one searchable set instead of twelve
  islands, and it is how a reader starts from a document rather than from a module.
- **Check the relative links before shipping** — a copied set with one dead link is a set nobody trusts:
  ```bash
  cd <card dir>
  for f in *.md; do
    grep -o '](\([^)]*\.md[^)]*\))' "$f" | sed 's/^](//;s/)$//;s/#.*//' |
      while read -r l; do [ -z "$l" ] || [ -e "$l" ] || echo "BROKEN $f -> $l"; done
  done
  ```
  An empty result is the pass condition; anything printed fails the delivery.

## 8.2 The card set also needs the resource map

The second correction after the cards were delivered was "每个链路里的相关 skill 和工具使用标准、文档也要加入",
followed by "去 WorkBuddy 和工程里找场景相关的完整 skill，把评判维度和 AI 关键词也整理进去". Both are the
same demand: the step table says *what* to use, the reader still needs to know *where it lives* and *which
ruler audits it*.

- **Skills live in one place on this Mac**: `~/.openclaw/agents/main/agent/workshop-skills/`, one folder per
  skill (~41 at the time of writing). Verified: the engineering repo and the WorkBuddy project each contained
  **no** skill or prompt directory (`find` found only an empty `\scripts`), so "去工程里找 skill" is a round
  trip that ends with nothing. List the workshop directory first and say in the card that this is where they are.
- **Take skill names from `ls`, never from memory** — the same rule as document names. A skill that does not
  exist is a dead reference; when the capability is genuinely missing, write it 缺 and name what must be built
  (`sfx-pipeline`, `package-size-audit`, `ui-screen-checklist`). A 缺 row is a roadmap; a plausible fake name is
  a dead end.
- **One row per skill: 干什么 + 本模块怎么用.** A bare inventory of installed skills transfers no decision —
  the reader cannot tell `render-preview-grading` from `project-snapshot-collect` without the "used here for…"
  clause.
- **Name the ruler, and never mix the three.** 七维打分 = an image judged against a reference image (total ≥4.0,
  any dimension ≤2 rework); 评判五维 = module delivery (功能 / 视觉 / 性能 / 数据 / 回归); 验收 L1–L4 =
  L1 专项 → L2 真实渲染 → L3 完整工程 → L4 设备. Auditing a module with the image ruler passes the wrong
  things; each card's 验收 section states which ruler applies.
- **Keyword and prompt libraries are a pointer, not a copy.** Cite the single source directory with its byte
  size and lift only the usable keywords and hard numbers. Rewriting a prompt skeleton from memory drops exactly
  the constraints the library exists to hold.
- **The index carries the cross-card inventory** — which skill serves which cards, and which ruler applies where —
  so a reader can start from a tool instead of a module.
