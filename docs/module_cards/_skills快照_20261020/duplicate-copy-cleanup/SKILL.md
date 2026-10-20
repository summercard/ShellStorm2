---
name: duplicate-copy-cleanup
description: Use when several copies of the same project or checkout exist and the user asks to consolidate to one folder, delete the extras, or asks why copies live in a tool/scratch directory. Verify the keeper copy is self-contained and works before removing the others, and delete recoverably.
---

# Consolidate Duplicate Project Copies

## When
The user asks why several copies of one project exist, which one to keep, or to delete the extras and leave a single canonical folder.

## Steps
1. List every copy and compare them: `git -C <copy> rev-parse --abbrev-ref HEAD`, `git -C <copy> rev-parse --short HEAD`, `du -sh <copy>`, `find <copy> -type f ! -path '*/.git/*' | wc -l`.
2. Pick the keeper — the user's own canonical project folder. Timestamped copies made by an IDE/agent tool (e.g. a `~/<Tool>/<timestamp>/` directory) and temporary mirrors are working copies, not the canonical home. When the user names a folder ("my formal folder"), that one wins; ask if it is still unclear.
3. Prove the keeper stands alone before deleting anything:
   - Self-contained: `test -f <keeper>/.git/objects/info/alternates` must find **nothing** — an `alternates` file means it borrows objects from another copy.
   - Shallow is fine: `test -f <keeper>/.git/shallow` only warns that history is truncated; editing and running are unaffected (full history or `push` needs `git fetch --unshallow`).
   - Same content as the copies to be deleted: equal branch name and tip commit. If they differ, do **not** pick silently — report the difference.
   - Works: open/import it once (e.g. an engine's `--headless --import` that exits 0) so "works" is verified, not assumed.
4. Delete recoverably with `trash <path>` (macOS `/usr/bin/trash`), never `rm -rf`.
5. Inside a tool-owned directory, remove only the project subdirectory; leave the tool's parent directory and its unrelated files in place.
6. Re-check after: the keeper's branch/tip/worktree are unchanged, and the extra paths are gone.

## Decision rules
- Never delete a copy until the keeper is verified both self-contained and functional.
- Equal file counts do not prove copies are interchangeable — one may be the only self-contained one; check `alternates` and `.git/shallow` for each.
- `trash` does not free disk space until the trash is emptied. Report the reclaimed total and offer to empty it (ask before emptying, since that is irreversible).
  - Emptying via Finder AppleScript (`osascript -e 'tell application "Finder" to empty trash'`) can hang with no output; guard it with a bounded wait, or remove the contents directly.
  - Then confirm the trash is really empty and that `df` free space rose. A suppressed-error `ls` returning nothing cannot be told apart from a permission error, and APFS can lag, so a flat `df` right after is not by itself proof of failure.
- Remove the local mirror/bare clone that seeded the copies too — it must not stay the keeper's `origin` (see `git-clone-triage`).

## Done when
One canonical copy remains and it is verified working; the extras are in the Trash; and the user has been told whether the space is actually reclaimed.
