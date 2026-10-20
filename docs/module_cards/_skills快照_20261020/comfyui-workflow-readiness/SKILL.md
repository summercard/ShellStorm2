---
name: comfyui-workflow-readiness
description: Use when asked whether a ComfyUI workflow can be used on a given machine — "把 <host> 的 ComfyUI 打开，里头有个 <workflow> 看一下能不能使用" — or to audit a ComfyUI install/bundle that was just copied to another host, or to judge from outside whether a running ComfyUI host already has the models a workflow needs. Covers whether the bundle itself can run there (a Windows portable package cannot run on Linux), whether the GPU is usable, and a static check of each workflow's referenced model files and node classes before any run is attempted.
---

# Audit whether a ComfyUI workflow will run on a host

## When
- "把 <host> 的 ComfyUI 打开，里头有个 <workflow> 工作流看一下能不能使用" — serve ComfyUI and judge a named workflow.
- A ComfyUI install was just copied/transferred to another machine and its runnability is in question.
- Not the same as launching a desktop app: ComfyUI is a **web service**, so verification is by its HTTP port and
  log (`remote-gui-app-launch` is for a windowed app on a remote Linux desktop).

## Steps
1. **Identify the install and read its layout on the target host.** A Windows portable bundle is recognisable by
   `绘世启动器.exe`, `.launcher`, `.app_path`, a bundled `python/` (Windows CPython), an Electron runtime folder
   (`程序文件/` holding `chrome_100_percent.pak`, `libEGL.dll`, `icudtl.dat`, `ffmpeg.dll`, `d3dcompiler_47.dll`),
   and `*.bat` launchers. **Such a bundle is Windows-only** — its embedded interpreter cannot run on Linux; say so
   instead of trying to launch it.
   **Several installs can coexist on one host — rank them by contents, not by path.** Enumerate every drive first (`cmd /c dir /s /b /ad <drive>:\*omfy*` per drive, or one PowerShell `Get-ChildItem -Directory -Recurse`), then read each candidate's `models\diffusion_models` and `models\text_encoders` sizes. Verified: `H:\ComfyUI` and `H:\kirtaAI\ComfyUI` were both fully stocked SD-era bundles with those two directories at **0 GB**, while the target MiniMax-H3 pack was a third tree on another drive (`E:\comfyui_h3\Comfyui-WF-2026.8.8`, 70.8 GB diffusion + 39.9 GB text encoders). The first ComfyUI folder found is not evidence of the right one — and the user may have to tell you that ("你可能找错了") only after a wrong report.
2. **Check the GPU works before predicting how it will perform.** `nvidia-smi`. `Failed to initialize NVML:
   Driver/library version mismatch` means kernel module and userspace library disagree — compare `uname -r` with the
   installed kernel package (`pacman -Q linux`) and `dkms status`: a *running* kernel older than the installed one
   (module built for the newer kernel) is a pending reboot, not a broken card. Report it and **ask before rebooting**.
3. **Inventory the workflows**: `<ComfyUI>/user/default/workflows/*.json`, and parse `nodes[].type` per file. A pack's shipping examples are often the only copy of a model's working graph — for MiniMax-H3 they live in `<ComfyUI>/custom_nodes/ComfyUI_MiniMaxH3_Director/example_workflows/` (t2v, i2v, fl2v, r2v, v2v, rv2v, plus localized "加速版/分段版") and `comfyui-minimax-h3-audio-T8/examples/workflows/` — so look there before concluding a host has no workflow for that model.
4. **Resolve every node type in two places, because both exist**:
   - Python: `grep -rl "<Type>" <ComfyUI>/custom_nodes --include=*.py`, plus builtins in
     `<ComfyUI>/comfy_extras/nodes_*.py` (e.g. `ComfyMathExpression`, `ResolutionSelector`, `PrimitiveStringMultiline`).
   - Frontend-only: `grep -rl "<Type>" <ComfyUI>/custom_nodes --include=*.js`. A node defined only in a pack's
     `web/*.js` (e.g. `SetNode` from kjnodes, `Fast Groups Bypasser` from rgthree) looks *missing* if you grep `.py` only.
5. **Resolve every model the workflow references** — filenames ending `safetensors|ckpt|pt|pth|gguf|onnx` inside the
   JSON — against `<ComfyUI>/models/**`. Match the **exact filename, not the stem**: one workflow asked for
   `upscale_models/RealESRGAN_x4plus.pt` while the bundle ships `RealESRGAN_x4plus.pth`; the node errors until renamed.
   - **A near-empty `models/` proves nothing — these bundles redirect it.** Check `extra_model_paths.yaml` (and the
     launcher's `*.json`) for extra search paths before reporting a model missing, or just ask the running server
     (see the HTTP branch below). Verified: `models/diffusion_models` and `models/text_encoders` were both 0 GB, yet
     `/object_info/UNETLoader` listed three MiniMax-H3 checkpoints, because an extra search path pointed at a separate
     work drive. That disk-only reading would have produced a false "cannot run" verdict.
6. **Report a per-item verdict** per workflow: bundle runnable on this host (yes/no), GPU usable, node types
   present/missing, model files present/missing.
7. **If the verdict is "bundle won't run here", the payload is still reusable**: `models/`, `user/default/workflows/`
   and `custom_nodes/` are ordinary files; only the runnable part (`python/`, launchers, `.exe`) is Windows-bound.
   Recommend a native install plus a read-only `extra_model_paths.yaml` mount of those directories instead of
   re-downloading 100+ GB. That route is **verified**: `comfyui-native-install` carries the install, the mount, and the
   API-side proof that the mounted models are actually visible to the loaders.

## Audit a host you can reach only over HTTP (branch)
Asked whether some other machine could run the workflow, and you have no shell there (or only 8188 is exposed) — the server answers the model question itself; no filesystem access needed.
1. **Per loader, read its COMBO list**: `GET /object_info/UNETLoader` → `UNETLoader.input.required.unet_name[0]`, and the same for `CLIPLoader.clip_name` / `VAELoader.vae_name`. That array is the exact installed filename list, the same truth as `models/**` on disk — compare it against the workflow's exact filenames (step 5).
2. `GET /system_stats` gives the hardware verdict in one request: `devices[]` (`name`, `vram_total`/`vram_free`), `ram_total`/`ram_free`, `comfyui_version`, and `argv` (which shows `--listen`/`--port` and flags like `--disable-smart-memory`).
3. `GET /queue` — empty `queue_running` and `queue_pending` means the host is idle and free to take the job.
4. One class per request; never pull the whole `/object_info` dump (it truncates — see `comfyui-remote-run`).
5. Verdict: every referenced filename present, node class present, idle, VRAM adequate ⇒ ready to queue; state that the run is still the proof.

## Decision rules
- A "missing" node from a `.py`-only grep is usually a frontend-only node — check the `.js` side before reporting it missing.
- Low VRAM is not a blocker: these workflows ship block-swap / reserved-VRAM / block-cache nodes (`UniBlockSwap`,
  `ReservedVRAMSetter`, `MiniMaxH3MemoryEfficientSageAttentionPatch`, `…blockcache…`), so expect heavy offload and
  slowness, not failure. Report the hardware tier (VRAM + RAM) with the verdict.
- File names in the workflow's JSON are the only model truth; do not assume a similarly named file matches.
- Model files present + node classes present is a **precondition**, not a pass — the run is the proof. Do not report
  a workflow as "works" from the static check alone; run it (`comfyui-remote-run`) before claiming it does.
- Ask before rebooting for a driver mismatch; never reboot a machine someone is using unannounced.

## Done when
Each named workflow has a per-item verdict, the missing node types and model filenames are listed, and the machine's
actual blocker (Windows-only bundle, driver/module mismatch, or a missing file) is named.

## Related
Running the workflow for real through the host's HTTP API (submit, poll, fetch the output), and the `task_type` /
base-model pairing rule — `comfyui-remote-run`. Reaching the host, and its Windows command-length/quoting limits —
`tailnet-host-control` and its `references/windows-remote-execution.md`. Launching a *desktop* app on a remote Linux
desktop and proving its window — `remote-gui-app-launch`.
