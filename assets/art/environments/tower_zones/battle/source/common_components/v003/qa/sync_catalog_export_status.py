"""把各资产包 manifest 的真实导出状态回写到 catalog.json。

背景：catalog.json 由 build_common_library_v003.py 在建模阶段一次性生成，里面
`exported` 与 `collision` 是写死的初值（false / not_created）。之后每次把某个组件
做成正式资产，只会回填该组件自己的 asset_manifest.json，catalog 从此停在旧快照上——
于是同一个组件在两份文件里说法不同，看 catalog 会以为地砖根本没导出。

这个脚本以 asset_manifest.json 为准，把 exported / collision 同步进 catalog.json，
并顺带带上 visual_glb / runtime_scene（有则写、无则删除），让 catalog 真正能当索引用。

幂等：状态已一致时不写文件。可反复运行。
不改 manifest，不改其它字段。
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

QA_DIR = Path(__file__).resolve().parent
V003_DIR = QA_DIR.parent
PKG_DIR = V003_DIR / "component_packages_v003"
CATALOG_PATH = PKG_DIR / "catalog.json"
BACKUP_PATH = CATALOG_PATH.with_suffix(".json.bak_sync_export_status")

# 从 manifest 同步到 catalog 的字段。"exported"/"collision" 两边都有；
# visual_glb / runtime_scene 是资产落成后才出现的，有则同步、无则从 catalog 删除。
SYNCED_KEYS = ("exported", "collision", "visual_glb", "runtime_scene")
OPTIONAL_KEYS = ("visual_glb", "runtime_scene")


def manifest_path_for(entry: dict) -> Path:
    category_id = entry["category"].split("_")[0]
    return PKG_DIR / category_id / entry["slug"] / "asset_manifest.json"


def main() -> int:
    if not CATALOG_PATH.is_file():
        print(f"FAIL 找不到 catalog: {CATALOG_PATH}")
        return 1

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    updated: list[str] = []
    missing_manifest: list[str] = []
    already = 0

    for entry in catalog:
        mpath = manifest_path_for(entry)
        if not mpath.is_file():
            missing_manifest.append(entry["slug"])
            continue
        manifest = json.loads(mpath.read_text(encoding="utf-8"))
        changed = False
        for key in SYNCED_KEYS:
            if key in manifest:
                if entry.get(key) != manifest[key]:
                    entry[key] = manifest[key]
                    changed = True
            elif key in OPTIONAL_KEYS and key in entry:
                del entry[key]
                changed = True
        if changed:
            updated.append(entry["slug"])
        else:
            already += 1

    if missing_manifest:
        print("FAIL 以下资产包缺少 manifest，catalog 无法判定状态：")
        for slug in missing_manifest:
            print(f"  - {slug}")
        return 1

    if not updated:
        print(f"CATALOG_EXPORT_STATUS_OK: 无需同步（{already} 条已一致）")
        return 0

    shutil.copy2(CATALOG_PATH, BACKUP_PATH)
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(f"已同步 {len(updated)} 条，备份 {BACKUP_PATH.name}")
    for slug in updated:
        print(f"  - {slug}")
    exported = sum(1 for e in catalog if e.get("exported") is True)
    print(f"CATALOG_EXPORT_STATUS_OK: catalog 共 {len(catalog)} 条，其中 exported=true {exported} 条")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
