---
name: ffmpeg-shot-assembly
description: Use when asked to stitch generated shots into longer videos ("每 N 个镜头拼成一条"), cut several edit drafts with different rhythm or ordering from one shot library, or join clips with hard cuts / crossfades using ffmpeg. Covers per-shot trimming, concat vs xfade, silent-draft handling, re-encoding a master that `-c copy` truncated, and verifying a join by decoding without ffprobe.
---

# Assemble generated shots into deliverable videos

## When
- A shot library exists on disk (`v01s1.mp4` … each ~3 s) and the ask is "拼成 10 条 12 秒" / "剪几版预告看看".
- Re-cutting the same library after the user changes rhythm, order, or length.
- Generating the shots themselves is `comfyui-remote-run`; this skill starts when the mp4s are downloaded.

## Steps
1. **Inventory before editing, and never pad a missing shot.** Diff the files on disk against the expected tag list. A shot that has not rendered makes its whole video short — skip that video and name the missing tag (`SKIP v10 (missing shot)`) instead of shipping a 9 s cut labelled 12 s.
   - **Take the set by its exact filename pattern, never by listing the directory.** A render folder also holds test renders and older versions, and they sort right next to the real shots: verified, `s02a_test.mp4` (0.74 s) was picked as `s02a` and silently shortened the cut until the file was moved aside. Match `sNN[a-c]_*_00001_.mp4` (or the project's stated pattern) and say how many files matched.
2. **Probe with what is installed.** On this Mac `ffmpeg` is at `~/.local/bin/ffmpeg` but **`ffprobe` is not installed**; read duration from `ffmpeg -hide_banner -i <file>` stderr (`Duration: 00:00:12.04`) and size from the `Stream #0:0` line. No install needed.
   - That `Duration:` line is the **container header**, i.e. what the writer intended, not what decodes. Use it as a first look only; step 7 is the real check.
3. **Trim each shot into its own segment before joining**: `-t <sec> -an` plus `-c:v libx264 -crf 20 -pix_fmt yuv420p -r 24`. Per-shot durations then vary freely and every segment shares identical codec params, so the join cannot drift.
4. **The join depends on the transition:**
   - Hard cuts → concat demuxer: write `file '<abs path>'` lines and `-f concat -safe 0 -i list.txt`. `-c copy` is safe only on segments you just produced with identical params **and** whose every file decodes; on independently downloaded shots it truncates silently (verified: a 33 MB master reported `Duration 3:20` yet decoded 18.3 s, and single clips printing `10.03 s` stopped at 105–212 frames). **Even matching segments do not make concat-copy trustworthy**: verified, 9 scene segments each decoded with empty stderr, their `-c copy` master was unplayable (`moov atom not found`) while every segment still played and the header looked plausible — the file cannot even be opened for a decode check, so read the master as failed, not as a short file. Rebuild it by re-encoding — `-c:v libx264 -crf 21 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k -ar 32000 -ac 2 -movflags +faststart` — and keep `-c copy` only for throwaway previews.
   - Crossfades → one `xfade` per junction, chaining `[vN]`, with `offset` accumulated as `offset += prevDur - fade`. A hand-tuned offset silently overlaps or freezes frames, so compute it.
5. **Make every draft a table row, not new code.** One builder `build(name, fade, [(tag, seconds), …])` produces all of them; a new draft is a new table. Verified: 5 drafts (20.8 / 21.9 / 16.6 / 22.5 / 15.6 s) from 39 shots in a single run.
6. **Decide audio explicitly.** Source shots carry ambient audio that will not match across cuts, so cut with `-an` and deliver silent drafts until music is chosen — say they are silent rather than letting mismatched ambience play.
7. **Verify by decoding, then hand over.** Metadata first (duration ±0.1 s of the intended sum, non-zero size, 24 fps / yuv420p), then a full decode pass per file — `ffmpeg -v error -i <file> -f null -` with **empty stderr** — plus a frame count from `ffmpeg -stats -i <file> -map 0:v:0 -c copy -f null - 2>&1 | tail -1`, compared with `round(seconds × 24)` (±2). Run it on every source shot as well as the master: a truncated download fails only here (verified: `h264_mp4toannexb filter failed` and a 5.45 s shot from a 646 KB file whose real size was 938 KB). Only then give one path per draft on its own `MEDIA:` line with a one-line description of its editing logic.
   - **Re-check the delivered copy, not just your working file.** Any finalize/watch script that rewrites the output directory can put the broken master back: verified, a repair was overwritten by a stale `finalize.sh` run 20 minutes later. Compare the delivered file's decode result and byte size with what you verified.
   - **A review grid lets the user judge the whole set in one look**: pull one frame per clip (`-ss 1.5 -frames:v 1`) and tile them with `xstack`. The 3×3 layout is `layout=0_0|w0_0|w0+w1_0|0_h0|w0_h0|w0+w1_h0|0_h0+h3|w0_h0+h3|w0+w1_h0+h3`; scale every input first (`scale=480:-1`) so rows align. Verified: 9 clips → one 214 KB jpg. Skip `drawtext` numbering on this Mac — it prints `Fontconfig error: Cannot load default config file`; rely on grid order and say which order it is.

## Decision rules
- Runtime of a crossfaded draft is `sum(shots) − fade × (n−1)`; report the length actually produced, not the intended one.
- Keep the shot library and the drafts in separate directories; re-cutting must never overwrite source shots.
- A rejected draft is a table change, never a re-render — do not regenerate video to fix pacing.
- Do not upscale or change fps while assembling; a 864×480 / 24 fps source stays that, and mixed fps is what makes a join stutter.
- **Fix the source, never the join.** A shot that is short, unreadable or a stray test render is a bad input: move it aside, re-download or re-render it, verify it decodes to its full frame count, then rebuild. Re-encoding cannot restore frames that were never written.

## Done when
Every draft exists, passed a full-decode pass with 0 errors and the expected frame count at the intended frame size, and was delivered with its path and editing logic stated.

## Related
Recording a live app or game being used, rather than assembling generated shots — `app-interaction-recording`.
Producing the shots (API graph, batch journal, spec pinning) — `comfyui-remote-run`. Pulling stills or reference frames out of a finished clip — `youtube-video-fetch`.
