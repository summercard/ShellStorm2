from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def load_document(path: Path) -> dict:
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20 : 20 + length].decode("utf-8").rstrip("\x00 "))


def main() -> None:
    for value in sys.argv[1:]:
        path = Path(value)
        document = load_document(path)
        print(path)
        for material in document.get("materials", []):
            print(
                " ",
                material.get("name"),
                "pbr=",
                material.get("pbrMetallicRoughness"),
                "emissive=",
                material.get("emissiveFactor"),
                "extensions=",
                material.get("extensions"),
            )


if __name__ == "__main__":
    main()
