# Matrix / Status Board: rows × columns, not a flow

Branch of `whiteboard-to-diagram-board` for a **table-shaped** board rather than a flow:
"每个模块现在用什么工具和 skill、流程到哪一步、处理什么问题的时候用哪个大模型，摊开成一张表",
"把工作矩阵拉出来一张图". There is no photographed sketch and no single spine to walk, so the
whiteboard reading steps do not apply — but the authoring rules do: generate the SVG from a numeric
layout table, render with headless Chrome, view the PNG before sending.

## 1. Shape: axis strip → banded table → foot blocks

- **Top axis = the pipeline the user just said out loud.** When the request contains a sentence like
  "核心体验搭建用 GPT，设计文档用 DeepSeek，工程执行用 DeepSeek，复杂功能挪到 GPT", that sentence is the
  first thing the board must show: one horizontal strip of stage chips, each with its owner model in a
  coloured tag. It answers "每段默认用谁" at a glance and is read before the table. Do not bury the
  mapping as a column inside the body.
- **Body = rows are subjects, columns are the questions actually asked.** Six columns fit a 1840-wide
  canvas: 模块 / 主要工具（软件·机器）/ Skill·脚本 / 流程现状 / 大模型 / 处理什么问题时用它. Every column
  must come from the user's wording — a column nobody asked for is a column that pushes the real text
  into an ellipsis.
- **Two groups, one table.** When rows split into groups (玩法 / 包装, 前端 / 后端), give each band its own
  background tint and a vertical label in the left gutter. Two separate tables lose the at-a-glance
  comparison. A row that genuinely serves both groups (here: 数据) is drawn once and tagged
  「两线交点」 — not duplicated, not silently filed under one side.
- **Foot = the decisions that belong to no row.** Switch criteria ("什么时候从 A 模型换成 B") and the
  "最该补的几件事" list. Numbered ①②③, one or two short lines each, side by side under the table.

## 2. A cell holds a judgement with its number, not an inventory

- "能走能看，不能边跑边瞄" beats "3C 模块 8 个文件". "规范 102.5k 字符最详细，性能预算未落表，45 文件偏碎"
  beats "特效：已完成". Each 流程现状 cell is a one-sentence verdict plus the one number that supports it.
- The model column names the **default** model and, for rows where it can escalate, the trigger — the same
  four criteria the foot block spells out.
- Rows are ordered by the pipeline, not alphabetically: the reader scans for "where does this break".

## 3. Geometry and the collision that costs a re-render

- Canvas 1840 × 1522 with an 11-row, 6-column body is a working size; anything taller needs the table
  split rather than the font shrunk.
- **Row height comes from the wrapped line count** (`46 + 20 × lines` style derivation, per SKILL.md step 10),
  never a fixed height with text clipped into the next row.
- **Footer blocks: 112 px fits three two-line entries, not four.** Verified: a fourth criterion rendered
  past the block and landed on the block's own bottom rule; moving the item into the block and raising both
  blocks 112 → 128 (canvas 1500 → 1522) fixed it. Size a block from its entry count and line count *before*
  the first render.
- **Every numbered item must live inside the same container as its siblings.** An item left outside the
  shared group/stack is positioned on its own y and collides with whatever the group's last row occupies —
  this is what produced the overlap above. When one item moves into the block, add its height to the block.

## 4. Render and check

- Wide canvas renders at **1.6×**, not 2×:
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1.6 --window-size=1840,1522 --screenshot=<out>.png file://<abs>.svg`
  → 2944 × 2435, ~1.18 MB PNG. A 1680-wide board at 2× stays small enough; a 1840×1522 board at 2×
  overshoots a megabyte and a half for no legibility gain.
- Chrome prints `N bytes written to file` but not the pixel size. Confirm the frame really rendered at the
  intended scale by reading the PNG header:
  `python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(33);print(struct.unpack('>II',d[16:24]))" <out>.png`
- `view_image` refuses `/tmp`; render or copy into the workspace (`~/.openclaw/workspace/tmp/` or
  `.tmp_*.png`) before inspecting. One media per message, so three boards are three messages
  (`render-preview-grading` → `references/media-handoff.md`).

## 5. What the chat message must carry

The table's conclusions, not a description of the table: the three most mature modules, the thinnest one,
the escalation criteria, and the "补什么" list. The image is the summary; the message is the reading of it.
State the canvas and PNG pixel size, and where the PNG + SVG now live (vault, desktop, repo copy) with the
byte sizes you measured.
