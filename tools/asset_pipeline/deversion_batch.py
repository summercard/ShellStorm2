#!/usr/bin/env python3
"""去版本化批次迁移：把 Godot 运行资产收成稳定路径（执行计划 §4.1 的批次工具）。

规则：`components/`、`runtime/` 下的运行资产文件名与目录名不含版本号。
- 同名资产多版本并存（后缀式版本）      → 保留最高版本，其余删除
- 带版本目录整树（如 `entry_safe_room/v007/<slug>/`） → 只保留指定版本，其余整树删除
- 稳定化 = 去掉文件名里的 `_vNNN`、去掉路径里的 `vNNN/` 段
- `.glb` 与其 `.import` 同步改名；改名后的 `.tscn` 内部 `res://` 引用同步改写
- `pinned`（人工定代例外）：同一稳定路径下若是**两份不同资产**而非代际，
  钉住其中一份到独立稳定名，两份都留（见 B3 的 corner_l_5m）

默认 `--plan` 只打印计划，不做任何改动。`--apply-renames` / `--apply-deletes` 才动手，
两者都走 `git mv` / `git rm`，历史由 git 承担。

用法：
  python3 tools/asset_pipeline/deversion_batch.py b1 --plan
  python3 tools/asset_pipeline/deversion_batch.py b1 --apply-renames
  python3 tools/asset_pipeline/deversion_batch.py b1 --apply-deletes
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
ART = PROJECT / "assets" / "art"

VERSION_SUFFIX = re.compile(r"_v(\d{3})(?=\.)")
VERSION_DIR = re.compile(r"^v(\d{3})$")
RUN_ASSET = re.compile(r"_v\d{3}\.(?:glb|tscn)(?:\.(?:import|uid))?$")
BACKUP = re.compile(r"\.bak_")

# 批次级开关：本批的「版本」是否写在**目录名后缀**上。
# B1/B2 的版本目录是纯 `vNNN/`（已由 VERSION_DIR 处理）；base_facility_3d 不一样，
# 它的批次分组目录形如 `env_base99_remaining_facilities_v021/<slug>/`，版本是
# **目录名的 `_vNNN` 后缀**，而且文件名里也可能嵌着组版本（`env_base99_floor_details_v017_visual_top3d_v001.glb`）。
# 开启后 stable_path 对**每个路径段**剥掉所有 `_vNNN`（后接 `.` / `_` / 段尾），
# 于是 `<组>_v017/…` 与 `<组>_v021/…` 归一到同一稳定路径，再由 collapse
# 的「保留最高版本」把旧代删掉 —— 跨目录同名冲突由此自然消解。
STRIP_DIR_VERSION = False

# 段内版本：允许 `_vNNN` 后接 `.`（文件扩展名前）、`_`（嵌在名字中间）或段尾（目录名后缀）。
VERSION_ANY = re.compile(r"_v(\d{3})(?=[._]|$)")

# 定代例外（module 级，由 main() 从批次定义的 `pinned` 注入）：
# 把**指定文件**固定到**指定稳定路径**，不走 stable_name 的「剥掉 _vNNN」推导。
#
# 为什么需要：collapse 的前提是「同一稳定路径下的多份 = 同一资产的代际」。但同一目录里
# 可能躺着**两份不同资产**，它们剥完版本号恰好同名 —— 这时 collapse 会按「留最高版」
# 删掉另一份，且被删的那份往往正是代码在用的那个（引用还在，内容被静默换掉）。
# 遇到这种情形必须人工定代，把其中一份钉到独立稳定名，两份都留。
PINNED: dict[str, str] = {}

BATCHES: dict[str, dict] = {
    "b1": {
        "label": "战局区块 battle（common_components + entry_safe_room）",
        "root": "assets/art/environments/tower_zones/battle",
        # 子树 → 策略
        "rules": {
            "components/common_components": {"mode": "collapse"},
            "runtime/common_components": {"mode": "collapse"},
            "components/entry_safe_room": {"mode": "keep_version", "version": "v007"},
            "runtime/entry_safe_room": {"mode": "keep_version", "version": "v007"},
        },
        "excluded": [
            "assets/art/environments/tower_zones/base/runtime/zone_base_v002.tscn"
            "（zone 场景、非 <slug> 粒度）→ 已转 B2",
            "assets/art/environments/tower_zones/rooftop/runtime/zone_rooftop_v021.tscn → 已转 B2",
        ],
    },
    # B2 横跨 7 个根（其中 tower_zones/base + rooftop 收的是 B1 残留的 2 个 zone 场景）。
    "b2": {
        "label": "dungeon_3d + tower_descent_3d + base_world_3d（+ B1 残留 zone 场景）",
        "roots": [
            {"root": "assets/art/props/dungeon_3d", "rules": {"": {"mode": "collapse"}}},
            {
                "root": "assets/art/environments/tower_descent_3d",
                "rules": {
                    "components": {"mode": "collapse"},
                    "runtime": {"mode": "collapse"},
                },
            },
            {"root": "assets/art/props/base_world_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/environments/dungeon_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/environments/base_world_3d", "rules": {"": {"mode": "collapse"}}},
            # B1 残留：这两个 zone 场景是 <slug> 粒度之上的整关包，B1 因「引用方
            # TowerDescent3D.gd 正被并行会话改动」而排除；B2 已一并改引用，故收进来。
            {"root": "assets/art/environments/tower_zones/base", "rules": {"runtime": {"mode": "collapse"}}},
            {"root": "assets/art/environments/tower_zones/rooftop", "rules": {"runtime": {"mode": "collapse"}}},
        ],
        # 跨目录取代：这两份是「同一逻辑资产」的两版，却分处不同目录，
        # 按 stable_path 分组看不出来（稳定路径不同 → 会被各自改名、双双留下）。
        # 依据 floor_tile_5m/asset_manifest_v002.json 的 replacement 字段：
        # 「v001 registry pointed to GLB but actual runtime was BoxMesh; v002 now
        #  explicitly imports the authored mesh」→ 扁平的 v001 是废弃版，删；
        #  floor_tile_5m/ 下的 v002 是正式版，改名保留。
        "superseded": {
            "assets/art/environments/tower_descent_3d/components/env_tower_floor_tile_5m_top3d_v001.glb":
                "assets/art/environments/tower_descent_3d/components/floor_tile_5m/env_tower_floor_tile_5m_top3d_v002.glb",
        },
    },
    # B3 与其它批不同：版本同时写在**文件名的尾缀**与**批次分组目录名的后缀**上。
    # 见 STRIP_DIR_VERSION / VERSION_ANY。三条形态：
    #   1) 两级扁平   components/env_base99_corner_l_5m/<slug>_visual_top3d_vNNN.glb
    #   2) 三级分组   components/env_base99_remaining_facilities_v021/<slug>/<slug>_visual_top3d_vNNN.glb
    #   3) 三代并存   components/env_base99_floor_{details,visuals}_v0{17,20,21}/… 与
    #                 env_base99_loft_floor_finish_v0{17,20}/…
    # 形态 3 归一后落到同一稳定路径，由 collapse「保留最高版本」保留 v021/v020 代、
    # 删掉 v017 代（已用 _scratch/b3_closure_check.py 验证：从美术总装递归解析的
    # 157 文件依赖闭包内，没有任何引用指向将被删除的版本）。
    "b3": {
        "label": "基地 99F base_facility_3d（两级扁平 + 三级分组 + 三代并存）",
        "root": "assets/art/environments/base_facility_3d",
        "strip_dir_version": True,
        "rules": {
            "components": {"mode": "collapse"},
            "runtime": {"mode": "collapse"},
        },
        "excluded": [
            "assets/art/environments/base_facility_3d/source/**（Blender 源，整体豁免）",
            "components/** 的 3 个 *_runtime_manifest_vNNN.json：不属门禁口径（"
            "RUN_ASSET 只认 .glb/.tscn），随所在分组目录的重命名单独处理",
            "assets/art/asset_import_manifest_v001.json：B1/B2 均未回填，"
            "按 P2 记的「P6 与重命名同批更新」统一留到收尾批",
        ],
        # 定代例外（人工决策，2026-09-17）：corner_l_5m 的 v004 与 v005 剥掉版本号后
        # 稳定路径相同，却是**两个不同资产**，不是代际 ——
        #   v004 = 手工维护的「11.9m 视觉 + 12m 双 BoxShape3D 碰撞载体」，根节点
        #          PrpCornerL5m，collision_owner="Godot wrapper"；
        #          DungeonRoom3D.gd:37 用它当 FACILITY 房间的 BASE99_CORNER_L_PREFAB，
        #          而 L2057 _configure_corner_camera_collisions() 正是遍历它那 2 个
        #          StaticBody3D（WallCollisionLong/Short）来配相机推墙。
        #   v005 = 纯视觉壳（visual_only=true，零碰撞，collision_owner="DungeonRoom3D"），
        #          zone_base.tscn 与 asset_import_manifest 的 runtime_scene 用的就是它。
        # 若按 collapse 留 v005 删 v004：DungeonRoom3D 的 preload 被改写到稳定路径后
        # 会加载 v005，2 个碰撞体凭空消失 → FACILITY 拐角丢碰撞（早期 "修改阻挡" 修掉的
        # bug 回归），且 verify_base99_corner_l_v024_import.gd / validate_base99_corner_wrapper.gd
        # 的 COLLISION_WRAPPER 断言同时失效。故把 v004 钉到独立稳定名，两份都留：
        # v005 占规范名（与 manifest 登记一致），v004 走角色名。
        "pinned": {
            "assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/"
            "env_base99_corner_l_5m_root_top3d_v004.tscn":
                "assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/"
                "env_base99_corner_l_5m_collision_top3d.tscn",
        },
    },
    # B6 是**纯改名批**：六个套件里的运行资产全部只有 `_v001` 一代，
    # 既没有「多代并存」也没有「批次分组目录」，因此 deletes 恒为 0。
    # 它同时是唯一「运行资产不在 components//runtime/ 下」的批 —— 这些套件本身就是
    # 「一个套件一个扁平目录」（如 vfx/combat_3d 是 8 个同级的 *_root_top3d_v001.tscn），
    # 见 assets/art/3D模型资产目录与命名规范.md:153 记的「非标准三件套布局」。
    # 门禁 check_asset_runtime_naming.py 扫的是整个 assets/art/**（仅 source/ 豁免），
    # 所以这批文件虽然在套件根、不在 components//runtime/ 下，一样是口径内欠账。
    "b6": {
        "label": "vfx + ui + training_range（纯改名批：全部唯一版本 _v001）",
        "roots": [
            {"root": "assets/art/vfx/combat_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/vfx/environment_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/vfx/visibility_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/ui/inventory_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/ui/pause_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/environments/training_range_3d", "rules": {"": {"mode": "collapse"}}},
        ],
        "excluded": [
            "assets/art/vfx/**/source/**（如有，Blender 源整体豁免）",
            "assets/art/vfx/environment_3d/base_facility_scene_vfx_manifest_v001.json："
            "manifest 是版本事实登记处，不属门禁口径（RUN_ASSET 只认 .glb/.tscn）",
            "assets/art/ui/inventory_3d/ui_inventory_item_model_preview_v001.png(+.import)、"
            "assets/art/environments/training_range_3d/env_training_range_preview_top3d_v001.png(+.import)："
            "预览图，不属门禁口径。`.png`/`.jpg`/`.tres`/`.wav` 一类全仓共 646 个带版本文件，"
            "是项目刻意收窄掉的独立类（动它等于改命名契约），留待单独决策",
        ],
    },
}


def stable_name(name: str) -> str:
    return VERSION_SUFFIX.sub("", name, count=1)


def stable_path(rel: str) -> str:
    if rel in PINNED:
        return PINNED[rel]
    parts = [p for p in rel.split("/") if not VERSION_DIR.match(p)]
    if STRIP_DIR_VERSION:
        parts = [VERSION_ANY.sub("", p) for p in parts]
    else:
        parts[-1] = stable_name(parts[-1])
    return "/".join(parts)


def version_of(rel: str) -> str:
    m = VERSION_SUFFIX.search(Path(rel).name)
    if m:
        return "v" + m.group(1)
    for part in rel.split("/"):
        if VERSION_DIR.match(part):
            return part
    return ""


def batch_roots(batch: dict) -> list[tuple[str, dict]]:
    """归一化批次的根列表：老写法 `root` + `rules`，新写法 `roots: [{root, rules}]`。"""
    if "roots" in batch:
        return [(entry["root"], entry["rules"]) for entry in batch["roots"]]
    return [(batch["root"], batch["rules"])]


def superseded_paths(batch: dict) -> list[str]:
    """跨目录「废弃版」及其旁文件（.import/.uid）：这些是删除项，不是改名项。"""
    out: list[str] = []
    for doomed in batch.get("superseded", {}):
        out.append(doomed)
        for suffix in (".import", ".uid"):
            if (PROJECT / (doomed + suffix)).is_file():
                out.append(doomed + suffix)
    return out


def batch_applied(batch: dict) -> list[str]:
    """判定批次已落地：`superseded` 的废弃版与其正式版都不在磁盘，但正式版的稳定路径在。

    这是一次性迁移脚本的**正常终态**，必须与「文件被误删」区分开 —— 否则在已应用
    的批次上重跑 `--plan` 会报「废弃版不存在」，读起来像丢了文件，会诱导操作者去
    「恢复」一个按设计本就该删掉的旧版。
    """
    hit: list[str] = []
    for doomed, canonical in batch.get("superseded", {}).items():
        if (PROJECT / doomed).is_file():
            continue
        if not (PROJECT / canonical).is_file() and (PROJECT / stable_path(canonical)).is_file():
            hit.append(doomed)
    return hit


def collect_leftovers(batch: dict) -> list[str]:
    """第二步（重命名之后）的删除清单：批根下**仍然带版本**的运行资产。

    与 collect() 分开是必要的：重命名之后，`<slug>_v003.glb` 的稳定名已被上一步
    的 `<slug>_v004.glb` 占据；若还用「保留最高版本」的逻辑重算，会把 `v003` 当成
    更高版本、反过来删掉刚改名成功的文件。

    第二步只认三条：
      A. 稳定名已存在 → 删带版本的那个（同资产多版本的旧版）
      B. 落在非保留版本的整树目录里（`<套件>/vNNN/...` 且 vNNN ≠ 规则保留版本）→ 整树删
      C. 命中 `superseded` 声明的废弃版（跨目录同名资产的旧版）→ 删
    """
    deletes: list[str] = []
    doomed_set = set(superseded_paths(batch))
    for root_rel, rules in batch_roots(batch):
        root = PROJECT / root_rel
        # 整树删除范围：keep_version 规则子树 <path>，保留版本 <version>
        tree_rules = [
            (sub, rule["version"])
            for sub, rule in rules.items()
            if rule["mode"] == "keep_version"
        ]
        for p in sorted(root.rglob("*")):
            if not p.is_file():
                continue
            rel = p.relative_to(PROJECT).as_posix()
            if rel in doomed_set:
                deletes.append(rel)
                continue
            if BACKUP.search(p.name):
                if "/source/" not in rel:
                    deletes.append(rel)
                continue
            if not RUN_ASSET.search(p.name):
                continue

            # B：整树目录（非保留版本）
            version_dir_hit = False
            for sub, keep in tree_rules:
                prefix = f"{root_rel}/{sub}/" if sub else f"{root_rel}/"
                if not rel.startswith(prefix):
                    continue
                head = rel[len(prefix):].split("/")[0]
                if VERSION_DIR.match(head) and head != keep:
                    version_dir_hit = True
            if version_dir_hit:
                deletes.append(rel)
                continue

            stable = stable_path(rel)
            if stable == rel:
                continue  # 已经是稳定名
            if not (PROJECT / stable).is_file():
                raise SystemExit(
                    f"{rel} 仍是带版本命名，但稳定路径 {stable} 不存在，也不在整树删除范围内——"
                    f"说明重命名还没做完或规则有漏，先跑 --apply-renames 并检查 BATCHES 规则。"
                )
            deletes.append(rel)
    return sorted(set(deletes))


def collect(batch: dict) -> tuple[list[tuple[str, str]], list[str]]:
    """返回 (rename_pairs, delete_relpaths)。"""
    renames: list[tuple[str, str]] = []
    deletes: list[str] = []

    for root_rel, rules in batch_roots(batch):
        root = PROJECT / root_rel
        for sub, rule in rules.items():
            base = root / sub if sub else root
            if not base.is_dir():
                continue
            # 收集该子树下所有带版本运行资产
            owned: dict[str, list[Path]] = {}
            for p in sorted(base.rglob("*")):
                if not p.is_file():
                    continue
                if BACKUP.search(p.name):
                    continue
                if not RUN_ASSET.search(p.name):
                    continue
                if rule["mode"] == "keep_version" and version_of(str(p.relative_to(PROJECT))) != rule["version"]:
                    deletes.append(p.relative_to(PROJECT).as_posix())
                    continue
                owned.setdefault(stable_path(str(p.relative_to(PROJECT)).replace("\\", "/")), []).append(p)

            for stable, group in sorted(owned.items()):
                if len(group) == 1:
                    old = group[0].relative_to(PROJECT).as_posix()
                    if old != stable:
                        renames.append((old, stable))
                    continue
                # 多版本并存 → 保留最高版本
                group.sort(key=lambda p: version_of(p.relative_to(PROJECT).as_posix()), reverse=True)
                if len({version_of(p.relative_to(PROJECT).as_posix()) for p in group}) != len(group):
                    raise SystemExit(f"{stable}: 同版本重复文件，人工确认：{[str(p) for p in group]}")
                keep = group[0].relative_to(PROJECT).as_posix()
                if keep != stable:
                    renames.append((keep, stable))
                for p in group[1:]:
                    deletes.append(p.relative_to(PROJECT).as_posix())

            # keep_version 模式下，被保版本以外的整树兜底（含非运行资产后缀的残件）
            if rule["mode"] == "keep_version":
                for p in sorted(base.rglob("*")):
                    if p.is_file() and p.relative_to(PROJECT).as_posix() not in deletes:
                        v = version_of(p.relative_to(PROJECT).as_posix())
                        if v and v != rule["version"]:
                            deletes.append(p.relative_to(PROJECT).as_posix())

    # 跨目录取代：废弃版（含其 .import/.uid 旁文件）删除，正式版按常规改名保留。
    # 旁文件必须一起删：只删 .glb 会把 `<slug>_v001.glb.import` 改名成稳定的
    # `<slug>.glb.import`，与正式版改名后的同类旁文件并存、留下无主残留。
    superseded: dict[str, str] = batch.get("superseded", {})
    for doomed, canonical in superseded.items():
        if not (PROJECT / doomed).is_file():
            raise SystemExit(
                f"superseded 声明要删的废弃版不存在：{doomed}\n"
                f"  若本批已应用，正式版的稳定路径应当存在：{stable_path(canonical)}"
                f"（现在{'存在' if (PROJECT / stable_path(canonical)).is_file() else '也不存在'}）"
            )
        if not (PROJECT / canonical).is_file():
            raise SystemExit(f"superseded 声明要保留的正式版不存在：{canonical}")
    doomed_all = set(superseded_paths(batch))
    renames = [(o, n) for (o, n) in renames if o not in doomed_all]
    deletes.extend(sorted(doomed_all))

    # 备份残留：只清运行资产侧的，`source/` 的备份不属于本批（源侧历史另议）
    for root_rel, _rules in batch_roots(batch):
        root = PROJECT / root_rel
        for p in sorted(root.rglob("*")):
            if not p.is_file() or not BACKUP.search(p.name):
                continue
            rel = p.relative_to(PROJECT).as_posix()
            if "/source/" in rel:
                continue
            deletes.append(rel)

    renames = sorted(set(renames))
    deletes = sorted(set(d for d in deletes if not any(d == r[0] for r in renames)))
    return renames, deletes


def check(renames, deletes) -> None:
    problems = []
    targets = set()
    # 一次性取全仓已跟踪清单：本机每个 git 子进程约 0.45s（杀软/沙箱拖慢），
    # 逐文件跑 `ls-files --error-unmatch` 会在大批（B3 266 条）上白烧两分钟，
    # 还会把整批拖过默认超时被杀。批量取一次，判据等价。
    tracked = set(
        subprocess.run(
            ["git", "-C", str(PROJECT), "ls-files"],
            capture_output=True, text=True,
        ).stdout.splitlines()
    )
    for old, new in renames:
        op, np_ = PROJECT / old, PROJECT / new
        if not op.is_file():
            problems.append(f"源不存在: {old}")
        if np_.exists():
            problems.append(f"目标已存在（会覆盖）: {new}")
        if new in targets:
            problems.append(f"重命名目标重复: {new}")
        targets.add(new)
        if old not in tracked:
            problems.append(f"未被 git 跟踪（改名会丢历史）: {old}")
    for d in deletes:
        if not (PROJECT / d).is_file():
            problems.append(f"待删文件不存在: {d}")
    if problems:
        print("PLAN_BLOCKED：计划有问题，未做任何改动", file=sys.stderr)
        for p in problems[:40]:
            print("  " + p, file=sys.stderr)
        if len(problems) > 40:
            print(f"  … 另有 {len(problems) - 40} 项", file=sys.stderr)
        raise SystemExit(2)


def git(*args: str) -> None:
    r = subprocess.run(["git", "-C", str(PROJECT), *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} 失败：{r.stderr.strip()}")


def stage_roots(batch: dict) -> None:
    """把批根下的一切改动一次性暂存（改名、删除、内容改写）。

    为什么不用逐文件的 `git mv` / `git rm`：本机每个 git 子进程约 0.45s
    （杀软/沙箱），B3 要 266 次 mv + 177 次 rm ≈ 5 分钟，且**每次都在索引上
    开一次锁**——并行会话稍有 git 操作就会撞 `index.lock`（B3 首跑即因此被
    中途 SIGTERM，留下部分改名）。改名本身是纯文件系统操作，提交时 git 按
    内容相似度照样识别为 rename，历史不丢。故：文件操作走 os 层，暂存只做一次。
    """
    for root_rel, _rules in batch_roots(batch):
        git("add", "-A", "--", root_rel)


def apply_renames(batch: dict, renames) -> None:
    path_map = {old: new for old, new in renames}
    for old, new in renames:
        src, dst = PROJECT / old, PROJECT / new
        dst.parent.mkdir(parents=True, exist_ok=True)
        src.rename(dst)
    # 改名后的 .tscn 内部引用同步改写
    touched = 0
    for old, new in renames:
        if not new.endswith(".tscn"):
            continue
        f = PROJECT / new
        text = f.read_text(encoding="utf8")
        updated = text
        for o, n in path_map.items():
            updated = updated.replace(f"res://{o}", f"res://{n}")
        if updated != text:
            f.write_text(updated, encoding="utf8")
            touched += 1
    stage_roots(batch)
    print(f"RENAMED {len(renames)} 个文件；改写内部引用的 .tscn {touched} 个")


def fix_scene_refs(batch: dict) -> int:
    """把批根下 `.tscn` 内部的 `res://..._vNNN.glb|tscn` 引用改写到稳定路径。

    只在**稳定路径已存在**时改写，因此幂等、且不会把引用改到不存在的文件上。
    独立成一步是必要的：重命名的内容改写若只留在工作区（未暂存），
    任何 `git checkout` 恢复都会把它抹掉——本批就踩过。
    """
    touched = 0
    for root_rel, _rules in batch_roots(batch):
        root = PROJECT / root_rel
        ref = re.compile(r"res://(assets/[A-Za-z0-9_/.\-]*?_v\d{3}\.(?:glb|tscn))")
        for tscn in sorted(root.rglob("*.tscn")):
            text = tscn.read_text(encoding="utf8")
            updated = text
            for old_rel in set(ref.findall(text)):
                stable = stable_path(old_rel)
                if stable == old_rel or not (PROJECT / stable).is_file():
                    continue
                updated = updated.replace(f"res://{old_rel}", f"res://{stable}")
            if updated != text:
                tscn.write_text(updated, encoding="utf8")
                touched += 1
    return touched


CODE_REF = re.compile(r"res://(assets/[A-Za-z0-9_/.\-]*?_v\d{3}\.(?:glb|tscn))")


def fix_code_refs(batch: dict) -> list[tuple[str, int, list[str]]]:
    """把全仓 `res://..._vNNN.glb|tscn` 引用改写到稳定路径。

    判据（三条同时成立才改，故自限定作用域、幂等）：
      1. 稳定路径与带版本路径不同；
      2. 带版本路径**已不存在**（说明本批或更早已把它改走）；
      3. 稳定路径**存在**。
    未处理的批次（如 weapons/base_facility 的 `_v001`）带版本文件仍在 → 跳过。
    只扫 `.gd` / `.tscn`：`.py` 批次配置与历史导入脚本不在改写范围（门禁亦只管
    `src/**/*.gd` 与 `*.tscn`）。
    """
    files: list[Path] = []
    for folder in ("src", "scenes", "tests", "tools"):
        base = PROJECT / folder
        if base.is_dir():
            files += [f for f in base.rglob("*") if f.suffix in (".gd", ".tscn")]
    for suffix in ("*.gd", "*.tscn"):
        files += list((PROJECT / "assets" / "art").rglob(suffix))

    changed: list[tuple[str, int, list[str]]] = []
    for f in sorted(set(files)):
        text = f.read_text(encoding="utf8")
        repl: dict[str, str] = {}
        for old in set(CODE_REF.findall(text)):
            stable = stable_path(old)
            if stable == old:
                continue
            if (PROJECT / old).exists():
                continue  # 仍带版本 → 属后续批次，不越界
            if not (PROJECT / stable).is_file():
                continue  # 稳定目标不存在（如被取代的旧版）→ 不能改
            repl[old] = stable
        if not repl:
            continue
        updated = text
        for o, n in repl.items():
            updated = updated.replace(f"res://{o}", f"res://{n}")
        if updated != text:
            f.write_text(updated, encoding="utf8")
            changed.append((f.relative_to(PROJECT).as_posix(), len(repl), sorted(repl)))
    return changed


def apply_deletes(batch: dict, deletes) -> None:
    for d in deletes:
        p = PROJECT / d
        if p.is_file():
            p.unlink()
    # 清掉留空的版本目录（纯 `vNNN/` 与 B3 那种 `_vNNN` 后缀的批次分组目录）
    for p in sorted((ART).rglob("*"), reverse=True):
        if not p.is_dir():
            continue
        is_version_dir = VERSION_DIR.match(p.name) or (
            STRIP_DIR_VERSION and VERSION_ANY.search(p.name)
        )
        if not is_version_dir:
            continue
        try:
            p.rmdir()
            print(f"RMDIR {p.relative_to(PROJECT).as_posix()}")
        except OSError:
            pass
    stage_roots(batch)
    print(f"DELETED {len(deletes)} 个文件")


def main() -> int:
    ap = argparse.ArgumentParser(description="去版本化批次迁移")
    ap.add_argument("batch", choices=sorted(BATCHES))
    ap.add_argument("--plan", action="store_true", default=True)
    ap.add_argument("--apply-renames", action="store_true")
    ap.add_argument("--apply-deletes", action="store_true")
    ap.add_argument("--fix-scene-refs", action="store_true")
    ap.add_argument("--fix-code-refs", action="store_true")
    args = ap.parse_args()

    batch = BATCHES[args.batch]
    excluded = list(batch.get("excluded", []))

    # 批次级开关必须在使用 stable_path 之前生效（模块级全局）
    global STRIP_DIR_VERSION, PINNED
    STRIP_DIR_VERSION = bool(batch.get("strip_dir_version", False))
    PINNED = dict(batch.get("pinned", {}))

    if args.fix_code_refs:
        print(f"=== {args.batch} 全仓代码/场景引用改写（.gd/.tscn） ===")
        changed = fix_code_refs(batch)
        for rel, n, refs in changed:
            print(f"  {rel}  ({n})")
            for r in refs:
                print(f"      -> res://{stable_path(r)}")
        print(f"共改写 {len(changed)} 个文件")
        return 0

    if args.fix_scene_refs:
        print(f"=== {args.batch} 场景内部引用改写 ===")
        print(f"改写 {fix_scene_refs(batch)} 个 .tscn")
        return 0

    if args.apply_deletes:
        deletes = collect_leftovers(batch)
        missing = [d for d in deletes if not (PROJECT / d).is_file()]
        if missing:
            raise SystemExit(f"待删文件不存在：{missing[:5]}")
        print(f"=== {args.batch} 第二步：删除残留 {len(deletes)} 个 ===")
        for d in deletes:
            print(f"  {d}")
        apply_deletes(batch, deletes)
        return 0

    applied = batch_applied(batch)
    if applied and len(applied) == len(batch.get("superseded", {})):
        print(f"=== {args.batch} {batch['label']} ===")
        print(f"本批已应用：superseded 声明的废弃版已删除、正式版已去版本化（{len(applied)} 项）。")
        print(f"  例：{applied[0]}")
        print("  复核：python _scratch/verify_ledger_b2_deversion.py"
              " && python scripts/check_asset_runtime_naming.py")
        print("（无需重复执行；这条不是错误，是正常终态）")
        return 0

    renames, deletes = collect(batch)
    check(renames, deletes)

    print(f"=== {args.batch} {batch['label']} ===")
    print(f"重命名 {len(renames)} 个：")
    for old, new in renames:
        print(f"  {old}\n    -> {new}")
    print(f"\n第一步之后还需删除 {len(deletes)} 个（用 --apply-deletes 执行）：")
    for d in deletes:
        print(f"  {d}")
    if excluded:
        print("\n本批排除（转其它批）：")
        for e in excluded:
            print(f"  {e}")
    if args.apply_renames:
        apply_renames(batch, renames)
    if not args.apply_renames:
        print("\n（--plan 模式，未做任何改动）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
