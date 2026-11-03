# -*- coding: utf-8 -*-
"""命名收尾：把制作源动作改名，并从磁盘实况**重新生成**清单与中转台账。

为什么要重生成而不是改字符串：运行 GLB 已经被**换成了合并后的动画母版**
（153,024 B → 1,230,900 B），旧清单里记的还是改名前的静态 GLB 哈希与体积。
逐字段手改会漏，重生成能让记录与磁盘强制一致。

产物：
- `art_source/.../source/animations/` 下 18 个文件改名为 `<state>.glb`
  （目录本身已是命名空间，再挂 `tvone_` 前缀是冗余）
- `enm_elite_arms_taker_manifest_v001.json`（重生成）
- `enm_elite_arms_taker_transfer_ledger_v001.json`（重生成）
- `入库说明.md`（重写）
"""
import hashlib
import json
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SLUG = "enm_elite_arms_taker"
ASSET_ID = "ENM-ELITE-ARMS-TAKER-3D"
ELITE_ID = "elite_arms_taker"
NAME_CN = "夺械者“收租人”"

ASSET_DIR = os.path.join(ROOT, "assets/art/enemies/elite_3d", SLUG)
COMPONENT_DIR = os.path.join(ASSET_DIR, "components", SLUG)
RUNTIME_DIR = os.path.join(ASSET_DIR, "runtime", SLUG)
SRC_DIR = os.path.join(ROOT, "art_source/enemies/elite_3d", SLUG, "source")
ANIM_DIR = os.path.join(SRC_DIR, "animations")

glb_runtime = os.path.join(COMPONENT_DIR, SLUG + "_visual_top3d.glb")
tscn_runtime = os.path.join(RUNTIME_DIR, SLUG + "_root_top3d.tscn")
script_runtime = os.path.join(RUNTIME_DIR, "elite_arms_taker_formal_visual.gd")

# 18 条动作的权威顺序与时长（秒）。取自美术源《状态机动画清单》。
CLIPS = [
    ("idle", 5.300), ("walk", 1.433), ("run", 0.867),
    ("turn_left", 1.333), ("turn_right", 1.333),
    ("attack_light", 2.667), ("attack_heavy", 1.100), ("attack_jump", 3.700),
    ("block", 1.333), ("dodge", 1.633), ("hit", 2.000),
    ("stagger", 4.933), ("stunned", 2.133), ("death", 4.600),
    ("spawn_standup", 3.100), ("roar", 5.400), ("kneel", 4.267), ("slam", 7.567),
]
LOOPING = {"idle", "walk", "run"}


def sha256_and_size(path):
    data = open(path, "rb").read()
    return hashlib.sha256(data).hexdigest(), len(data)


def res_path(abs_path):
    rel = os.path.relpath(abs_path, ROOT).replace(os.sep, "/")
    return "res://" + rel


def main():
    # ————— 1. 动作文件改名 —————
    renamed = []
    for state, _ in CLIPS:
        old = os.path.join(ANIM_DIR, "tvone_%s.glb" % state)
        new = os.path.join(ANIM_DIR, "%s.glb" % state)
        if os.path.isfile(old):
            if os.path.isfile(new):
                raise RuntimeError("目标已存在，拒绝覆盖：" + new)
            os.rename(old, new)
            renamed.append(state)
        elif not os.path.isfile(new):
            raise RuntimeError("既没有旧名也没有新名：" + state)
    print("[rename] 动作改名 %d 个 -> <state>.glb" % len(renamed))

    # ————— 2. 重生成清单 —————
    runtime_files = []
    # 预览与源说明
    for rel in ["previews/front_negY.png", "previews/back_posY.png", "previews/side_negX.png",
                "状态机动画清单.md"]:
        p = os.path.join(SRC_DIR, rel)
        digest, size = sha256_and_size(p)
        runtime_files.append({"res_path": res_path(p), "bytes": size, "sha256": digest})
    # 18 条动作
    for state, _ in CLIPS:
        p = os.path.join(ANIM_DIR, "%s.glb" % state)
        digest, size = sha256_and_size(p)
        runtime_files.append({"res_path": res_path(p), "bytes": size, "sha256": digest})
    # 运行资产
    for p in [glb_runtime, tscn_runtime, script_runtime]:
        digest, size = sha256_and_size(p)
        runtime_files.append({"res_path": res_path(p), "bytes": size, "sha256": digest})

    animations = []
    for state, duration in CLIPS:
        p = os.path.join(ANIM_DIR, "%s.glb" % state)
        digest, size = sha256_and_size(p)
        animations.append({
            "state": state,
            "source_file": "%s.glb" % state,
            "source_rel": os.path.relpath(p, ROOT).replace(os.sep, "/"),
            "bytes": size,
            "sha256": digest,
            "clips": [{"name": state, "duration_s": duration}],
            "loop": state in LOOPING,
            "loop_basis": "authored" if state in LOOPING else "one_shot",
        })

    glb_digest, glb_size = sha256_and_size(glb_runtime)
    manifest = {
        "manifest_kind": "asset_manifest",
        "schema_version": 1,
        "asset_id": ASSET_ID,
        "slug": SLUG,
        "asset_version": "v001",
        "domain": "enemies",
        "family": "elite_3d",
        "status": "connected_and_verified",
        "elite_id": ELITE_ID,
        "display_name": NAME_CN,
        "generated_at": "2026-11-03T18:30:00+08:00",
        "generated_by": "elite asset formalization (rename tvone01 -> arms_taker, 18-clip master merge)",
        "self_reference_note": "本文件不登记自身哈希；其哈希见同目录 <slug>_transfer_ledger_v001.json 的 outputs。",
        "runtime_visual_glb": {
            "res_path": res_path(glb_runtime),
            "bytes": glb_size,
            "sha256": glb_digest,
            "note": ("动画母版：网格 + 41 骨骨架 + 18 条 animation clip 合并在同一份 GLB 内，"
                     "对齐现有普通怪（小僵尸 6 剪辑 / 胖子僵尸 13 剪辑）的规格。"
                     "合并脚本见 art_source/.../source/animation/author_merge_animation_v001.py。"),
        },
        "skeleton": {
            "bone_count": 41,
            "root_bone": "Root",
            "note": "18 条动作的 joints 名与基础模型逐位一致，合并脚本内已断言。",
        },
        "clip_count": len(CLIPS),
        "runtime_files": runtime_files,
        "animations": animations,
    }
    manifest_path = os.path.join(ASSET_DIR, SLUG + "_manifest_v001.json")
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("[manifest] 已重生成：clip=%d，runtime_files=%d" % (len(CLIPS), len(runtime_files)))

    # ————— 3. 重生成中转台账 —————
    outputs = []
    for item in runtime_files:
        p = os.path.join(ROOT, item["res_path"].replace("res://", "").replace("/", os.sep))
        outputs.append({
            "res_path": item["res_path"],
            "bytes": item["bytes"],
            "sha256": item["sha256"],
        })
    ledger = {
        "ledger_kind": "asset_transfer_ledger",
        "schema_version": 1,
        "asset_id": ASSET_ID,
        "slug": SLUG,
        "asset_version": "v001",
        "generated_at": "2026-11-03T18:30:00+08:00",
        "generated_by": "elite asset formalization (rename tvone01 -> arms_taker)",
        "self_reference_note": "本文件不登记自身哈希。",
        "source_machine": "3号机 sc@100.117.192.4:/home/sc/动作库/04_临时/精英怪01",
        "source_stability": "源机已不可达（Connection refused）；本地工作区为唯一副本。",
        "source_hashes": [
            {"source_file": "%s.glb" % state, "note": "源清单只记状态名，未提供逐文件源哈希。",
             "duration_s": duration}
            for state, duration in CLIPS
        ],
        "outputs": outputs,
        "animations": [a["state"] for a in animations],
        "skeleton": {"bone_count": 41, "root_bone": "Root"},
        "consumers": [
            "src/enemy3d/EliteContentCatalog.gd",
            "src/enemy3d/EnemyAvatar3D.gd",
            "assets/art/enemies/elite_3d/%s/runtime/%s/elite_arms_taker_formal_visual.gd" % (SLUG, SLUG),
        ],
        "rollback": "本次为新增资产；回滚即移除本目录。3 号机源不可达，本地无第二份副本。",
        "compliance": [
            "GLB 只含表现网格与材质，无碰撞、无脚本、无灯光、无相机。",
            "正式运行路径（components/ 与 runtime/）不含版本号。",
            "源（3 号机）只读，未修改。",
        ],
    }
    ledger_path = os.path.join(ASSET_DIR, SLUG + "_transfer_ledger_v001.json")
    with open(ledger_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(ledger, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("[ledger] 已重生成：outputs=%d" % len(outputs))

    # ————— 4. 重写入库说明 —————
    rows = "\n".join(
        "| %d | %s | `%s.glb` | %d | %.3f | %s |"
        % (i + 1, state, state, animations[i]["bytes"], duration,
           "✅" if state in LOOPING else "❌")
        for i, (state, duration) in enumerate(CLIPS)
    )
    doc = """# {slug} · 入库说明

- 资产 ID：`{asset_id}`
- slug：`{slug}`
- 内容 ID / 精英身份：`{elite_id}` · {name_cn}
- 域 / 族：`enemies` / `elite_3d`
- 版本：`v001`（目录与运行文件名均不带版本号）
- 制作状态：`connected_and_verified`
- 入库时间：2026-11-03（同日晚完成正式定名与状态机接线）
- 来源：3 号机 `sc@100.117.192.4:/home/sc/动作库/04_临时/精英怪01`（只读）
  —— **源机现已不可达（Connection refused），本地工作区是唯一副本。**

---

## 1. 这是什么

**夺械者“收租人”** —— 12 只唯一精英中的 `elite_arms_taker`，投放 94F / 93F / 92F
（每局按 `run_seed` 三选一，与首只“背枪的裂口爬虫”的 98—96F 窗口互不重叠）。

造型：电视机头（CRT 显示器 + 天线）人形变异体，西装、歪领带、过膝长外套、工装靴。

**这是精英首次使用真骨骼动画。** 首只 `rift_boar_armed` 的表现 GLB 是纯静态
（`skins=0` / `animations=0`），靠 `EnemyAvatar3D` 的程序化外壳演；本只带
**41 骨 / 18 剪辑**，由表现层逐态驱动 `AnimationPlayer`。

---

## 2. 放了什么、放在哪

### 2.1 运行资产（`assets/art/enemies/elite_3d/{slug}/`）

| 路径 | 内容 |
|---|---|
| `components/{slug}/{slug}_visual_top3d.glb` | **动画母版**：网格 + 41 骨 + 18 剪辑（同一份 GLB 内） |
| `runtime/{slug}/{slug}_root_top3d.tscn` | Godot 包装场景（含元数据，无碰撞） |
| `runtime/{slug}/elite_arms_taker_formal_visual.gd` | 状态机表现脚本（12 态 → 18 剪辑映射） |
| `{slug}_manifest_v001.json` | 本资产清单（全部文件 SHA-256 + 时长） |
| `{slug}_transfer_ledger_v001.json` | 严格中转台账 |
| `入库说明.md` | 本文件 |

### 2.2 制作源（`art_source/enemies/elite_3d/{slug}/source/`）

| 路径 | 内容 |
|---|---|
| `animations/<状态>.glb` | 18 条单状态动作 GLB |
| `previews/{{front_negY,back_posY,side_negX}}.png` | 三视图预览 |
| `状态机动画清单.md` | 3 号机原始动画清单（含接地校验与 SUSPECT 说明） |
| `animation/author_merge_animation_v001.py` | 18 条 → 动画母版的合并脚本 |

> 本次**无 `.blend` 母版**（3 号机产物只有 GLB，且源机已不可达）。

---

## 3. 18 条动作

{crown_note}循环标记：`idle` / `walk` / `run` 为循环段（按相位播），其余为一次性段。

| # | 状态 | 文件 | 字节 | 时长(s) | 循环 |
|---|---|---|---|---|---|
{rows}

> 合并时 `slam` 的源 clip 名是 Blender 默认名（`Armature.001|mixamo.com|Layer0`），
> 母版内已统一归一为 `slam`。
>
> `run` / `hit` / `spawn_standup` / `kneel` 四条在源侧标 `SUSPECT`：接地校验对
> 「非站立静止」动作天然非零，属语义差异而非穿地/悬空。

---

## 4. 状态机（12 态 → 18 剪辑）

事实源：`runtime/{slug}/elite_arms_taker_formal_visual.gd` 的 `CLIP_BY_STATE`。

| 状态 | 剪辑 | 说明 |
|---|---|---|
| `dormant` | idle（钉 0） | 未激活不消耗视觉预算 |
| `idle` / `alert` | idle | 待机与锁定共用 |
| `patrol` | walk | 唯一用走路的移动状态 |
| `chase` / `search` / `return` | run | 按**实际速度**改判走/跑（0.62 进 / 0.50 出，带迟滞） |
| `telegraph` / `attack` / `recovery` | attack_light | 前摇取前段、命中钉中段、收招走尾段 |
| `stagger` | hit | 受击打断 |
| `dead` | death | 倒地保留 2.4s |

驱动链：`Enemy3D` → `EnemyAvatar3D.sync_presentation()` → 精英表现根 `sync_state()`。
判据是**「表现根有没有 `sync_state`」**，不是按 `elite_id` 写死分支。

> **14 条尚未接玩法触发**：`turn_*` / `attack_heavy` / `attack_jump` / `block` /
> `dodge` / `stagger` / `stunned` / `kneel` / `roar` / `spawn_standup` / `slam`
> 目前只有映射表里的主段，没有各自的专属行为。接动作要先有玩法需求。

---

## 5. 验收

| 入口 | 结论 |
|---|---|
| `tests/verification/verify_second_elite_arms_taker.tscn` | `SECOND_ELITE_ARMS_TAKER_OK`（目录/18 剪辑/12 态/窗口/碰撞归属） |
| `tests/verification/probe_second_elite_motion.tscn` | `SECOND_ELITE_MOTION_OK`（真实循环逐态骨骼在动） |
| `python3 scripts/check_asset_registry.py --ledger enemies` | issues=0 |

---

## 6. 纪律与安全

- 源（3 号机）只读，未修改；本次为纯新增，未覆盖任何既有文件。
- GLB 只含表现网格与材质（无碰撞 / 脚本 / 灯光 / 相机）；包装场景无碰撞，
  `Enemy3D` 继续持有 `melee_chaser` 的碰撞、AI、生命、伤害与掉落。
- 运行路径不含版本号；版本号只记在清单、Prefab 根 `metadata/asset_version` 与账本版本列。
""".format(
        slug=SLUG, asset_id=ASSET_ID, elite_id=ELITE_ID, name_cn=NAME_CN,
        rows=rows,
        crown_note="",
    )
    with open(os.path.join(ASSET_DIR, "入库说明.md"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(doc)
    print("[doc] 已重写入库说明.md")


main()
