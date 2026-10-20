---
name: asset-registry-archiving
description: Use when a 3D asset (scene, prop set, character, effect, whole-pack scene) must be registered in the vault's asset library, when the user asks for the 3D-asset category to be tidied because assets keep accumulating, when draft and approved versions must be separated into their own records, or when someone asks where an approved asset's final file and specs live. Covers the append-only asset numbering by type, the six-value status vocabulary and who may set 过稿, the draft-card/approved-card split, and the rule that large files stay on the execution host with path + bytes + date recorded instead.
---

# Register a 3D Asset in the Vault

## When
- A scene, prop, character or effect reaches draft or approved and has to be findable later.
- "3D 资产这块的归类做整齐，以后会越来越多" — building or extending the category structure itself.
- "草稿和过稿也要整理" — splitting process records from final versions.
- Asked where an asset's final `.blend`/`.glb` is, what it measures, or why an earlier version was rejected.

Home in this vault: `04_工作使用/美术创作/3D资产/`, with `00_索引/` (registry table + naming rules), `01_草稿/`, `02_过稿/`, `03_规范/` (delivery checklist), `99_废弃/`.

## Steps
1. **Register in the table before writing cards.** `00_索引/资产总表.md` is the single authority: one row per asset, columns 编号 · 名称 · 类型 · 项目 · 状态 · 过稿位置（路径/字节/规格）· 草稿与过程 · 更新. Any other place that lists assets is a view of this table, not a second source.
2. **Assign an append-only number by type.** `S-` scene, `P` prop, `E-` whole-pack scene, `C-` character, `F-` effect/VFX; three digits, gaps allowed, **numbers never reused** even after 已废弃. Renaming is fine (record it in the 更新 column); renumbering is not.
3. **Write two cards for the same asset, one per side.** Draft side `01_草稿/YYYY-MM-DD_编号_简称.md`, approved side `02_过稿/YYYY-MM-DD_编号_简称.md`. The draft card holds the iteration table (round → what changed → outcome), the rejected items **in the user's own words**, and the rollback baselines with bytes. The approved card holds only the final: location, spec, deliverables, reproducible points, known issues. Never merge them, and never delete the draft card once approved — "why it is not that" is the judgment material.
4. **Use exactly six statuses.** `草稿` / `待审` / `过稿` / `已集成` / `阻塞` / `已废弃`. **过稿 is the user's call alone** — a grading average above 3.5 only reaches 待审 (see `render-preview-grading`). 阻塞 requires a written reason.
5. **Record paths, not files.** Large `.blend`/`.glb`/frame sequences stay on the execution host. The card and the table carry host + absolute path + bytes + date + resolution/face count/frames. When a path is not yet obtainable write **待补** with what is missing; when it dies mark it **失效**. Never leave a stale path looking live, and never copy an asset into the vault to "complete" the record.
   - **Exception — a small 2D deliverable whose only copy sits in a disposable `tmp/`.** A character sheet, design three-view or reference PNG belongs in the project's asset folder (`<项目>/01_美术资产/<类别>/`), not in `tmp/`. Copy it once, verify the copy with `md5 -q` against the source, and record that destination path in the table with byte size and pixel dimensions. The rule above targets large host-side build artifacts, not a 1–2 MB sheet that would otherwise be deleted.
   - **A 2D design sheet takes the character's `C-` number**, with 类型 written as e.g. `角色设定（2D）`, and its path points at the project's asset folder rather than `02_过稿/`. Register the sheet the user actually ratified; leave the alternate version in `tmp/` noted in 草稿与过程 instead of filing it unasked.
6. **Fill the six required card items:** location, spec, status + date, deliverable list, process-archive location, known issues / next step. A card missing one of these is not finished.
7. **Append one row to `00_规则与索引/录入记录.md`** per created or changed file group, and add the folder to its parent `README.md` when the structure is new. Then update the table row's 更新 date the same day.

## Decision rules
- One asset, one number, one row. A second row for the same asset is a status change recorded in 更新, not a new line.
- Copying a file into the vault is a **preservation** decision, not a completeness one: do it when the source is throwaway (`tmp/`), the file is small, and it is the ratified deliverable — and prove the copy with a checksum. Everything large stays where it was built.
- A draft that was rejected for a stated reason keeps that reason verbatim; paraphrasing it into "不够好" destroys the only reusable part.
- A "too sparse / too bright / looks painted-on" complaint is a diagnosis, not a tweak: record which axis was wrong (count and category, exposure, material and ray-traced reflection) so the next attempt does not move positions when it should add parts.
- Cards carry facts and the user's wording; the reviewer's opinions stay in the grading note.
- `99_废弃/` keeps three lines — what was built, who rejected it, why — and whether the engineering files were deleted or kept. Deleting the record is worse than keeping a dead direction.
- Registers age badly if the spec drifts: when a delivery convention changes (e.g. a required non-empty build script), change `03_规范/像素3D_交付检查单.md` first, then the cards that cite it.

## Done when
The registry table has one row for the asset with a real status, the approved card exists with path + bytes + spec, the draft card exists with the rejected reasons when there was an iteration, `录入记录` has its row, and the parent README links the folder — or every gap is explicitly marked 待补 with what is missing.

## Related
Grading the preview and the task-book/revision-order split — `render-preview-grading`. Filing a day's work and judgment entries, priority tiers, staging-then-confirming — `project-snapshot-collect`. Renaming a category path without leaving stale links — `path-rename-reference-sweep`.
