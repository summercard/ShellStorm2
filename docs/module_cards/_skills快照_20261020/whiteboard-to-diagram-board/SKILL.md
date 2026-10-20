---
name: whiteboard-to-diagram-board
description: Use when the user photographs a hand-drawn whiteboard, sketch or flow ("这张是我的核心循环，帮我整理成一份工整的画板") and wants it redrawn as one clean structure diagram — a game loop, system map, or org/flow chart — or when a messy sketch must become an image they can paste into a doc or forward, or asks for a table-shaped status/matrix board instead of a flow ("每个模块用什么工具和 skill、流程到哪一步、用哪个大模型，摊开成一张表", "把工作矩阵拉出来"), or asks for an editable version of that board ("做成一个可编辑的图版"), or asks for a second board on a project that already has one but explains a different layer of it ("把昨天那个体验循环也做一张图，重点加入玩家心流"), or asks for a new layer to go straight into an existing board at a marked spot as explanation rather than analysis ("直接在这个图的右边把心流体验加进去，这个是用来说明的，不是分析的"). Covers transcribing the handwriting without guessing, collapsing the board onto one main line (主线) instead of mirroring ink position, authoring the board as a generated SVG, rasterising a standalone .svg with headless Chrome (2× for a 1680 board, 1.6× for a wide 1840 matrix), catching text overflow and footer-block collisions before sending, delivering PNG + SVG, and — when the board must stay editable — generating a browser editor from the same layout model with drag/text-edit and SVG/PNG/Excalidraw/JSON export, and filing a confirmed project board into both the project vault and the engineering design docs.
---

# Turn a Whiteboard Photo Into a Clean Board

## When
- A photo of a whiteboard arrives with a one-line ask: "帮我整理成一份工整的画板 / 结构图".
- The same photo, but the deliverable must stay editable — "做成一个可编辑的图版 / 让我自己拖 / 我要能改字":
  branch to step 14 and `references/editable-board.md`.
- The board is **table-shaped, with no sketch and no spine** — "每个模块用什么工具和 skill、流程到哪一步、
  用哪个大模型，摊开成一张表", "把工作矩阵拉出来": read `references/matrix-board.md` first. It keeps
  this skill's SVG/headless-render/view-before-send rules and replaces the whiteboard reading and
  composition steps with an axis strip, a banded rows × columns table and numbered foot blocks.
- The project already has a board and the new ask is a second reading of it — "昨天那个循环也做一张图，重点加入心流 / 体验 / 情绪", "再来一张讲成长的". This is not a restyle (that re-enters the generator, step 9) and not a new sketch. Reuse the sibling board's node names, wording and palette; keep the mechanism chain as the spine; add the new layer as a panel plus per-node marks — procedure in step 9a.
- The new layer goes **into the board that already exists**, at a spot the user marks — "直接在这个图的右边这个地方把心流体验加进去，这个是用来说明的，不是分析的". That is neither a second board nor a restyle: widen the existing canvas and add one panel (step 9b). The register is the tell — explanation sentences belong inside the board; scores, weights and thresholds make it a separate analytic board.
- A sketch is the input, a shareable diagram is the output — not a screenshot of an app
  (`macos-window-capture`) and not a long-form document (`doc-package-delivery`). The structure doc in
  step 15 is the companion of a filed board, not the deliverable itself.
- The board is a project's structure baseline and must be filed where developers will read it ("放入项目的
  资料库，还有工程文档中") — step 15 and `references/filing-board.md`.

## Read the photo before drawing anything
1. Transcribe every node, arrow and annotation first. When the handwriting is small, crop quadrants
   with the local ffmpeg (`/Users/summercards/.local/bin/ffmpeg -vf "crop=w:h:x:y,scale=1200:-1"`)
   and `view_image` each crop — a 1200×675 phone photo is not legible at full-frame scale.
2. **Do not guess a word.** Put a `★` beside every uncertain term on the board and list those words in
   the chat message for confirmation. On a rendered board the same mark is a `?` inside the word plus a
   purple `待确认` tag on the node, and a numbered 待确认 card listing each one. One marked word costs the
   user one line to correct; one guessed word silently poisons the whole diagram.
3. **Keep struck-through and crossed-out items.** A struck chain on a whiteboard is a decision, and it is
   usually the turning point of the design (verified: 「吃金币 → 买家具 → 成长 ①」 was crossed out, so
   growth can no longer be bought directly). Draw it as its own dashed red 「已划掉」 block plus one line
   saying what it changed. Deleting it throws away the most informative mark on the board.

## Structure by main line, not by position
4. **Pick one spine; hang everything else off it.** A usable board has exactly one main line — the
   sequence the user narrates (一局怎么走, 一局怎么循环). Draw it as a single vertical chain on the
   central axis; entries, branches, struck ideas and uncertain words become side chips or dashed
   links beside it. Panels are containers for genuinely parallel groups, never the default frame:
   a five-panel layout was rejected twice in favour of one axis — 「这张图应该中轴是核心 … 每个卡片
   不要这么长」, then, after re-panelling, 「这段是主线，先把这个表达清楚，脑图结构也要按照这个来
   清出来」. When the user names a segment as 主线, it becomes the spine verbatim: keep its order and
   wording, demote the rest, and never add nodes just to balance a column.
5. Cards on the spine: a bold title plus one grey sub-line, 320×76 or shorter — never one tall card per
   group. A one-line premise (the game's logline, "小机器人在末世的天台冒险，寻找失散的主人") belongs in that
   sub-line; a floating note parked in the header band collided with the protagonist card and had to be pulled
   back, costing a re-render. When panels are genuinely parallel, give each a two-digit number, a title, a hairline rule
   and single-accent chips, and repeat the accents in a legend.
6. Point at related panels by name inside a chip ("分三支，见 02") instead of drawing long crossing arrows.
7. Keep your own commentary visually separate — small grey text at the panel foot, labelled as yours:
   "白板原意优先，灰色文字是我加的解读". Never let interpretation wear the same style as the original.

## Author it as SVG, not by hand
8. Generate the SVG from a short Python script with helpers `rect / text / chip / arrow / panel`, all
   geometry coming from a numeric layout table. A fix must cost one edit + one re-render, not a redraw.
9. Canvas 1680×1080, margin 56–104, font stack `PingFang SC, Hiragino Sans GB, Noto Sans CJK SC,
   sans-serif`, chip title 17–19 px / sub 12.5–13.5 px. Two sanctioned looks, both driven by the model:
   - **Light card board — default for framework/loop boards.** Background `#F4F5F7`, 40 px grid at 0.025
     black; cards `#FFFFFF`, stroke `#E4E7EC` 1.2 px, radius 12–16, one soft shadow
     (`feDropShadow dy=3 stdDeviation=7 opacity=.07`); text `#111827`, sub `#6B7280`; accents blue
     `#3B82F6`, amber `#D97706`, purple `#7C3AED`, green `#0E9F6E`, red `#E02424`.
   - **Dark board** (`#0E141B`; `#4C9AFF` `#FFB454` `#B98CFF` `#46D39A` `#FF6B6B`) only when the user
     asks for it or the board is bound for a dark deck.
   Composition: the core loop runs down a **central axis** (cards 320×76, step 124 px, one arrow between
   neighbours) with branches in narrow side columns — section cards 400 wide holding 360×38 chips, ~180–300
   tall. Keep every card short; do not span the board with one tall panel (the 620×876 rejected shape is
   in step 4).
   **A second layer (experience, emotion, flow) rides beside the chain, never inside it.** Keep the
   mechanism spine as drawn and add: a per-node intensity row (five cells, filled = level 1–5) plus a
   one-word emotion tag, both in the accent colour rather than the structural text colour; and one analytic
   panel with banded zones (焦虑区 / 心流带 / 无聊区), a solid line for the pressure the game applies and a
   dashed line for the capacity the player has, per-stage tick labels carrying the *real* counts from the
   project (six stages → 21/33/45/57/69/78 cards), and at most two annotation chips whose pointers land on
   the crossing that matters (挑战先跳、技能下一局才追). Mark any number you estimated as 待定 on the board
   itself — an invented axis looks like evidence.
   **Step 9a — a second board on an existing project (new lens, same structure).**
   1. Open the sibling generator's model (`build_board*.py` → `MODEL`, or `board_model.json`) and copy its
      node names verbatim: 进入房间 / 怪物 · 机关 · 搜集 / 局内货币 / 命运卡 / 撤离 / 天赋 · 武器 · 装备. New
      vocabulary in the second board means the pair can no longer be read together.
   2. Name the one thing the new board argues. For an experience board it is the emotional curve, so the
      spine becomes the *same* chain relabelled by what the player feels at each node, not a new chain.
   3. Choose the quantity the chart plots and take its numbers from the project (stage card pools, level
      counts, time budget). If the project has no number, draw no plot — put the open question in a 待定
      line instead of inventing an axis.
   4. Add the layer as its own panel plus per-node marks (step 9): one plot, one six-to-eight row table
      mapping each element to the mechanism that delivers it and a checkable pass line, and one list of
      what breaks the effect — each tagged with the module that owns the fix.
   5. Footer cites the sibling (`依据：<date> <sibling board> / <structure doc>`); the pair is only useful if
      a reader can find both.
   6. File it beside the sibling (same folder, `YYYY-MM-DD_<name>_v1.png|.svg|_生成器.py`), generator kept,
      so a later number change is one edit and one render.

   **Step 9b — add the layer into the existing board instead of beside it.**
   1. Widen the canvas and move nothing. In an editable HTML board the size is duplicated in five places —
      `#wrap` width, the `svg` CSS width/height, the `<svg viewBox>`, the `width`/`height` attributes, and
      the background `<rect>` — plus the x of any right-anchored header `meta`. Miss one and the board is
      clipped or floats on a grey band.
   2. Place the panel in the region the user pointed at: one white card with a hairline rule and a title,
      then six rows of three parts — emotion pill (好奇 / 紧张 / 松弛 / 释放 / 掌控 / 犹豫), the sentence in
      the player's head as a quote (「顶不顶得住？」), and what the mechanism gives in grey
      (`血条、命中、掉落，手上有数`). Same order as the spine, never a new chain.
   3. Write explanation, not analysis: no weights, percentages, thresholds or 判据 columns — those belong
      to the analytic board. One closing line is allowed ("心流不是难度高，是每一刻都有下一步想做的事").
   4. Leave every existing node untouched, including stray chips the user may not want; widening is
      additive. Offer the deletion, do not perform it.
   5. Render in clean mode so the editor toolbar is not in the PNG, at the new width, into the workspace,
      then `view_image` (toolbar fix in `references/editable-board.md` §3).

10. **Draw every wrapped line.** A wrap helper that computed two lines but rendered the second as an empty
    string cut half a sentence out of a card — and only the rendered PNG showed it. Height must be derived
    from the line count (`46 + 24 × lines + 14`), not fixed.

## Rasterise and verify
11. Chrome headless renders a standalone `.svg` file directly — no HTTP server, no `file://` module problem:
    `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1680,1080 --screenshot=board.png board.svg`
    → 1680×1080 renders as 3360×2160. `rsvg-convert` is not installed on this Mac; Chrome is the renderer.
    `task_policy_set TASK_CATEGORY_POLICY` noise on stderr is harmless — the success signal is
    `N bytes written to file`. Script: `scripts/render_svg.sh`.
    Write the render **into the workspace, not `/tmp`**: step 12 views the PNG, and `view_image` refuses paths
    outside the allowed directories (`Local media path is not under an allowed directory` — rule and recovery in
    `macos-window-capture` step 3). A `/tmp` render costs a copy step before it can be inspected or sent.
12. `view_image` the PNG and check for clipped or overflowing text, empty cards, and a label colliding
    with a dashed connector. Three failures pass a code review and still wreck the picture: a side chip
    landing on an annotation card in another column; a rotated `loopback` label sitting on the gutter
    line and clipped by the canvas edge; and duplicated text where a scripted edit rewrote one field of a
    shared layout list. **Place every label from its measured length, not by eye.** A CJK glyph is ~1 em
    wide, so a 40 px title of four characters is 160 px and a suffix starting at 200 px lands on top of it
    (keep suffix x ≥ chars × size + 8). A rotated label's length becomes its vertical extent: it must fit
    inside its own panel, not merely inside the canvas — a `下一局 · 更强` label anchored at the panel edge
    ran into the neighbouring panel, and the fix is to move the return curve and the label 100 px inward.
    Keep legends out of the line's path: a `实线＝挑战　虚线＝技能` legend parked at the plot's top-right
    corner sat exactly on the arrowhead and belongs on the section header line instead. When
    several entries share a shape, replace the whole block and regenerate — do not patch them field by
    field. Fix and re-render; each cycle is one command. Never send an unviewed board.
    A fourth is invisible at full-frame scale: a connector the draw loop skipped because that edge kind
    carries no node endpoints. Account for every declared edge before re-routing points —
    `references/editable-board.md` §2 has the guard and the counting check.
13. Deliver `board.png` (2×, state the pixel size) together with `board.svg` (the editable source), and put
    the structure in the message so it is readable without opening the file: one sentence for the spine,
    then its segments, then the side marks, then the uncertain words.
14. **If the user wants to keep editing it themselves** (可编辑的图版 / 想自己拖 / 要改字), do not hand-edit
    the SVG: render the same layout model a second time as a browser editor. Model schema, edge-routing
    rule, editor mechanics, and the `.html` attachment rejection with its zip recovery are in
    `references/editable-board.md`.
15. **If the board is a project baseline and the user asks to file it** ("放入项目的资料库，还有工程文档中，
    用来指导开发创作"), the image alone does not satisfy the request: write a structure document beside it in
    both places and register each in its own index. Targets, document shape, the index rows, and how to push a
    later correction into every copy are in `references/filing-board.md`.

## Decision rules
- A whiteboard's layout is not its structure; redraw the relationships, keep the wording.
- A matrix/status table is not a flow: do not force it onto a central axis. Rows are subjects, columns are
  the questions the user asked, and the pipeline the user spoke becomes the top axis strip.
- A picture and an editor are different deliverables. Build the editor only when the user says they want
  to move or rename things later; otherwise PNG + SVG is the whole job.
- One layout model drives both renderers. Editing the generated HTML or SVG by hand splits the source and
  the next correction lands in only one of them.
- Uncertain handwriting is marked, never filled in — and the marked words are listed in the reply.
- Rejected or abandoned nodes stay visible, labelled as rejected.
- The SVG is the source of truth; the PNG is generated from it. Never edit the PNG.
- A second board on the same project is a new lens, not a restyle: reuse the first board's node names
  and palette even when that means keeping dark (the sibling shipped dark at `#0E141B`), and make every
  added mark visually attributable to you. Restating the mechanism in different words is the failure mode —
  the reader must be able to lay the two boards side by side and see one structure, two readings.
- Explanation rides inside the board it explains; analysis gets its own board. When the user says
  "这个是用来说明的，不是分析的", the panel carries sentences and mechanism lines only — one weight,
  percentage or pass-threshold turns it into the analytic board they explicitly did not ask for.
- Extending a board is additive: widen the canvas, add the panel where the user pointed, move nothing,
  delete nothing. Stray nodes stay and are offered for removal.
- A restyle request re-enters the generator: edit the layout table / `MODEL`, render to a **new** file
  name (`board_v4.png`) so the rejected version stays comparable, then view the new render. Never
  restyle by editing the generated HTML or SVG.
- Default to the light card look on a new framework board; switch to dark only on request.
- A board that is a project baseline is filed twice — vault record and engineering design page — each with
  a row in its index. Sending the PNG again is not filing.

## Done when
Every handwritten node appears exactly once and one spine carries the sequence in the whiteboard's own
order, uncertain words are marked `★` and listed for the user,
struck items are shown as rejected, the rendered PNG has been viewed and has no clipped text, and both
PNG and SVG are delivered with their measured sizes. For the filed branch: both documents exist, each
image resolves through a path relative to its own document, and both index tables carry a row. For the
editable branch: the editor screenshot has
been viewed, drag redraws connectors from live node rects, all exports write non-empty files, and the
zip (not the bare `.html`) is delivered with its own text part. For the matrix branch: every row's 现状
cell is a verdict with its supporting number, the axis strip names a model per pipeline stage, the foot
blocks have been viewed at full size with no item outside its block, and the PNG's pixel size is read from
its header rather than assumed. For the derivative branch: node names and palette match the sibling board,
every added number is either sourced from the project or tagged 待定, and the new layer reads as yours
rather than as part of the mechanism. For the in-place branch: the widened canvas holds the new panel
without a node moving or disappearing, the panel follows the spine's order and carries no
weight/percentage/threshold, and the rendered PNG shows no editor toolbar.

## Related
Live app/window screenshots: `macos-window-capture` (it also holds the headless-Chrome page-render rules
for HTML pages). Turning notes into a document the user reads: `doc-package-delivery`. Media attachment
limits (one media per message): `render-preview-grading` → `references/media-handoff.md`.
