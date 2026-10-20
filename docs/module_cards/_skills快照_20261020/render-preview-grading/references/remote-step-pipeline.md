# Running a Revision as One Scripted Step on the Render Host

The brief says *what* changes; this file is *how it lands on the host*. One round = one pushed file = one ssh command = one verifiable artifact (a changed scene file plus a fresh preview).

## Who executes the round: host agent or your script

Both paths end in the same three commands (push → run → read) and the same proof (a changed scene file plus a fresh preview). Pick by what the round actually is.

**Host CLI agent — default for a scene-editing round.** Hand it the written order as a file and let it write and run the patches:

```bash
ssh <host> 'cat > <ROOT>/修改单_Rn.md' < local_order.md
ssh <host> 'cd <ROOT> && ~/.pi/agent/bin/pi -p "读 修改单_Rn.md 并严格按它执行"'
```

Verified over six consecutive rounds on one hall scene (a jukebox rebuild deleting 18 stale meshes and rebuilding 66 blocks, a sofa, a bar plus stools, three props, a sofa rescale, a lighting pass): each returned a new `_rn.png` (207–239 KB) and an updated scene file, and the reviewer never touched the host beyond pulling the preview and writing the next order. What makes that work is the brief, not the agent — a complete delta list with target values, an explicit do-not-touch list, and "one preview, no final render" leaves nothing to decide.

**Your own step script — fallback and mechanical edits.** Use it when the host has no configured CLI agent, when the round is a numeric/material/parameter change you can state exactly, or when an agent round died at its own model layer.

**The failure that produced the old "no child agent" rule.** Three chat-side subagent runs died with `LLM request failed: DNS lookup for the provider endpoint failed | ENOTFOUND`, each ending a round with no artifact; one that did run spent ~50 min across six self-written patches moving only exposure while the structure stayed unbuilt. Those are two separable faults: an unverifiable model link (nothing can fix that inside the loop) and a brief without numbers. They do not condemn delegation to the host's own agent, which needs no chat-side model call.

Either way: **a round with no artifact is not a round.** Re-dispatch it (suffixed task name), never deduct it from the round budget, and never report it as a failure of the scene work.

## The three commands

```bash
# 1. push (scp can hang on this link; cat-redirect does not)
ssh <host> 'cat > <ROOT>/scripts/sN_name.py' < local_step.py

# 2. run
ssh <host> 'cd <ROOT> && bash <ROOT>/../dispatch/q8run.sh sN_name scripts/sN_name.py'

# 3. read
ssh <host> 'cat <ROOT>/state/sN_name.json; grep -A12 Traceback <ROOT>/logs/sN_name.log'
```

Run step 2 with a long `yieldMs` (60–180 s). It blocks until Blender exits, so the exec completion *is* the done signal — no polling loop, no `done` file watcher.

## The runner

Kept outside the project so a step script can never overwrite it.

```bash
#!/usr/bin/env bash
set -u
ROOT=<project dir>; STEP="$1"; SCRIPT="$2"
mkdir -p "$ROOT"/{logs,state,backup,scripts}
LOG="$ROOT/logs/$STEP.log"; STATE="$ROOT/state/$STEP.json"; DONE="$ROOT/state/$STEP.done"
rm -f "$DONE" "$STATE"                       # a stale marker is a false success
{ echo "=== STEP $STEP"; echo "=== START $(date '+%F %T')"; } > "$LOG"

# back up only the first run of a step: an in-place rerun must not overwrite the clean baseline
if [ -f "$ROOT/scene.blend" ] && [ ! -f "$ROOT/backup/pre_$STEP.blend" ]; then
  cp -f "$ROOT/scene.blend" "$ROOT/backup/pre_$STEP.blend"
fi
cd "$ROOT" || exit 3

taskset -c 12-15 nice -n 10 blender -b --python-exit-code 1 scene.blend \
  --python "$SCRIPT" >> "$LOG" 2>&1
RC=$?

SZ=$(stat -c %s "$ROOT/scene.blend"); MT=$(stat -c %y "$ROOT/scene.blend" | cut -d. -f1)
printf '{"step":"%s","rc":%s,"blend_bytes":%s,"blend_mtime":"%s"}\n' \
  "$STEP" "$RC" "$SZ" "$MT" > "$STATE"
touch "$DONE"
echo "STEP_RESULT step=$STEP rc=$RC blend=$SZ"
exit $RC
```

`taskset`/`nice` keep the step off the host owner's own interactive render; drop them on macOS (no `taskset`).

Rollback is one line: `cp backup/pre_sN.blend scene.blend`.

## Blender gotchas that each cost a round

- **`blender -b` exits 0 even when the Python script raises.** Verified: the first step printed a `Traceback`, `blend` byte size and mtime unchanged, and the runner still reported success. Always pass `--python-exit-code 1`, and treat "rc=0 but the blend mtime did not change" as a failed step regardless.
- **Find the Principled node by type, never by name.** `material.node_tree.nodes.get("Principled BSDF")` returned `None` on this file and the run died on `AttributeError: 'NoneType' object has no attribute 'inputs'`. Use `next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)` and create the node + output link when it is missing.
- **Make every step idempotent by rebuilding, not by appending.** Delete what the step owns before creating it: by name prefix (`[o for o in bpy.data.objects if o.name.startswith("q8d_")]`) in the same script, so a rerun cannot stack duplicates.
- **`save_mainfile()` before `render()`.** A render that runs before the save leaves the step's geometry only in the image, not in the file the next step loads.
- **Probe the scene in a read-only step first.** One script printing camera loc/rot/lens/DOF, render engine/resolution/samples, scene bounds, and per-material `{count, bbox, sample names}` turns guesses about "where is the sofa" into coordinates, and confirms the whole push-run-read chain before anything is modified.

## Replacing a prop you cannot name

Read the prop's form from a crop of the reference at native pixels **before** writing the build step. At whole-frame or preview scale a prop collapses into a generic shape and the step gets built in the wrong direction: a curtain set went in as two vertical side drapes (630 blocks, discarded) and had to be rebuilt once a crop showed torn cloth hung from the arch spring, torn off near mid-window height. One crop costs seconds; the wrong form costs a step.

When a prop was built as several generically-named objects (`q8_1908`, `q8_1919`), do not hunt names and do not leave them behind: delete every mesh whose world bbox falls inside the prop's box, then build the replacement. Verify by object count before/after, and keep the delete list in the log.

## Transfer

- `scp` of a 750 KB preview hung twice on this link with no error and no progress; `ssh <host> 'cat <path>' > local.png` returned the full file immediately. Use the cat form in both directions for single small files.
- Verify bytes **and** dimensions on the copy you actually hold (`ls -l`, `sips -g pixelWidth -g pixelHeight`) before sending it; a truncated PNG still opens as a file.
- A 600×338 / 16 spp test render answers "did the structure change" in ~60 s; keep the 1200×675 / 48 spp form for the preview the user sees.

## Done when

`state/sN.json` shows `rc=0`, the blend's byte size **and** mtime are newer than the backup, the log has no `Traceback`, and a fresh preview was pulled and looked at. A step that did not change the blend did not run, whatever the exit code says.

On the host-agent path the same rule applies without the state file: the scene file's bytes and mtime must have moved, and a new preview must exist with a decode-checked size. An agent transcript that *says* it finished is not the check.
