# Filing a confirmed board into a project

Branch of `whiteboard-to-diagram-board` for when the board is a project's structure baseline and the user
says to file it: "这个要放入2个地方，第一是项目的资料库中，还有是项目的工程文档中，用来指导开发创作".

Two places, not two copies of one file. Each gets a **document that explains the structure in words** plus
the image; the vault copy is for the human's archive, the engineering copy is the design main source that
开发 reads before writing code.

## 1. Locate both homes before writing

| Place | Target folder | What it is |
|---|---|---|
| 资料库 | `<资料库>/04_工作使用/独立游戏开发/<Project>/01_项目架构与原则/` | the human archive; a structure baseline belongs with 架构与原则, not with 研发记录 |
| 工程文档 | `<Project>/docs/<version>/design/` (+ image under `design/refs/<主题>/`) | rule main source for developers; same shelf as 关卡/命运卡/经济 design pages |

Confirm the version folder from `project.godot` / `docs/README.md`; do not guess `v0.1` vs `v0.2`. `docs/v0.2/PLAN.md`
is a registration ledger only — a design page goes in the version whose rules it governs.

Read one sibling page in the engineering design folder first and copy its header pattern
(`状态 / 关联 FeatureID / 适用版本 / 维护规则`), so the new page is readable in the same rhythm.

## 2. What goes in each document

**资料库 page** — for a person returning months later: source and date, one-sentence summary, then one
section per layer of the structure, then a short 已确认 / 待确认 split, then a 相关文件 line pointing to the
engineering twin. Archive the editable sources here too (`_可编辑.html`, `_模型.json`) — this is the copy that
survives `tmp/` cleanup.

**Engineering page** — for whoever implements next. Same structure sections, plus these three that the vault
page does not need:

1. **对实现的约束** — every line must be checkable, phrased as a rule an implementer could fail. "成长的所有
   产出必须在下一局关卡内被感知，否则装备进关断链" is usable; "注意成长体验" is not.
2. **跨线归属表** — each cross-cutting link with its direction, engineering requirement and owning module.
3. **未决项表** — `项 / 现状 / 承接文档`. Listing what is *not* decided is what keeps the page from being read as
   a frozen spec; never fill a gap to make the table look complete.

Add a `## 变更记录` row with the revision (`r1`), date and what changed. Do not bump the project version for
a design page.

## 3. Image reference: same folder, bare filename

Copy the PNG next to the document, then reference it as `![...](名称.png)` — not
`../<same folder>/名称.png`. Verified mistake: the first pass wrote the folder-relative path back into the
folder itself, which resolves only by accident and breaks when the file moves.

Engineering pages that already keep images under `design/refs/<主题>/` use `refs/<主题>/<file>.png` and that is
correct there; the rule is that the path must be relative to the document's own directory.

## 4. Register in both indexes

| Index | Row to append |
|---|---|
| `<Project>/项目入口.md` → `## 记录` table | `\| 日期 \| 正式入库 \| 一行内容（含结构图与可编辑源） \| [[文档名]] \|` |
| `<Project>/docs/<version>/design/README.md` → 主设计表 | `\| [标题](文件.md) \| 覆盖的功能 \| 施工对照 \|` |

Also add the new files to the entry page's 正式资料目录 tree when that tree lists file names, so the folder
does not silently disagree with the page.

## 5. Verify before reporting

```bash
grep -n "<文档标题片段>" "<Project>/项目入口.md" "<Project>/docs/<version>/design/README.md"
ls -l "<资料库路径>" "<工程路径>"
```

Report the two absolute paths, the index rows added, and which items are deliberately left open. Do not
claim the structure is approved because it is filed — the user's own confirmation is a separate event, and
the board's 待确认 words stay 待确认 in both documents.

## 6. When the board changes after filing

A filed board will be corrected — the user supplies the one-line story, a node gets renamed, a link is
retyped. **All copies move in the same edit**, or the vault and the engineering page start disagreeing:

1. Edit the generator's `MODEL`, re-render, `view_image` the new PNG.
2. Overwrite the filed PNG **under its existing name** in both places. Versioned names (`_v7`) belong to the
drafting phase in `tmp/`; a rename here breaks the image links in both documents and the index rows.
3. Refresh the vault's editable sources (`_可编辑.html`, `_模型.json`) from the same generator output — the
   archive copy is the one that survives `tmp/` cleanup, so a stale editor silently re-introduces the old text.
4. Edit the same section in both documents (the logline went into the vault's 剧情一句话 section and the
   engineering page's 主线 section, with the implementation constraint spelled out only on the engineering side).
5. Index rows do not change — the file names did not.

Verified: one logline correction touched 2 documents + 4 files, all under stable names; skipping any one of
them leaves a reader looking at two different boards.

## Done when

Both documents exist with the image resolving via a relative path, the engineering page has 实现约束 / 跨线归属 /
未决项, both indexes carry a row, and the reply names the two paths plus the still-open items.
After a post-filing correction, every copy agrees: same text in both documents, same PNG bytes in both places,
and the vault's editable sources re-exported from the final `MODEL`.
