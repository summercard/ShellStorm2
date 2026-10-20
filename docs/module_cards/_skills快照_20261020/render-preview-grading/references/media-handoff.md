# Handing a Remote-Rendered Preview to the User in Chat

A render lives on the render host. Getting it into the conversation has two independent failure points: the copy, and the message.

## 1. Copy it locally, then verify the copy

Transfer truncation is silent — `scp` exits 0 on a partial file. Always finish with two checks on the local file:

```bash
scp <host>:<remote path> ~/.openclaw/workspace/tmp/prev.png
ls -la ~/.openclaw/workspace/tmp/prev.png          # bytes
sips -g pixelWidth -g pixelHeight <file>            # real decode + dimensions
```

A file that stalls at 98,304 B or 163,840 B (or any round boundary) is truncated despite a clean exit: delete it (`rm -f`), re-run the copy, re-check. `sips` (macOS) reading the dimensions is the proof the bytes decode as an image.

If `scp` keeps truncating, `ssh <host> "cat <remote path>" > <local>` is the alternative — but `ssh` may prefix the stream with login/`stat` noise, so a PNG's magic number can sit at offset 47. Check with `xxd -l 64`; if the header is offset, either use `scp` again or strip the prefix before trusting the file.

## 2. Send it in a normal turn

- **Completion-event replies cannot carry media.** A subagent-completion turn rejects both `attachments` and `media` with `Completion source replies cannot use the "media" argument.` Send the image in an ordinary conversational turn instead, once the finished report is in hand.
- **Name the target explicitly.** A tool-driven send outside the ordinary reply path needs `target` (Feishu: `user:<open_id>`), and `channel: feishu` when not replying in the current conversation.
- **One media per message.** Feishu rejects a second attachment in the same message; send one image per call, each with its own one-line caption. Two images means two sends.
- **A video over Feishu's 30 MB cap needs a second encode, not a trim.** The send fails as `file exceeds limit of 31457280 bytes (got 34899598)`. Produce a delivery copy at the same frame size (`-c:v libx264 -crf 24 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k`), keep the full-quality master in the user's library, and run the full-decode check on the copy too — verified, a first compression attempt looked fine but decoded only 25 s. State which file is the archive original in the caption.
- Caption each image with what it is and its score/round, not just the file name; the user is judging the picture, not opening paths.

## 3. Clean up

Keep the working file and all renders on the render host. The local copy exists only to be sent: put it under `tmp/` and delete it after delivery. Do not build a local archive of remote renders on a machine whose disk is short.

Documents are not media: a Markdown/HTML/docx package, its Feishu online doc and the DM delivery rule live in `doc-package-delivery`.
