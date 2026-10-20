---
name: comfyui-remote-run
description: Use when asked to actually run a ComfyUI workflow — "把这台机器的 ComfyUI 跑起来，用远程接口提交 <workflow> 出一张/一段" — i.e. serve ComfyUI on a host (often remote) and submit a workflow through its HTTP API, generate an image/video/audio from a stored workflow JSON, or prove by execution that a workflow a static audit passed really produces output. Covers making the service reachable from another machine, building an API-format prompt graph, resolving exact input names and enum values, polling the queue, downloading the produced files, driving a long multi-shot batch, deploying a queue folder + worker on the host so jobs survive ssh teardown, and answering "那台机器现在怎么样" with a read-only state report (live port, idle or busy, last outputs).
---

# Run a ComfyUI workflow through its HTTP API

## When
- "把 <host> 的 ComfyUI 拉起来，然后用远程接口提交 <workflow>" — serve ComfyUI and drive it from a peer machine.
- Generate a still/video/audio from a workflow JSON that lives on that host, without opening the browser UI by hand.
- Turning a passed static check into proof: present models + nodes is a precondition, execution is the proof
  (that precondition audit is `comfyui-workflow-readiness`).

## Steps
1. **Serve it so a peer can reach it.** ComfyUI binds loopback by default, so a remote call needs the listener
   opened: `--listen 0.0.0.0 --port 8188`. Confirm **from the client machine**, not the host: `GET
   http://<host>:8188/system_stats` returns 200 with `comfyui_version`; `/queue` and `/object_info` answer 200 too.
   The URL/scheme and any firewall scoping (`100.64.0.0/10` only) are the job of `tailnet-host-control`.
   - **On Windows, every child of the ssh console dies with it — `Start-Process`, `start /b` and a plain `&` alike.**
     A hidden `Start-Process … -PassThru -RedirectStandardOutput` reported a PID, left both logs at **0 bytes**, and the
     process was gone by the next check. Verified again with `start "" /b pythonw.exe worker.py`: it logged its
     startup line, claimed a queued job (file moved to `done\_running_…`), then vanished — process list empty, its
     `status.json` frozen at the startup timestamp. Only a process the OS creates on its own behalf survives the ssh
     teardown. Launch through WMI instead, from a `.bat` that sets an unbuffered stream and a log:
     `@echo off` / `cd /d <bundle>` / `set PYTHONUNBUFFERED=1` /
     `.\python\python.exe .\ComfyUI\main.py --listen 0.0.0.0 --port <port> --disable-auto-launch > E:\comfy_boot.log 2>&1`,
     then `Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='cmd.exe /c E:\<bundle>\start.bat'}`
     (wrap that in `-EncodedCommand` — see `tailnet-host-control` → `windows-remote-execution.md`).
     Verified: `RET=0 PID=10620`, the ssh dropped, the log kept filling, and the port answered 200 ten minutes later.
     Nesting that call inside `powershell -NoProfile -Command "…@{CommandLine=\"…\"}…"` through ssh breaks on the
     quoting (parser error `UnexpectedToken`, localized as 缺少表达式). Write a small `.ps1` containing the
     `Invoke-CimMethod` call and run it with `-File`; it returned `pid=18136 rc=0` and the process was still alive on
     the next check. Same `.ps1`-and-`-File` form for any repeatable remote launcher.
     `PYTHONUNBUFFERED=1` is what makes the log readable: redirected python stdout is **block-buffered**, so an empty
     log means buffered, not crashed. The attached form (`ssh <host> "cmd /c \"cd /d <bundle> && python\python.exe
     ComfyUI\main.py --listen … 2>&1\""`) also binds, but only while that exec session lives, and it shows nothing
     until the run ends. Either way, `--listen` only helps if the process actually stays up.
   - **Take the port from the host's own launch script, not from a note.** Verified: the bundle's
     `comfy_run_8189.bat` said 8189 while the machine's recorded address said 8188 — the remembered port answered
     `000` on a healthy server. List the bundle root for `comfy_run*.bat` / `start*.bat` before probing.
   - **Prestartup looks exactly like a hang.** A node-heavy bundle spends **~10 minutes** importing custom nodes
     (`comfy-env` scanning `nodes.blender` alone took 60.5 s; `ComfyUI-Manager`, `Crystools`, `GGUF`, `Sharp` follow).
     The readiness signal is the log's `Starting server` / `To see the GUI go to: http://0.0.0.0:<port>` line **plus**
     a client-side `/system_stats` 200. A live python PID, rising CPU or a growing log is not that — process ids are
     not a running server.
   - **Stop the right process**: the owner of the listening socket, not "a python" — several python processes exist
     on these hosts (`Get-NetTCPConnection -State Listen -LocalPort 8188` → `OwningProcess` → `Stop-Process -Id`).
     Killing by image name hits unrelated interpreters.
2. **Build the API graph** — do not drive the browser. `{"prompt": {"<id>": {"class_type": "<Type>", "inputs":
   {...}}}, "client_id": "<any>"}`; a link is `["<node id>", <output slot>]`. Read the stored workflow
   (`<ComfyUI>/user/default/workflows/*.json`) as the source of node types, but **leave that file untouched** —
   submit a separately built graph.
   A stored UI graph is not the API graph. Nodes with `"mode": 4` are **bypassed**: they never execute and their
   inputs pass straight through, so collapse each bypass chain instead of transcribing it (verified: a 19-node
   MiniMax-H3 “导演台” workflow reduced to 6 executable nodes — UNETLoader, CLIPLoader, two VAELoader, the Director
   node, `CreateVideo`/`SaveVideo` — and still produced the intended clip). Node `inputs[]` entries that carry a
   `widget` key give the API input names in `widgets_values` order; when the counts disagree, trust the per-class
   `/object_info/<Type>` over that order.
3. **Resolve every input name and enum from the server before writing it.** `GET /object_info/<ClassType>`
   lists the exact `required` input names and a COMBO's allowed `options`. Do not copy a display/localized label:
   verified, `MiniMaxH3AudioConditioningT8.task_type` accepts only `auto|T2VA|I2VA|FL2VA|L2VA|Ref2VA|Hybrid`, and a
   localized value was rejected with `value_not_in_list` (a full round trip lost to one guessed string).
   - **Never fetch the whole `/object_info` dump** to shortcut this. It is multi-megabyte and truncates: repeated
     attempts returned `Unterminated string …` after 2.1 MB, then a still-growing 5.2 MB body two minutes in. One
     class at a time is fast, complete, and the only reliable form.
   - Enums that differ from the UI label, verified: `SaveVideo.format` accepts only `auto|mp4` — the UI's
     `video/h264-mp4` is rejected with `value_not_in_list`. `SaveVideo` also takes a single `VIDEO` input, so wire
     `CreateVideo` (`images` + `fps`, optional `audio`) into it rather than an image/audio/fps trio.
   - Widget inputs the UI presents as section headers still count as required values and must be sent with their
     declared default text (e.g. `MiniMaxH3Director` needs `bd_grp_sample: "采样设置"`,
     `bd_grp_advanced: "高级采样"`, `bd_grp_perf: "性能"`).
4. **Upload local media first if the graph needs it.** `POST /upload/image -F "image=@<file>;filename=<name>"`
   returns `{"name":…, "subfolder":"", "type":"input"}`; that returned name is what `LoadImage.image` takes. It then
   appears in the `/object_info/LoadImage` list — check there rather than assuming the upload landed.
5. **Submit and read the response.** `POST /prompt` (JSON body). A validation failure comes back as
   `{"error": {"type": "prompt_outputs_failed_validation", …}, "node_errors": {…}}` with **no `prompt_id`**, so
   check for a non-empty `node_errors` and fix per node before resubmitting. A `prompt_id` with empty
   `node_errors` ⇒ queued; keep the id, and never treat the id alone as success either.
6. **Wait on the queue, not on a hunch.** `GET /queue` shows it in `queue_running`; `GET /history/<prompt_id>`
   stays `{}` until the run completes. A first run also spends minutes loading the text encoder + model before
   sampling starts, so poll on a generous interval and do not read `{}` / `queue_remaining: 1` as a hang.
   An HTTP 502 from `/queue` is **not** a dead host: verified, the same moment `curl` returned `queue: 200` and
   `stats: 200`. Re-probe `/system_stats` (or `curl`) before concluding the server is down or restarting anything.
7. **Read the result and fetch the files.** History then holds `status.status_str == "success"` (or an error, with
   per-node messages) and `outputs["<node>"]`, whose key is the node's own output name — `VHS_VideoCombine` writes
   under **`gifs`** even for an `.mp4`; image savers under `images`. Each entry has `filename`, `subfolder`,
   `type`. Download with `GET /view?filename=<f>&subfolder=<s>&type=output`.
   **A Windows portable bundle keeps output one level down: `<bundle>\ComfyUI\output`, not `<bundle>\output`** —
   verified `PathNotFound` on the shallow form while the nested one listed the batch folders. List it before globbing,
   and read `subfolder` in the history entry as relative to that root.
8. **Verify the artifact before reporting**: non-zero size and a real container probe (a 3.0 MB `ISO Media, MP4`
   file, not a 0-byte or error page), then hand it over. A truncated download still passes that probe — the header is
   written first — so when a file is well under its siblings' size (verified: 646 KB where 938 KB was expected), re-fetch
   it and require a clean decode (`ffmpeg -v error -i <f> -f null -`); the decode-check procedure is `ffmpeg-shot-assembly`
   step 7, and that same pass is what catches a silent `-c copy` concat truncation. Without `ffmpeg` on PATH, `mdls -name kMDItemDurationSeconds -name kMDItemPixelWidth -name kMDItemPixelHeight <file>` reads duration and dimensions on
   macOS, `qlmanage -t -s <w> -o . <file>` renders a poster frame, and a bundled
   `~/Library/Python/3.9/lib/python/site-packages/imageio_ffmpeg/binaries/ffmpeg-macos-*` can step frames. Copy any
   still into the workspace before inspecting it — `view_image` rejects paths outside its allowed roots.
   - **Specs passing is not the same as the shot working — look at a frame from every shot before calling a batch
     done.** Verified: a 20/20 batch passed duration (3.00 s), 864×480, size and byte-total checks, and still had
     three unusable shots that only showed up on inspection: a splash plume swallowed the subject on the dive opener,
     one "underwater" shot read as an aerial of the city, and one had drifted to a different hairstyle in a stiff
     T-pose. Extract one frame per clip (`ffmpeg -ss 1.5 -i <clip> -frames:v 1 <png>`, `-ss` before `-i`), view them
     together, and judge action readability and character continuity before reporting success.

9. **Drive a multi-shot batch from a journal, not from a re-typed tag list.** One loop: submit a tag → record
   `tag prompt_id` in a state file the moment `/prompt` answers → poll that id → download → next tag. A "skip when the
   output file already exists" guard protects **finished** shots only, not in-flight ones: verified, re-running a
   partial list 20 s later resubmitted a tag whose job was still running (`v01s2 submitted e60b0d78` …
   `v01s2 submitted 7e8926ed`), and the duplicate queued behind the original on the same single GPU. On restart read
   the journal plus `/queue` and `/history/<id>`, then resume at the first tag that has neither a finished file nor a
   live id. An exec handle reporting `No active session found` is not proof the loop died — the journal kept
   advancing after the handle was gone; read its tail before resubmitting anything.
   - **A batch that must outlast the turn runs under launchd, not `nohup … &`.** Detaching reaps the loop the moment
     the exec session ends (`disown` does not help, `setsid` does not exist on macOS), so a 27-shot run started that
     way dies mid-batch; hold it in a foreground background-exec session while it is pollable, and when that handle
     is gone mid-batch relaunch the same loop via `launchctl submit -l <label> -- /bin/bash <script>` and poll the
     script's own log (see `cli-agent-delegation` step 3 for the verified reap behaviour and `launchctl remove`).
   - To pass the tag list on macOS zsh, `TAGS=$(…)` used as `$TAGS` arrives as **one** argv entry (the runner logged
     the entire list as a single `unknown`); expand with `${=TAGS}` or pass an array.
   - **Adding shots to an existing batch: extend the original runner, do not start a second pipeline.** `import <runner> as base`, register only the new tags in a dict, `base.SHOTS.update(...)`, and loop those tags through the same submit → journal → download path with `base.build` / `base.OUT` unchanged; the exists-guard then skips everything already rendered and the new clips inherit the same prompt scaffolding, folder and specs (verified: 4 shots added to a finished 20-shot set, 4/4 at 3.00 s / 864×480, old files untouched). Re-typing the builder into a new script is what diverges on the next prompt fix.
   - **Redo a rejected subset by moving files aside, not by deleting and not by re-running the batch.** Move the bad
     clips into `<out>/_rejected/`, leave the good ones in place so the exists-guard skips them, and invoke the runner
     with just those tags. Verified: three re-shot after a prompt rewrite, one per job, ~80 s each, and the batch
     count went back to 20 with the replaced files byte-different from the rejects.
   - **A persistent queue worker beats a local loop for long unattended batches.** Deploy it once on the host:
     `queue\` (one JSON per job), `done\` (one result JSON per finished job), `out\` (downloaded artifacts),
     `status.json` (`state` / `current` / `done_count` / `last`), `logs\worker.log`, and a `template.json` that is one
     successful `/history` entry's `prompt` graph, with only the per-job fields (`global_prompt`, `total_frames`,
     `seed`, `SaveVideo.filename_prefix`) overwritten from the job file. The local agent then just copies a JSON into
     `queue\` — nothing depends on an ssh session staying up. Verified: the worker claimed an uploaded job and
     submitted `prompt_id=…` on its own; GPU went to 85 % with the graph loading.
     - **Deploying it needs a working ssh/scp channel; when those hang, drop the queue and drive the API from the
       client.** Verified: `scp` to `queue\` timed out while ComfyUI's HTTP port answered normally, and the same
       `template.json` driven locally (`/prompt`, then `/history/<id>` and `/view`) accepted a 27-shot re-render one job at
       a time, overriding only prompt / frames / fps / width / height / seed / `filename_prefix`. Do not spend turns
       repairing a transfer path that the API does not require.
     - Keep the job file declarative: `{id, prompt, frames, seed, fps, width, height, prefix, free_first}`; the
       worker owns the `/free` check, submit, poll, download and the done record. Move a claimed job out of `queue\`
       before running it (that move is the claim), and write `status.json` through temp-file + `os.replace` so a probe
       never reads a half-written file.
     - **A `/free` that returns an empty body is not a failed unload, and low free VRAM between jobs is normal.**
       `POST /free` answers 200 with no JSON, so a client that parses the reply logs `Expecting value: line 1 column 1`
       and a pre-submit guard reports “VRAM 紧张” before every shot — verified: the shot submitted after that error
       completed normally (`s01a` downloaded), the loop went on to the next tags, and `vram_free` read 13.2 GB → 10.4 GB
       → 0.4 GB as successive models loaded. Do not retry `/free`, do not insert sleeps, and do not abort a batch on that message; gate on
       `/queue` being empty and `/history/<id>` reporting `success` instead.
     - **A job id is a dedupe key, so reusing one is silently skipped, not re-run.** Verified: after an art-direction
       change I requeued `s01a` under its old id; the worker found `done\s01a.json`, moved the new job to
       `done\s01a.json.skipped` and went on to `s01b`… with no error anywhere — the batch came back one shot short.
       Delete `done\<id>.json` (and any `_running_<id>.json`) before requeueing a changed render, or version the id.
     - **`done_count` is not a progress number**: it counts every `.json` under `done\`, including `_running_*.json`
       and `*.skipped`, so one finished job can read as 2. For progress, count `done\*.json` names that do not start
       with `_`; keep that rule in the probe script rather than eyeballing the field.
     - **Report completion from `done\` + `status.json`, never from process liveness or an empty queue.** A worker
       that died mid-job leaves `state:"running"` frozen — verified: `status.json` stuck at its startup timestamp
       while no python/pythonw process existed. A stale `updated` field is a failure signal, not a busy host.
     - Watch the queue headlessly with a condition job (`automation-condition-watcher`) whose probe script prints
       one compact JSON line. Its trigger script must read the exec output as `res.aggregated` — reading
       `res.stdout` yields `''` and the watcher silently never fires.
   - **A delegated loop dies of its own log, so cap what the delegate reads.** Verified: a subagent running a 20-shot
     batch for an hour ended with *Newest session context cannot fit the model-context limit without splitting a tool
     frame* and returned no report — the work itself was intact on disk. Brief any such delegate to redirect all job
     output to files, read only `tail -c 600`, never `cat` a log or paste a full `ffprobe`, print only the two numbers
     it needs, and append one line per finished tag to a progress file so a successor resumes from disk instead of
     from its own transcript.

## Report the host's state (read-only branch)
Asked "那台机器怎么样了 / 现在空着吗" — answer from live reads, never from a remembered port or an earlier note. Start nothing, stop nothing.
1. **Take the port from the running bundle, not from memory.** Both 8188 and 8189 can appear in notes; only the listening one answers. Verified: 8188 returned `000` (connection refused) while 8189 returned 200 on the same healthy host. The bundle root's `start*.bat` / `comfy_run*.bat` names the real one.
2. **One `/system_stats` gives the hardware picture**: `devices[0].name`, `vram_free`/`vram_total`, `system.ram_free`/`ram_total`, `comfyui_version`.
3. **Idle or busy is queue + VRAM, not CPU or RAM.** Empty `queue_running` and `queue_pending` with VRAM near free means idle. A python process holding ~24 GB RAM is a warm server that has models cached — not a job in progress (verified: 24 GB RSS, 0.2/25.8 GB VRAM, empty queue).
4. **What it last produced, and when it stopped**: `GET /history?max_items=<n>` gives `status.status_str` plus `status.messages` entries `execution_start` / `execution_success`, each carrying a millisecond `timestamp`. On a host you cannot shell into, those two numbers are the only honest answer to "when did it finish" and "why is it idle now" (verified: last `execution_success` 15:41, queue empty and VRAM 0.3/24 GB free at 17:48 ⇒ finished two hours ago, models still cached). With shell access, newest mtimes in the output tree (path rule in step 7) confirm the same.
5. **Confirm a remembered spec from the artifacts, not from memory.** Asked "之前说每个视频 10 秒、发 20 个去跑，是这样吗", the answer is countable: distinct filenames across history `outputs` = shots that really ran, `ffmpeg -i` on one or two downloads = real duration, `execution_*` timestamps = the window. Verified: 10 job entries but only 8 distinct shots (`s01 s03 s06 s20–s24`), 3.00 s each — so "20 × 10 s" was never executed. Report what ran and what the plan appears to have been as two separate statements, and never agree to a spec you cannot find a record of.
6. **Which install is actually running**, when several exist: the python PID's `Path` (not `CommandLine`, which is empty without elevation) names the bundle.
7. Report in one block: online and by which port/version, GPU and free VRAM, idle or busy, last outputs with timestamps, disk free on the bundle's drive, RAM headroom. Say plainly that a status check ran nothing.

## Decision rules
- **The base model variant and the `task_type` family must agree.** The MiniMax-H3 pack's own rule: r2v / v2v / rv2v
  need the `ref2va` base, t2v / i2v / fl2v need the `fl2va` base. When the stored workflow's `task_type` and the
  `UNETLoader.unet_name` disagree, pick the `task_type` matching the **loaded base** and say you did (verified: an
  `fl2va` base with one reference image ran successfully as `I2VA`, giving a 1152×864 5.2 s clip with native audio).
- **Audio/video conditioning length is a frame count, not seconds.** Wall-clock duration = `length` / the output
  node's `frame_rate` (verified: `length` 124 at 24 fps ≈ 5.2 s). State the fps you used; a stored `frame_rate`
  differing from the one you pass is a deliberate choice, not a default. The H3 Director names the field
  `total_frames` (default 124 ≈ 5 s at 24 fps, snapped to the 17k+5 grid, so 10 s ≈ 243 frames) — read the exact
  name from `/object_info/<Type>` instead of assuming `length`.
- **A 0-byte `/view` download means the file is absent, not that the clip is empty.** Verified: two names from an
  earlier job returned 0 bytes while three siblings downloaded fine; re-read the history entry's `subfolder` before
  re-running anything.
- `node_errors` is the server's own input validation and the cheapest fix loop — prefer it over reading the host's
  run log, and use the log only when the failure is at load/execution time.
- These graphs are heavy: expect the GPU to be saturated for the whole run (observed 100 % util, ~23.8/24.5 GB).
  Report per-step time and total, not just "done", and do not start a second job on the same host meanwhile.
  Budget from it: a 864×480 / 124-frame t2v on a 4090 took ~7 min from submit to `success`, load included, so a
  9-shot batch is roughly an hour — submit it as one background loop that polls each id instead of babysitting.
  Only the **first** job of a batch pays that load: verified on the same host, the opener took 300.9 s and every
  following 80-frame shot at 864×480 finished in 57–60 s. Quote the warm number when estimating a long batch
  (60 shots ≈ 1 h), and do not promise that rate until the second job has actually run.
- **Pin the deliverable spec before queueing a long batch, and re-pin whenever it changes.** Style, per-shot
  duration/frame count, shot count and number of outputs are four separate decisions the user may revise; state them
  in one line and get a yes first. Verified: a plan became 10 videos × 4 shots × 3 s in one style after the first
  render and the spec had been something else, so already-queued work was wasted. When it changes, stop the running
  loop, re-render **one** shot in the new style for approval, and only then batch.
- **A world rule is a negative constraint in every prompt, not a chat-level art direction.** A style word ("卡通") does
  not stop the model from inventing geography: verified, a water-world batch returned shots with coastline, forest and
  hillsides that had to be discarded. Write the prohibition list into each prompt (no land / shoreline / forest / dry
  ground; water is the ground) and keep a one-line world bible that every prompt is checked against before queueing.
- **Lock a recurring character with a reference sheet before the batch.** Generate one four-view sheet (front / side /
  back / close-up, plain background) with the image skill, get the user's yes on age and gender, and pass that sheet as
  an image input to every shot containing the character; otherwise the face and outfit are re-invented per shot. Identity
  changes after rendering mean re-running the entire batch — ask before queueing, not after.
- **Prompt text for a reference/persona workflow is content you guessed when you cannot see the supplied image —
  say so, and offer to re-run with the user's own description rather than presenting the output as intended.
- **Name the camera side and the body pose, and keep effects small.** An action word ("跳入海中") does not place the
  camera or the body: verified, the first dive shot rendered a giant splash with the character reduced to a dark speck,
  while re-prompting with "背对镜头、镜头在她身后略高处平视、画面里只出现她的背影和半个屋顶、水花很小只有零星气泡"
  produced a readable opener. A "不出现正脸" clause in the shared style prefix does **not** control this — verified, a
  rooftop wide shot still returned the character facing the camera until 背对镜头 / 侧后方 was written into that
  shot's own sentence. Camera side belongs in the per-shot text, not the global prefix. Same failure shape on an
  underwater shot that read as an aerial — say the angle
  ("侧面近景") and the water cues ("浑浊、悬浮颗粒、上方是暗蓝水面、不是俯瞰"). For a swimming/diving pose, spell out limb
  direction ("身体前倾、双臂贴在身侧向后、双腿并拢向后蹬") or the model returns a floating T-pose.
- **Rewrite the drift-prone identity tokens into every prompt, not just the reference sheet.** Verified drift with one
  reference image still supplied: hair changed to short spiky, and goggles sat on the eyes in some shots and pushed to
  the forehead in others. Re-state hair, headwear position and outfit per prompt; treat a cross-shot mismatch as a
  continuity bug to fix before assembly, not as acceptable variance.

## Done when
The prompt reached `status.status_str == "success"` and the produced file has been downloaded and probed, or the
exact blocking node error is reported with the value the server actually accepts.

## Related
Static pre-check of models/nodes/GPU and the "bundle won't run here" verdict — `comfyui-workflow-readiness`.
Reaching the host, its Windows command limits, retry-on-DERP behaviour, and scoping the port's firewall —
`tailnet-host-control`.
Putting a downloaded still/video into the user's chat (one media per message, verifying a truncated copy) —
`render-preview-grading` → `references/media-handoff.md`.
