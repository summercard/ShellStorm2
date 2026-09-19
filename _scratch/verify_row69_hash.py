"""Confirm ledger row 69 (ENV-TOWER-CORNER-L-5M) still holds the on-disk GLB hash."""

import hashlib
import io
import re
import zipfile

GLB = r"assets/art/environments/tower_descent_3d/components/env_tower_corner_l_5m_top3d.glb"
XLSX = r"assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"

COL_RE = lambda col, row: re.compile(
    r'<c r="%s%d"([^>]*?)(?:/>|>(.*?)</c>)' % (col, row), re.S
)


def main() -> None:
    blob = open(GLB, "rb").read()
    digest = hashlib.sha256(blob).hexdigest()
    print("GLB bytes :", len(blob))
    print("GLB sha256:", digest)

    zf = zipfile.ZipFile(XLSX)
    names = [n for n in zf.namelist() if n.startswith("xl/worksheets/")]
    print("worksheets:", names)

    shared = []
    if "xl/sharedStrings.xml" in zf.namelist():
        xml = zf.read("xl/sharedStrings.xml").decode("utf-8")
        for si in re.findall(r"<si>(.*?)</si>", xml, re.S):
            shared.append("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S)))

    for name in names:
        sheet = zf.read(name).decode("utf-8")
        if "ENV-TOWER-CORNER-L-5M" not in "".join(shared) and 'r="69"' not in sheet:
            continue
        rows = re.findall(r'<row r="(\d+)"', sheet)
        print("%s rows r= present: %d, has 69: %s" % (name, len(rows), "69" in rows))

        def value(col: str, row: str) -> str:
            m = COL_RE(col, int(row)).search(sheet)
            if m is None:
                return "<missing>"
            attrs = m.group(1) or ""
            body = m.group(2) or ""
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            val = v.group(1) if v else ""
            if 't="s"' in attrs and val.isdigit():
                val = shared[int(val)]
            elif 't="inlineStr"' in attrs:
                t = re.search(r"<t[^>]*>(.*?)</t>", body, re.S)
                val = t.group(1) if t else val
            return val

        print("  A69 =", value("A", "69"))
        print("  N69 =", value("N", "69"))
        t69 = value("T", "69")
        print("  T69 =", t69)
        print("  T69 == disk sha256 :", t69.strip().lower() == digest)
        print("  Y69 head:", value("Y", "69")[:100])


main()
