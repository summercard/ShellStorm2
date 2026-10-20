# Driving a Native App or Game (no DOM)

Read this instead of steps 1–3 of `SKILL.md` when the thing to record is a **native window** — a Godot/Unity build, a packaged game binary, any app that is not a page you can inject JavaScript into. Steps 4–8 of `SKILL.md` (capture, verify, deliver, clean up) still apply; the differences are how you drive it and how you build the timeline.

## 1. Find the window and bring it frontmost
Injected events go to whichever window has focus, so activation is not optional:
```
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Godot") to true'
```
Use the process name from `ps` / the window owner, not the .app display name. If the app was already launched, do not relaunch it — relaunching resets the scene you were about to record.

## 2. Check for Quartz before choosing a driving method
```
python3 -c "import Quartz; print(Quartz.__file__)"
```
On this Mac it is already importable from the user site-packages (`.../Library/Python/3.9/lib/python/site-packages/Quartz`), so **do not pip-install it** — check first, then use it. Only fall back to `osascript … System Events keystroke` when the import genuinely fails; AppleScript keystrokes are slower and lose multi-key holds.

## 3. Drive with Quartz CGEvent from a small reusable script
Key presses post to the HID tap and are indistinguishable from hardware for a full-screen game:
```python
import Quartz, time
KEY = {'w':13,'a':0,'s':1,'d':2,'e':14,'r':15,'f':3,'space':49,'esc':53,'shift':56,'[':33,']':30}
def hold(name, secs):
    c = KEY[name]
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None, c, True))
    time.sleep(secs)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None, c, False))
```
Express a run as a comma string (`"w:2.2,sleep:0.6,e:0.15"`) so a beat list is data, not new code. Values are **virtual keycodes**, not characters.

A menu click needs an absolute position **and** a warp — posting a click at the current cursor location is not enough:
```python
p = (170.0, 257.0)
Quartz.CGWarpMouseCursorPosition(p); time.sleep(0.2)
for down in (True, False):
    ev = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown if down else Quartz.kCGEventLeftMouseUp, p, Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev); time.sleep(0.08)
```
Verified: this entered a level-select entry from a menu; a bare click without the warp did nothing. Coordinates are in **points** of the capture screen (the same space `screencapture` reports at 1×), so derive them from an unscaled still.

## 4. What injection cannot do
**A game that captures the cursor (any first-person viewport) ignores injected relative mouse motion.** Menus and buttons respond; the camera does not turn. Verified: warping the mouse and posting moves left the view unchanged, while the game's own debug keys (here `[` / `]`, 5° per press) did rotate it.
- Plan the shot list around keyboard-only actions: walking, doors, menus, UI panels, debug camera keys.
- For combat, aiming or a boss fight, the honest options are: the user drives while you record, or you shoot static angles.
- Say this limit in the delivery message instead of shipping a clip that silently has no combat in it.

Interactables also need proximity: pressing the interact key at the wrong spot produces a frame identical to before. Verify per beat (next section) rather than assuming the keypress did something.

## 5. Capture only the client area
Full-screen capture drags in the menu bar, the title bar and the desktop. Crop them away in the recorder itself so the clip is the game only:
```
~/.local/bin/ffmpeg -y -f avfoundation -capture_cursor 0 -framerate 30 \
  -pix_fmt uyvy422 -i "1:none" -t <secs> \
  -vf "crop=1600:900:0:106" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p <out.mp4>
```
- `-capture_cursor 0` keeps the pointer out of the frame.
- **Measure the crop box from a still; do not guess it.** `screencapture -x s.png`, then `ffmpeg -i s.png -vf "crop=W:H:X:Y,scale=800:-1" -y s_s.png` and look at the result; adjust until the window chrome is gone. On a 2880×1800 Retina screen a game window's client area landed at `crop=1600:900:0:106`.
- `-pix_fmt uyvy422` must precede `-i` (input-side); the `NSKVONotifying_AVCaptureScreenInput not linked` lines are a harmless warning.
- **Hide the other apps; do not rely on the game being frontmost.** A full-screen capture takes whatever is on the desktop, and any window that comes forward mid-run lands in the clip. Verified: the first 30 s recording had the game behind the desktop and other apps and was unusable. Hide them up front with `try`-wrapped System Events calls (`set visible of process "Electron" to false`, same for the chat client, Finder, settings and the proxy client), bring the game forward, and restore per section 8.
- **Pre-flight 10 s before driving a long sequence.** Record briefly, check the byte count and look at one frame, then only start the real run. At `crop=1600:900`, 30 s of real gameplay weighed 3.3–6.5 MB while the clip that had captured the desktop instead was **399 KB** — an order-of-magnitude gap, so a short clip under ~1 MB per 30 s means no game content: fix occlusion and re-record rather than driving a two-minute script into a dead frame buffer. Two full re-records were the cost of skipping this check.

## 6. Build the timeline from stills taken before each beat
There is no `window.__log` to read from a native app, so the timeline has to be produced while recording:
1. Drive to the next state, then pause.
2. `screencapture -x beat.png`, crop and scale it into the workspace, and **look at it** — copy into the workspace first, since `view_image` rejects `/tmp`.
3. Only when the still shows the intended state, start the recorder and replay that beat.

That still doubles as the evidence frame in the delivery table (时间 / 操作 / 画面). A beat whose still shows nothing new gets cut, not narrated.

## 7. Stitch the beats and verify
Join recorded segments without a demuxer list when the trims differ:
```
ffmpeg -y -i a.mp4 -i b.mp4 -filter_complex \
 "[0:v]trim=start=1:end=17,setpts=PTS-STARTPTS[a];[1:v]trim=start=1:end=13,setpts=PTS-STARTPTS[b];[a][b]concat=n=2:v=1:a=0,fps=30[v]" \
 -map "[v]" -c:v libx264 -preset medium -crf 21 -pix_fmt yuv420p -movflags +faststart out.mp4
```
Then `ffmpeg -v error -i out.mp4 -f null -` must print nothing, and a 4-frame tile (`select='eq(n\,45)+eq(n\,300)+…',tile=2x2`) confirms the cuts land where intended. Keep the recorder running 1–2 s past the last beat so the tail is not cut mid-motion.

## 8. Give the user's desktop back
If windows were hidden or minimised for a clean capture, restore them in the same turn — one `try` per process so a name that is not running does not abort the rest:
```
osascript -e 'tell application "System Events"' \
  -e 'repeat with n in {"Electron","Feishu","Finder"}' \
  -e 'try' -e 'set visible of process n to true' -e 'end try' \
  -e 'end repeat' -e 'end tell'
```
Leaving the machine with the user's windows hidden is a failure of the task, not a side effect.
