"""给 v004 五件 GLB 的 .glb.import 打公共色盘导入契约。

背景：Godot 首次导入 GLB 时生成的 .import 里 import_script/path 为空、
gltf/embedded_image_handling=1。按全库与 scene_facility_shared_palette 契约，必须改成：
  import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
  gltf/embedded_image_handling=0

做法与 v003 的 bind_wall_door_palette_imports.py 一致：只做两处字符串替换，
不重写文件结构，保持 Godot 生成的其他字段原样。

运行（必须在 Godot 至少导入过一次、.import 已存在之后）：
  "C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe" bind_v004_palette_imports.py
"""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent          # .../<版本>/qa
VERSION_DIR = HERE.parent                       # .../<版本>
SOURCE_DIR = VERSION_DIR.parent.parent
BATTLE = SOURCE_DIR.parent
ROOT = BATTLE.parents[4]
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

# 版本号只用于日志；Godot 侧路径恒定、不含版本号。
VERSION = grn.version_from_argv(VERSION_DIR.name)
COMPONENTS = BATTLE / "components" / "common_components"

TARGET_SCRIPT = '"res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"'
EMPTY_SCRIPT = 'import_script/path=""'
WRONG_EMBED = "gltf/embedded_image_handling=1"
RIGHT_EMBED = "gltf/embedded_image_handling=0"

# (slug, 出包子目录)
TARGETS = [
    ("wall_standard_5m", "wall_standard_5m"),
    ("wall_door_5m", "wall_door_5m"),
    ("door_5m", "door_5m"),
    ("floor_tile_r01_c01", "floor_tile_5m"),
    ("floor_tile_r01_c02", "floor_tile_5m"),
]


def main() -> int:
    results = {}
    for slug, sub in TARGETS:
        glb = COMPONENTS / sub / grn.visual_glb_name(slug)
        imp = Path(str(glb) + ".import")
        if not glb.is_file():
            raise SystemExit(f"缺少 GLB（先跑导出脚本）: {glb}")
        if not imp.is_file():
            raise SystemExit(f"缺少 .import（先跑 godot --headless --import）: {imp}")

        text = imp.read_text(encoding="utf-8")
        original = text
        text = text.replace(EMPTY_SCRIPT, f"import_script/path={TARGET_SCRIPT}")
        text = text.replace(WRONG_EMBED, RIGHT_EMBED)

        if text == original:
            results[slug] = "unchanged"
            print(f"SKIP {slug}: 契约已就位（幂等）")
            continue

        # 历史由 git 承担，不再落 `*.bak_pre_palette`（工作区不保留旧资产副本）。
        imp.write_text(text, encoding="utf-8")
        results[slug] = "patched"
        print(f"PATCHED {slug} -> {imp}")

    failures = []
    for slug, sub in TARGETS:
        imp = Path(str(COMPONENTS / sub / grn.visual_glb_name(slug)) + ".import")
        text = imp.read_text(encoding="utf-8")
        if f"import_script/path={TARGET_SCRIPT}" not in text:
            failures.append(f"{slug}: import_script/path 未指向公共色盘后处理脚本")
        if RIGHT_EMBED not in text:
            failures.append(f"{slug}: gltf/embedded_image_handling 不是 0")
        if WRONG_EMBED in text:
            failures.append(f"{slug}: 仍残留 embedded_image_handling=1")
    if failures:
        for f in failures:
            print(f"FAIL {f}")
        print("BIND_V004_PALETTE_IMPORTS_FAIL")
        return 1

    print("BIND_REPORT " + str(results))
    print(f"BIND_V004_PALETTE_IMPORTS_OK total={len(TARGETS)} "
          f"patched={sum(1 for v in results.values() if v == 'patched')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
