---
name: source-grounded-feature-doc
description: Use when asked to write a feature, module or system spec from the code itself — "帮我做一份功能说明文档", "把某个模块的制作框架整理成一份文档", "这个面板/这套数值是怎么定义的", or a whole-project module map across many modules ("每个模块的制作链路 / 工具 / 实用逻辑 / 评判维度"), or to answer what a running feature actually does — rather than from the user's notes or an older design doc. Covers snapshotting the live source, finding the single table the runtime really reads, citing every number with `file:line`, keeping a separate 已知缺口 section for design intent the code never implemented and a 无法证实 section for facts a partial snapshot cannot prove, and the verify pass that re-greps each stated constant.
---

# Document a Feature From Its Source, Not From Memory

## When
- "把 X 的功能说明 / 制作框架 / 数值表整理成一份文档" where X is code that exists in a project (a combat system,
  a weapon table, a debug panel, a save format).
- The user asks a behaviour question and the answer will be long enough to keep: "这个面板到底有哪些功能".
- An earlier doc or comment contradicts what the code does and the user wants the current truth.
- The ask is a **map of the whole project** rather than one feature — "每个模块的制作链路 / 工具 / 实用逻辑 /
  评判维度", "每个链路里的 skill / 工具使用标准 / 依据文档也要加上", "把整个工程整理成一份模块说明".
  Read `module-map-survey.md` instead of steps 2–3: it replaces read-everything with measure → rank → read
  only the risky modules, and it requires labelling each section
  实测 or 推断. If that map then has to become **one card per module** ("独立整理成卡片，可互相链接、可迭代、
  可复刻"), §8 of the same reference holds the card set: index, template, stable `MOD-` ids, relative links
  and the receiver-side copy check; §8.1 holds the per-step table that makes each 链路 row reproducible —
  tool/Skill, a numeric 使用标准, and a 依据文档 name taken from a real listing; §8.2 holds the resource map —
  where the installed skills actually are, a 缺 row for a missing one, and which of the three rulers audits
  the module.
- Not for user-written notes → `doc-package-delivery`; not for project state/history → `project-snapshot-collect`;
  not for reviewing one edit a user made → `remote-change-review`.

## Steps
1. **Snapshot the live copy, read-only, into scratch.** Decide the source first (running process, newest commits) —
   see `project-snapshot-collect`. Copy the tree to `/tmp/<proj>src` and grep there so the search is fast and
   nothing in the working copy can be touched. Name machine + path + commit in the finished doc.
2. **Find the table the runtime actually reads, before writing a single number.** Grep the feature's identifier
   (`GUN_PROFILES`, `BULLET_VISUAL_REGISTRY`, `DEFAULT_*`, a registry `_register_*`) and locate the one dict/array
   that the spawn or compute path indexes. Verified: gun stats lived in one `GUN_PROFILES` dict, drop grades in a
   separate grade module, drop weights in a third — three owners, three different files. Every fact family gets
   **one** owner; if two places hold the same constant, say which one wins and report the other as drift.
3. **Read logic whole; extract large data tables structurally.** Take the consuming functions around the table
   (fire path, reload path, stat-computation exit) in full so the doc explains behaviour, not just literals. For a
   table of hundreds of rows, do not page through it by eye: parse it with a short script that prints one line per
   entry (`name|type|rarity|params`) — verified: a 753-line preset file and a 95-line catalog, parsed with two
   `python3` heredocs, produced the complete 48-row table — then open a few rows by hand to confirm the parser did
   not swallow a nested dict. Note the ranges you read; they become your citations.
4. **Write 真源表 first.** A small table mapping each section of the doc to `path:line`. Everything after it is
   downstream of that table, and a reader can re-verify any line without trusting the prose.
5. **Count the rows against the claimed total.** When a design doc, comment or store page states a total ("78 张"),
   count the implementing entries and report implemented / claimed per group. 22 / 14 / 5 / 7 / **0** across four
   suits is a finding; "78 身份" copied from the plan is a rumour. The delta, with the names of the missing groups,
   goes in 已知缺口 — that single number was the most useful line in the delivered doc.
6. **Cite every number inline as `file:line`.** Not "伤害 25" but "伤害 25（`WeaponModel3D.gd:84`）". A doc the user
   will use to tune values must be traceable back to the literal, otherwise it is a rumour with formatting.
7. **Keep an explicit 已知缺口 section, and a separate 无法证实 one.** Design intent that the code never implemented,
   dead/legacy paths and values only set at runtime go in 已知缺口 — never into the body as if it were current.
   This is the user's standing rule: 只写工程里真实存在的规则，设计说要做但代码没做的必须放进缺口节。
   Facts the snapshot physically cannot settle go in their own short section naming the missing file and the one
   file that would settle each — never guessed, never silently dropped.
8. **Verify pass before delivering.** Re-grep each constant you wrote and diff it against the doc; check the
   stated file:line still points at that literal; check the byte count with `wc -c`. Report the checks you ran.
   Then deliver where the user asked: a copy requested on the Desktop is `cp`, not a move — the vault path stays
   canonical, and say plainly that the two can drift if only one side is edited later.

## Traps (all hit in practice)
- **zsh glob in `--include`**: `grep -rn X . --include=*.gd` dies with `(eval):1: no matches found: --include=*.gd`
  and exit 1. Always quote: `--include="*.gd"`. An unquoted pattern looks like "no matches" and hides real hits.
- **Comment drift is not evidence.** A file header said the board was `6×6=36` while the constant and the runtime
  both used `5×5=25`. Trust the literal the code reads, and list the stale comment as a gap — do not repeat it,
  do not silently "fix" it in the doc.
- **A feature with no name still exists.** A debug panel was not findable by its panel name; it was found by key
  handling — grep `KEY_P`, `_unhandled_input`, `physical_keycode`, `z_index`. Panels live where the input arrives.
- **A snapshot can be partial — say what it cannot prove.** `project.godot` is not always where you remember it
  (find the live project directory first; a stale copy answers with "No such file" while the real one is
  elsewhere), and a tree the user hands over may hold only `src/ docs/ data/`. Missing files mean missing
  answers: no `.tscn` → cannot prove which scene hosts a node; no `project.godot` → cannot check a key binding
  against the input map. Verified: a panel's host scene and its `P`-key conflict check were both unprovable from
  the snapshot provided. Put them in 无法证实 and ask for that one file — do not omit the fact, and do not write
  the likely answer as if the code had shown it.
- **A record split into base + patch needs both sides.** Upright numbers lived in a preset file while reversed
  numbers lived in a catalog holding only a `reversed_effect_patch` dict merged over them; either file read alone
  gives half-wrong values. Merge explicitly and state which side wins for a shared field.
- **Runtime-only values.** Debug values that reset on scene reload (camera offsets, light tweaks, "no save, no cfg")
  must be written as session-scoped, or the reader will assume they persist.
- **A map wider than what you read is a map you must label.** Across many modules you will cover some at
  entry-file level only, from filenames and design-doc titles. Mark those 推断 in the document, name which
  modules were read in full, and repeat that split when delivering — prose that reads as source-verified when
  it was inferred invites the reader to tune values against nothing.
- **Debug and shipped paths diverge.** Record which branch of behaviour is production and which is a debug hook;
  a doc that mixes them makes the tuning team chase a value that is never read.

## Done when
The doc names its exact source (machine, path, commit), opens with a 真源表 of `path:line`, every number carries an
inline citation that re-greps correctly, the claimed total is checked against the counted rows, implemented
behaviour / unimplemented intent / snapshot-unprovable facts sit in three separate sections, and the report lists
the constants you re-checked plus anything left unread and the one file that would close it.
