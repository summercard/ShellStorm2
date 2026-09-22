"""把 Write 工具产出的 LF 文件转为 CRLF（二进制读写，禁文本模式）。

用法：python to_crlf.py <file> [...]
判据：转换前后都断言无 CRCRLF；转换后 CR == LF。
"""
import sys
from pathlib import Path

for arg in sys.argv[1:]:
    p = Path(arg)
    data = p.read_bytes()
    assert b"\r" not in data, f"{p.name} 已含 CR，勿二次转换（会得到 CRCRLF）"
    data = data.replace(b"\n", b"\r\n")
    p.write_bytes(data)
    b = p.read_bytes()
    cr, lf = b.count(b"\r"), b.count(b"\n")
    print(f"{p.name} CR={cr} LF={lf} diff={cr - lf} CRCRLF={b.count(b'\r\r\n')}")
