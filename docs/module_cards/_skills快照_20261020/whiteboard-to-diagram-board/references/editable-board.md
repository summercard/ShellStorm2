# Editable Board: one model, two renderers

Branch of `whiteboard-to-diagram-board` for when the user wants to *keep editing* the board
themselves — "这个帮我做成一个可编辑的图版", "让我自己拖", "我要能改字的".

Do not build this when a picture is enough. The static SVG → PNG path is the default; the editor is
extra work and only pays off when the user intends to move or rename things later.

## 1. The model is the source of truth

Author one JSON layout model, then render it twice — static SVG/PNG for sending, interactive HTML for
editing. Two independent hand-written versions inevitably diverge on the first correction.

Top-level keys (verified shape, 1680×1080 board):

| key | contents |
|---|---|
| `w` `h` `bg` | canvas size and background colour |
| `header` | `kicker`, `title`, `line`, `meta[]` |
| `panels` | `id x y w h num title accent` |
| `cards` | section cards: `id x y w h num title accent` |
| `nodes` | `id x y w h main sub color` (+ optional `chip` / `small` for chips) |
| `edges` | `from to kind color` (+ `dash`, `label`, and `x` / `targets` / `lx` / `ly` for routed or hand-placed labels) |
| `notes` | free text: `x y text size color` |
| `legend` | `x y label color` |

Keep the generator (`build_board.py`) and the model file together; every fix is edit model → regenerate,
never edit the generated HTML.

## 2. Edge routing lives in one function pair

`edges[].kind` is a small vocabulary, each with a fixed route: `v` (down), `h` (right), `up` (back up),
`vskip` (down the left gutter when a node sits in between), `loopback` (side gutter, back to an earlier
node, `x` picks the gutter), `feedback` (down then into a right-side anchor), `bus` (down to a shared y,
across, up), `busv` (straight down), `bracket` (down out of a node, across to a gutter, then one stub per
`targets[]` node — the "one card unlocks three branches" shape). Anchors are computed from the node's
current rect at render time; `lx`/`ly` override a label position when the computed spot lands on a line.

Both the SVG exporter and the browser renderer must call the *same* routing code. If the editor stores
absolute arrow points, dragging a node leaves the arrow behind — and that is the bug the user notices first.

### Hand-routed polylines need their own guard

A `poly` edge carries absolute `pts` and has no `from`/`to`, so it must branch **before** the shared
endpoint check:

```js
if (e.k === "poly") { if (!e.pts || e.pts.length < 2) return; }
else if (!a || !b) return;
```

Verified failure: the render loop opened with `const a = byId[e.f], b = e.to ? byId[e.to] : null;` then
`if (!a || !b) return;`, which silently dropped **every** poly edge. The board still looked plausible
because the `v`/`h` routes survived, and the absent ones were exactly the hand-routed ones — the long side
loop back to 关卡, 装备进关, 物资回流成长, 下一间. Two successive coordinate edits changed nothing.

Decision rule: **a missing connector is a renderer question before it is a geometry question.** Re-routing
points cannot fix an edge the draw loop never visited. Prove the kind renders, then adjust coordinates.
After adding or changing an edge kind, count declared edges against connectors in the PNG
(`grep -c '"k":' build_board*.py`, then a 1:1 crop of each lane) instead of trusting the full-frame view:
a 2 px dashed line at 40 % downscale reads as "not there" whether it is missing or merely faint.

## 3. Editor mechanics (minimum that earns the name)

- `pointerdown/move/up` on the node group → drag; on `pointerup` persist.
- `dblclick` a node → position a real `<input>` over it; Enter commits, Esc cancels, blur commits.
- `localStorage` autosave keyed per board, plus an explicit 重置 that clears the key and reloads.
- Export buttons: **SVG** (serialise the live `<svg>`), **PNG** (draw at 2× on a canvas), **JSON** (the
  model after edits), **Excalidraw** (`.excalidraw` JSON — rectangles + bound text + arrow points).
- `?clean=1` hides the toolbar so headless screenshots show only the board. A board that predates the
  flag usually still carries the `body.clean` CSS rule — render a throwaway copy with `<body class="clean">`
  instead of editing the deliverable, or the first screenshot ships the 保存/导出 toolbar inside the PNG.

Canvas size is duplicated in five places, and the model's `w` is only one of them: `#wrap` width, the `svg`
CSS width/height, the `<svg viewBox>`, the `width`/`height` attributes, and the background `<rect>`. Widen
all five (plus the x of any right-anchored header `meta`) before re-rendering a board that had a panel
added to its side; one missed copy clips the board or leaves a grey band past the new edge.

Verified sizes for reference: editor 25 KB, 2× PNG 410 KB, Excalidraw export 128 elements / 110 KB.

## 4. Verify, then say what was verified

Screenshot the editor itself and `view_image` it:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --hide-scrollbars --force-device-scale-factor=2 --window-size=1680,1080 \
  --screenshot=board_v3.png "file:///…/board_editor.html?clean=1"
```

Headless proves layout, overflow and connector alignment — it does **not** prove drag feel. Report it
that way: "渲染已核验，拖动交互请主人试一下", not "已经能用了".

## 5. Delivering the editor

**A local `.html` cannot be attached to a Feishu message.** Verified rejection before dispatch:

```
Feishu media preparation failed before message dispatch: hostReadCapability permits only validated
plain-text documents and trusted generated HTML reports for local reads | path-not-allowed
```

Recovery that worked: copy the set to a Desktop folder, `zip` it, send the zip as the media part.

```bash
mkdir -p ~/Desktop/<Board>_图版 && cp board_editor.html board_model.json board_v3.png <board>.excalidraw ~/Desktop/<Board>_图版/
cd ~/Desktop/<Board>_图版 && zip -q -r <board>_可编辑图版.zip board_editor.html board_model.json board_v3.png <board>.excalidraw
```

- One media per message (`render-preview-grading` → `references/media-handoff.md`): the preview PNG and
  the zip are **two sends** with their own captions, not one call with two files.
- Keep the unzipped copy on the Desktop and tell the user the path — a zip is for forwarding, the folder
  is for opening right now.
- Close the loop explicitly: edit → 导出 JSON → send it back, and the next version is regenerated from
  the user's own layout instead of from guesses.

## Done when
The editor opens with no clipped text, every edge declared in the model is visible in the render,
drag redraws connectors live, all four exports produce files
(measured bytes), the preview PNG has been viewed, the zip is delivered with a text part and a media
part, and the user knows both the Desktop path and the export-JSON round trip.
