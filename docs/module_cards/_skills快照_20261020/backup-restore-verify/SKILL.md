---
name: backup-restore-verify
description: Use when restoring, overwriting, or recovering files, memory, or config from a user-provided backup folder or archive. Verify the source holds real file content before copying; macOS AppleDouble "stub-only" copies look populated but contain no data.
---

# Verify a Backup Source Before Restoring

## When
The user points at a backup folder or archive and asks you to restore, overwrite, or recover existing data (workspace files, memory, config).

## Rule
Never overwrite live data from a backup whose real content you have not verified. Inspect the source first; a directory can show thousands of files and still hold zero content.

## Steps
1. Count real files, excluding macOS metadata sidecars:
   `find <src> -type f ! -name "._*" ! -name ".DS_Store" | wc -l`
2. Read the result:
   - **0 real files** -> the backup is metadata-only; the content was lost in transit. Do **not** restore. Report the finding and ask for the original.
   - **>0** -> proceed, copying only real files; `._*` and `.DS_Store` are noise.
3. Confirm the stub pattern rather than trusting the count alone: `._*` files are ~163 bytes and `file <name>` reports "AppleDouble encoded Macintosh file".
4. Archive (`.zip`/`.7z`): extract to a temp dir, then run the same real-file count and stub check there. Listing entries is not proof of content — a valid archive can still hold stubs only. macOS has no `7z`/`7zz`; `python3 -m pip install --user py7zr` lists/extracts `.7z`.
5. Non-ASCII names: a ZIP created on macOS shows mojibake elsewhere (e.g. `╣ñ│╠╕∙─┐┬╝`) because names are stored as CP437-decoded bytes. Re-decode each name before judging structure — in Python `zipfile`, `n.encode('cp437').decode('gbk')` (GBK/CP936); Info-ZIP `unzip -O` is absent on macOS.
6. Before the first overwrite, snapshot what is live now (e.g. `cp -Rp` to `.restore-backup/before-<label>-<date>/`) so a bad restore is reversible.
7. After copying, re-count real files at the destination and spot-read one file, so "restored" means content, not an empty shell.

## Pitfall
A tree copied from macOS through a Windows, network, or cloud path can keep every directory and every `._*` sidecar while dropping every real file. `ls` and `du` still look full (each 163-byte stub occupies a 4K block), so always run the real-file count before acting.

## Reporting
If the source is empty, say so plainly, name the exact path checked, and offer alternatives: original backup location, or having the user dictate what to keep. Do not silently copy stubs or claim a restore.
