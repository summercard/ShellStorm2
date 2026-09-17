"""给 08 墙壁 / 10 门组件三件新 GLB 的 .glb.import 打公共色盘导入契约。

背景：Godot 首次导入 GLB 时生成的 .import 里 import_script/path 为空、
gltf/embedded_image_handling=1。按 v003 全库与 scene_facility_shared_palette 契约，
必须改成：
  import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
  gltf/embedded_image_handling=0
（着色贴图统一走公共色盘本身由后处理脚本完成；此处只负责把导入参数接对。）

做法与项目既有 tools/asset_pipeline/configure_base_facility_v022_imports.py 完全一致：
只做两处字符串替换，不重写文件结构，保持 Godot 生成的其他字段原样。

幂等：已经是目标值则 SKIP。补丁前备份 <name>.import.bak_pre_palette。
运行（必须在 Godot 至少导入过一次、.import 已存在之后）：
  "C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe" bind_wall_door_palette_imports.py
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent          # .../v003/qa
V003 = HERE.parent                              # .../v003
SOURCE_DIR = V003.parent.parent                 # .../source
BATTLE = SOURCE_DIR.parent                      # .../battle
ROOT = BATTLE.parents[4]                        # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

import sys

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

COMPONENTS = BATTLE / "components" / "common_components"

TARGET_SCRIPT = '"res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"'
EMPTY_SCRIPT = 'import_script/path=""'
WRONG_EMBED = "gltf/embedded_image_handling=1"
RIGHT_EMBED = "gltf/embedded_image_handling=0"

SLUGS = ["wall_standard_5m", "wall_door_5m", "door_5m"]


def main() -> int:
    results = {}
    for slug in SLUGS:
        glb = COMPONENTS / slug / grn.visual_glb_name(slug)
        imp = Path(str(glb) + ".import")
        if not glb.is_file():
            raise SystemExit(f"缺少 GLB（先跑导出脚本）: {glb}")
        if not imp.is_file():
            raise SystemExit(f"缺少 .import（先跑 godot --headless --import）: {imp}")

        text = imp.read_text(encoding="utf-8")
        original = text
        text = text.replace(EMPTY_SCRIPT, f'import_script/path={TARGET_SCRIPT}')
        text = text.replace(WRONG_EMBED, RIGHT_EMBED)

        if text == original:
            results[slug] = "unchanged"
            print(f"SKIP {slug}: 契约已就位（幂等）")
            continue

        # 历史由 git 承担，不再落 `*.bak_pre_palette`（工作区不保留旧资产副本）。
        imp.write_text(text, encoding="utf-8")
        results[slug] = "patched"
        print(f"PATCHED {slug} -> {imp}")

    # 复验：每个 .import 必须同时满足两条契约
    failures = []
    for slug in SLUGS:
        imp = Path(str(COMPONENTS / slug / grn.visual_glb_name(slug)) + ".import")
        text = imp.read_text(encoding="utf-8")
        if f'import_script/path={TARGET_SCRIPT}' not in text:
            failures.append(f"{slug}: import_script/path 未指向公共色盘后处理脚本")
        if RIGHT_EMBED not in text:
            failures.append(f"{slug}: gltf/embedded_image_handling 不是 0")
        if WRONG_EMBED in text:
            failures.append(f"{slug}: 仍残留 embedded_image_handling=1")
    if failures:
        for f in failures:
            print(f"FAIL {f}")
        print("BIND_WALL_DOOR_PALETTE_IMPORTS_FAIL")
        return 1

    print("BIND_REPORT " + str(results))
    print(f"BIND_WALL_DOOR_PALETTE_IMPORTS_OK total={len(SLUGS)} patched={sum(1 for v in results.values() if v == 'patched')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
