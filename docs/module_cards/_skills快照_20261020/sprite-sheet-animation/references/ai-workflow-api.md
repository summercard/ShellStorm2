# ai-workflow HTTP API (sprite-sheet pipeline)

Service base: `http://sc-arch-niri:7091`. Host `niri`, code at `/home/sc/projects/ai-workflow`. That host reaches GitHub over IPv4 only, so use `curl -4` / `git -4` there. After changing the service's code: `bun run build`, then `systemctl --user restart ai-workflow`.

The running service (a user systemd unit) keeps serving the **last built** `dist/` — a source change with no rebuild looks like nothing changed. `git fetch` + `git merge --ff-only` in `/home/sc/projects/ai-workflow` only updates the source tree; the app picks it up only after build **and** restart. Verify all four: the built bundle's mtime is fresh (`dist/index.html`), the new feature's text is present in `dist/static/*.js`, the service's Main PID changed, and `http://sc-arch-niri:7091` returns 200.

## Endpoints

| Call | Body | Returns |
| --- | --- | --- |
| `POST /api/projects` | `{"name": "<pid>"}` | 201 `{project}`; **409** when it already exists (then just reuse the name) |
| `POST /api/projects/:pid/assets?name=<file>` | raw image bytes, `Content-Type: image/png` | `{"image": {"id","name","width","height"}}` |
| `POST /api/projects/:pid/sheet-detect?maxFrames=N` | raw image bytes | `{ok, geometry:{frameWidth,frameHeight,gapX,gapY,offsetX,offsetY}, method:"blobs", frames:N, note}` — a **hint** only, see the SKILL.md key rule |
| `POST /api/projects/:pid/workflows` | `{"name": "<wf>"}` | `{"workflow": {"id", ...}}` |
| `PUT /api/projects/:pid/workflows/:wfid` | `{"workflow": {version,name,nodes,edges,viewport}}` | 200; **400 `The workflow is malformed.`** when the object carries extra keys |
| `POST /api/projects/:pid/workflows/:wfid/run` | `{"workflow": <same object>}` | 200, NDJSON stream |
| `GET /api/projects/:pid/workflows` | — | `{workflows:[...]}` |

A project id **is** its name (may be non-ASCII) — URL-encode it on every call.

## Workflow document

- Send exactly `{version, name, nodes, edges, viewport}`. `id` / `createdAt` / `updatedAt` are server-owned: including them fails the PUT with `The workflow is malformed.` (a `GET` of the saved workflow hands them back, so strip them before a re-PUT).
- To locate the real malformed field, validate locally with the project's own zod schema rather than guessing — `bun` needs its absolute path in a non-login shell.
- node: `{id, type, position:{x,y}, params:{}, size:{width,height}, view:{frame,selected}}`
- edge: `{id, source, sourceHandle, target, targetHandle}`
- ids must match `/^[A-Za-z0-9_-]{1,64}$/` (they become output filenames).

## Ports

`image` / `video` nodes have no input. Otherwise: `removeBackground`, `crop`, `scale`, `mergeNearby`, `frameLattice` = in `image` → out `image`; `spriteSheet`, `irregularSpriteSheet` = in `image` → out `frames`; `frameSample` = in `source` → out `image` (a video by frame number, a sequence by index); `meshGrid` = in `image` → out `mesh`; `downscale` = in `image` + `mesh`; `quantize` = in `image` + `reference`.

## Node params used by the sprite pipeline

- `image`: `{image: {id, name, width, height}}` — the asset **object** returned by the upload, not a string.
- `removeBackground`: `{backgroundColor, backgroundScope: "border", backgroundTolerance, colorDistance: "oklab", outlineRadius, alphaThreshold}`. Takes a **single image** (no sequence), so it runs on the whole sheet before the cut. `border` scope keeps white details inside the character.
- `spriteSheet`: `{frameWidth, frameHeight, gapX, gapY, offsetX, offsetY, skipEmpty, maxFrames}` — one Aseprite `ImportSpriteSheet`-style tiled rule; pass the measured geometry explicitly.

## Run stream

One JSON object per line: `node-progress {nodeId, stage, done, total}`, `node-result {node:{frames:[{url}]}}`, `error {message}`. The frames come on the `spriteSheet` node's `node-result`.
