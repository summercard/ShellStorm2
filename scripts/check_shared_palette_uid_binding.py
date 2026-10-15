#!/usr/bin/env python3
"""门禁：共享色盘 UID 契约与消费者缓存新鲜度。

背景（2026-10-16 实测）
    环境/设施 GLB 的材质不内嵌贴图，而是由导入后脚本
    `tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`
    统一绑定到同一张共享色盘。这形成一条**跨文件、跨语言、跨进程生命周期的隐形契约**：

        811 个 GLB 的导入产物 `.godot/imported/*.scn`（RSCC/zstd 压缩二进制）
        里冻结着「色盘资源的外部引用 UID」。

    一旦色盘的 `.import` 被删除重建（例如切换压缩格式 s3tc/etc2、开关 mipmap），
    Godot 会为它**重新分配一个全新 UID**，而 811 个 `.scn` 仍指向旧 UID。
    后果不是崩溃，而是**静默降级**：加载时 UID 校验失败、回退文本路径、贴图照常显示，
    但每次进局刷出 900+ 条 `invalid UID ... using text path instead` 警告，
    把调试器的真实错误一起淹掉（本轮实测 938 条警告 / 28 条真错误被埋在中间）。

    光靠注释说明，几个月后没人记得这条契约。所以这里放一条会失败的断言。

检查项
    A.「源头」色盘 `.import` 的 uid 必须等于 `scripts/shared_palette_uid_contract.json`
       的登记值。不等 → 退出 1：UID 已漂移，必须重导全部消费者并更新契约。
    B.「消费端」色盘 `.import` 的 mtime 不得晚于任何消费者的 `.scn` 缓存 mtime。
       晚于 → 退出 2：缓存陈旧，重导消费者即可，无需改契约。

退出码
    0  契约一致且缓存新鲜
    1  UID 漂移（源头契约被破坏，需重导 + --update-contract）
    2  契约缺失 / 缓存陈旧（需处理，但不算上游违规）

用法
    python3 scripts/check_shared_palette_uid_binding.py
    python3 scripts/check_shared_palette_uid_binding.py --update-contract
    python3 scripts/check_shared_palette_uid_binding.py --json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
ART_ROOT = PROJECT / "assets"
PALETTE_DIR = ART_ROOT / "art" / "shared" / "palette"
PALETTE_PNG = PALETTE_DIR / "设施低亮多巴胺色盘_10x10_512.png"
PALETTE_IMPORT = PALETTE_DIR / "设施低亮多巴胺色盘_10x10_512.png.import"
PALETTE_NAME = "设施低亮多巴胺色盘"
IMPORT_SCRIPT_DIR = PROJECT / "tools" / "asset_pipeline"
CONTRACT = Path(__file__).resolve().parent / "shared_palette_uid_contract.json"

_UID_RE = re.compile(r'^uid="(uid://[0-9a-z]+)"', re.MULTILINE)
_DEST_SCN_RE = re.compile(r'dest_files=\["(res://[^"]*\.scn)"\]')
_MTIME_TOLERANCE_S = 1.0

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def read_palette_uid() -> str:
    """从色盘 .import 读出 Godot 当前分配的 UID 文本。"""
    if not PALETTE_IMPORT.is_file():
        return ""
    match = _UID_RE.search(PALETTE_IMPORT.read_text(encoding="utf-8", errors="replace"))
    return match.group(1) if match else ""


def discover_binding_scripts() -> list[str]:
    """自动发现所有把共享色盘绑进 GLB 材质的导入后脚本。

    2026-10-16 实测教训：修复时先只登记了 scene_facility_shared_palette_post_import.gd
    覆盖的 811 个 GLB，漏掉 scene_facility_door_visual_post_import.gd 覆盖的 1 个，
    第一次重导后仍有 1 条 "invalid UID" 警告残留。所以这里改为**扫目录**，
    新增绑定脚本自动纳入，杜绝再次漏项。
    """
    found: list[str] = []
    for gd in sorted(IMPORT_SCRIPT_DIR.glob("*post_import*.gd")):
        try:
            text = gd.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if PALETTE_NAME in text:
            found.append(gd.name)
    return found


def collect_consumers() -> list[tuple[str, Path]]:
    """扫出所有引用共享色盘的 GLB，返回 [(源 GLB 相对路径, 对应 .scn 绝对路径)]。"""
    scripts = discover_binding_scripts()
    consumers: list[tuple[str, Path]] = []
    for imp in sorted(ART_ROOT.rglob("*.glb.import")):
        try:
            text = imp.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not any(name in text for name in scripts):
            continue
        match = _DEST_SCN_RE.search(text)
        if not match:
            continue
        scn_abs = PROJECT / match.group(1)[len("res://"):]
        consumers.append((imp.relative_to(PROJECT).as_posix()[: -len(".import")], scn_abs))
    return consumers


def load_contract() -> dict:
    if not CONTRACT.is_file():
        return {}
    try:
        return json.loads(CONTRACT.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def write_contract(uid: str, consumer_count: int) -> None:
    payload = {
        "_comment": (
            "共享色盘 UID 契约。色盘 .import 被重建会导致 UID 重分配，"
            "令全部消费者的 .scn 缓存失效。改动此值必须同时重导消费者。"
        ),
        "palette": PALETTE_PNG.relative_to(PROJECT).as_posix(),
        "uid": uid,
        "consumers_expected": consumer_count,
    }
    CONTRACT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="共享色盘 UID 契约门禁")
    parser.add_argument("--update-contract", action="store_true", help="按现状重写契约快照")
    parser.add_argument("--json", action="store_true", help="输出机器可读结果")
    parser.add_argument("--max-report", type=int, default=10, help="单类问题最多列几条")
    args = parser.parse_args()

    current_uid = read_palette_uid()
    if not current_uid:
        print(f"FAIL: 无法从 {PALETTE_IMPORT.relative_to(PROJECT)} 读出 uid")
        return 2

    consumers = collect_consumers()
    if not consumers:
        print("FAIL: 未扫到任何引用共享色盘的 GLB（绑定脚本是否被改名/移除？）")
        return 2

    if args.update_contract:
        write_contract(current_uid, len(consumers))
        print(f"已更新契约：uid={current_uid}  consumers={len(consumers)}")
        return 0

    contract = load_contract()
    contract_uid = contract.get("uid", "")

    palette_mtime = PALETTE_IMPORT.stat().st_mtime
    missing: list[str] = []
    stale: list[str] = []
    for _imp, scn in consumers:
        if not scn.is_file():
            missing.append(scn.relative_to(PROJECT).as_posix())
            continue
        if palette_mtime - scn.stat().st_mtime > _MTIME_TOLERANCE_S:
            stale.append(scn.relative_to(PROJECT).as_posix())

    uid_drifted = contract_uid != current_uid
    ok = not uid_drifted and not missing and not stale

    if args.json:
        print(json.dumps({
            "ok": ok,
            "palette_uid": current_uid,
            "contract_uid": contract_uid,
            "uid_drifted": uid_drifted,
            "consumers": len(consumers),
            "missing_scn": missing,
            "stale_scn": stale,
        }, ensure_ascii=False, indent=2))
    else:
        print(f"色盘当前 uid      : {current_uid}")
        print(f"契约登记 uid      : {contract_uid or '(缺失)'}")
        print(f"消费者 GLB        : {len(consumers)} 个")
        print(f"缓存缺失 .scn     : {len(missing)} 个")
        print(f"缓存陈旧 .scn     : {len(stale)} 个")
        print()

        if uid_drifted:
            print("✗ A. 源头 UID 与契约不符 —— 色盘 .import 被重建过。")
            print("     修复：重导全部消费者，然后 --update-contract 更新登记值。")
            for rel in stale[:args.max_report]:
                print(f"       · 陈旧: {rel}")
            if len(stale) > args.max_report:
                print(f"       · ...（另有 {len(stale) - args.max_report} 个）")
        else:
            print("✓ A. 源头 UID 与契约一致")

        if missing:
            print(f"✗ B. {len(missing)} 个消费者缺少导入产物（.godot 缓存不全或被清过）")
            for rel in missing[:args.max_report]:
                print(f"       · 缺失: {rel}")
        elif stale:
            print(f"✗ B. {len(stale)} 个消费者的缓存早于色盘 .import —— 需重导")
            for rel in stale[:args.max_report]:
                print(f"       · 陈旧: {rel}")
            if len(stale) > args.max_report:
                print(f"       · ...（另有 {len(stale) - args.max_report} 个）")
        else:
            print("✓ B. 全部消费者缓存新鲜")

        print()
        print("PASS" if ok else "FAIL")

    if uid_drifted:
        return 1
    if missing or stale:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
