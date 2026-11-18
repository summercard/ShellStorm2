"""只读检查入口：七份 TSCN 是唯一可编辑真源，已禁用场景及贴图生成覆盖。"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).resolve().parent


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_runtime_texture(path: Path) -> None:
    header = path.read_bytes()[:33]
    if len(header) != 33 or header[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR":
        raise SystemExit(f"运行贴图不是有效 PNG：{path}")
    width, height, depth, color_type = struct.unpack(">IIBB", header[16:26])
    if (width, height, depth, color_type) != (256, 256, 8, 6):
        raise SystemExit(f"运行贴图必须为 256x256、8 位 RGBA：{path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefabs-only", action="store_true", help="兼容旧调用；仍仅只读检查，不写场景或贴图")
    parser.parse_args()
    manifest = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    source_paths = set()
    for source in manifest["source_textures"]:
        path = ROOT / source["path"]
        if sha256(path) != source["sha256"]:
            raise SystemExit(f"原图 SHA256 不匹配：{path}")
        source_paths.add(source["path"])
    for asset in manifest["assets"]:
        prefab = ROOT / asset["prefab"]
        text = prefab.read_text(encoding="utf-8")
        amount = re.search(r"^amount = (\d+)$", text, re.MULTILINE)
        if amount is None or 'metadata/asset_version = "v004"' not in text:
            raise SystemExit(f"Prefab 缺少数量或 v004 元信息：{prefab}")
        if asset["source_texture"] not in source_paths:
            raise SystemExit(f"纹理缺少原图来源登记：{prefab}")
        runtime_path = asset["runtime_texture"]["path"]
        texture = ROOT / runtime_path
        if f'path="res://{runtime_path}"' not in text:
            raise SystemExit(f"Prefab 贴图引用与清单不一致：{prefab}")
        if sha256(texture) != asset["runtime_texture"]["sha256"]:
            raise SystemExit(f"运行贴图 SHA256 不匹配：{texture}")
        check_runtime_texture(texture)
        print(f"{asset['key']}: authored amount={amount.group(1)}；{asset['prefab']}")
    print("只读检查完成；未写入任何文件，未运行 Godot。请直接编辑七份 TSCN 的粒子参数。")
    print("原图与运行贴图来源及 SHA256 见 manifest.json；许可未提供，待核对。")


if __name__ == "__main__":
    main()
