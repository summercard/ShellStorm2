---
name: app-interaction-recording
description: Use when asked to record a video of a running app, game or local web project actually being used — "把<项目>的玩法过程录一段", a gameplay or walkthrough demo, or proof that an interaction works end to end. For a web page it serves it over HTTP, opens a fixed-size Chrome window and drives it with injected JavaScript; for a native game or app window it drives keyboard and menu clicks with Quartz events. Either way it captures the screen with ffmpeg's AVFoundation device, verifies the clip by decoding it and checking frames against what the driving log or the pre-beat stills show, and states any action injection could not perform.
---

# Record a Real Interaction to Video

## When
- "把这个项目的玩法/操作过程录一段给我" — the user wants to see the thing work, not hear that it works.
- A feature must be demonstrated end to end (a counter moves, a panel opens, a character moves) rather than described.
- Not a still frame (`macos-window-capture`), not stitching generated shots (`ffmpeg-shot-assembly`), not driving a logged-in web console to produce an artifact (`web-console-session`).

## Pick the drive path first
- A **local web page** (or a page inside a browser you control) → steps 1–3 below: serve it, then inject JavaScript.
- A **native app or game window** (Godot/Unity build, packaged binary) → there is no DOM. Read `native-app-driving.md` for activation, Quartz key/mouse driving and the crop box, and use steps 4–8 below for capture, verification and delivery. Its pre-beat stills replace the page log as the timeline.

## Steps
1. **Serve the page over HTTP.** Start the server in the exec tool's **background mode**: `cd <project> && python3 -m http.server 8099 --bind 127.0.0.1`, then `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8099/` must print `200`. A page using `type="module"` and an importmap fails from `file://`, and a server started with `nohup … &` inside a plain exec session is reaped when that session ends. A first background attempt can also die on its own — check the port again right before recording, not just once.
2. **Open a dedicated Chrome window at fixed bounds.** Fixed bounds keep the frame size and any coordinates identical for the whole clip:
   `osascript -e 'tell application "Google Chrome"' -e 'set w to make new window' -e 'set bounds of w to {0, 0, 1440, 900}' -e 'set URL of active tab of w to "http://127.0.0.1:8099/"' -e 'end tell'`
   Use a fresh window you created, so `front window` is unambiguous and the user's other tabs stay untouched.
3. **Drive it with injected JavaScript.** Chrome must have **View → Developer → Allow JavaScript from Apple Events** enabled; without it `execute … javascript` errors out. Verified working form, which returns the expression's value:
   `osascript -e 'tell application "Google Chrome" to execute active tab of front window javascript "document.title"'`
   - **Long scripts: base64 + `eval(atob(…))`.** Every quote, newline and non-ASCII character in a multi-line script breaks the AppleScript string otherwise. `B64=$(base64 < drive.js | tr -d '\n')` then `javascript "eval(atob('$B64'))"` — verified returning `complete` for a multi-line script.
   - **Keys** go to `window`: `new KeyboardEvent('keydown', {code:'KeyW', key:'KeyW', bubbles:true, cancelable:true})`, and a "hold" is keydown → `await sleep(ms)` → keyup. **Clicks** go to the DOM node (`document.getElementById('dive-button').click()`), which is exact where a screen coordinate is a guess.
   - **Log inside the page**: push `Date.now() + ' ' + what happened` into `window.__log`, set `window.__done = true` at the end. This array becomes the caption timeline; do not reconstruct the timeline from memory afterwards.
   - Pace it: a script that fires all its actions in 2 s produces a clip nobody can follow. Sleep between beats and keep the whole run under about 60 s.
4. **Record the screen with ffmpeg.** `~/.local/bin/ffmpeg -y -f avfoundation -pix_fmt uyvy422 -framerate 30 -i "1:none" -vf scale=1280:720 -pix_fmt yuv420p -c:v libx264 -preset veryfast -crf 20 <out.mp4>`
   - The screen device is `[1] Capture screen 0` here (`ffmpeg -f avfoundation -list_devices true -i ""` lists it); `:none` disables audio.
   - **`-pix_fmt uyvy422` belongs before `-i`, for the input.** Putting `yuv420p` there fails with `Selected pixel format (yuv420p) is not supported by the input device` — the screen device only offers `uyvy422`, and the encoder converts to `yuv420p` on the output side.
   - `objc[…]: class 'NSKVONotifying_AVCaptureScreenInput' not linked into application` is a harmless startup warning, not a failure.
   - The device captures at the Retina backing scale (2880×1800 here), so state `-vf scale=` explicitly; un-scaled 3 s already weighed 0.5 MB.
   - Start the recording **before** the first injected action, and let it run a couple of seconds past the last one.
5. **Read the page's log, then stop.** One more `execute … javascript "JSON.stringify(window.__log)"` proves each step actually fired. If a step is missing, fix the script and re-record — never narrate an action the log does not contain. Then `window.__done` is the stop signal for the recorder.
6. **Verify before delivering.** Duration within about 1 s of the plan; `ffmpeg -v error -i <file> -f null -` prints nothing (full decode, 0 errors); then pull 3–4 frames at the logged timestamps (`-ss <t> -frames:v 1 -vf scale=1280:720`), **copy them into the workspace** (`view_image` and chat attachments reject `/tmp`), and look at each one. The frame must show the state the log claims — a resource counter that went 0→2, a depth readout that changed. With no page log (native app), use the stills taken before each beat as both the timeline and this evidence.
7. **Deliver with the table.** One `MEDIA:` line, the measured length/frame size, and a 时间 / 操作 / 画面 table generated from `__log` (native app: from the pre-beat stills). Name the two or three frames that prove it was real interaction rather than a static capture, and state any action you could not perform.
8. **Clean up.** Close the window you made (`tell application "Google Chrome" to close front window`) and stop the background server session. Never kill Chrome by app name — the user's own windows live in that process.

## Decision rules
- Every caption line must map to a log entry — or, for a native app, a pre-beat still — that actually shows it happened; an event that did not fire is cut, not embellished.
- **A game that captures the cursor ignores injected relative mouse motion**: menus answer clicks, the camera does not turn. Plan keyboard-only shots, or have the user drive while you record, and say which actions you could not perform instead of shipping a clip with the combat silently missing.
- Injecting into the page beats posting screen coordinates: coordinates break the moment a window moves, and a click that lands on the wrong widget still "succeeds".
- macOS may require **Screen Recording** permission for the process running ffmpeg; a clip that consists of a black frame is that grant missing, not a broken app.
- Record on a clean desktop: a screen capture includes whatever notification or window happens to appear.
- If the finished file exceeds Feishu's 30 MB cap, encode a delivery copy at the same frame size with a higher CRF and keep the full-quality original in the library, stating which is which — do not trim the demo to fit.

## Done when
The video shows the interaction happening, its duration matches the plan, it decodes with 0 errors, the frames at the claimed moments show those states, the driving record confirms every step fired — `__log` for a web page, the pre-beat stills for a native app — the limits of injection are stated, and it was delivered with a caption table plus the paths of the frames used as evidence.
