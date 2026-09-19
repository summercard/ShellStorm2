"""极简 PNG 解码 + 像素差异量化（无第三方依赖）。
用途：客观判断两张 Godot 截图是不是真的不同，而不是靠肉眼。
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    pos = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
    assert bit_depth == 8, "only 8-bit supported"
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        ftype = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, bytes(out)


def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    wa, ha, ca, a = read_png(a_path)
    wb, hb, cb, b = read_png(b_path)
    print(f"A: {wa}x{ha} ch={ca}")
    print(f"B: {wb}x{hb} ch={cb}")
    if (wa, ha, ca) != (wb, hb, cb):
        print("尺寸/通道不同 → 必然不同")
        return
    # 只看画面中央 3/4 区域，避开 HUD 时钟等噪声。
    x0, x1 = int(wa * 0.12), int(wa * 0.88)
    y0, y1 = int(ha * 0.10), int(ha * 0.90)
    total = 0
    diff_pixels = 0
    big_diff = 0
    samples = 0
    for y in range(y0, y1, 2):
        row = y * wa * ca
        for x in range(x0, x1, 2):
            i = row + x * ca
            d = abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])
            total += d
            samples += 1
            if d > 12:
                diff_pixels += 1
            if d > 90:
                big_diff += 1
    print(f"中央区域采样 {samples} 点")
    print(f"平均通道差 {total / max(samples, 1) / 3:.2f} / 255")
    print(f"明显不同(d>12) 占比 {100.0 * diff_pixels / max(samples, 1):.1f}%")
    print(f"大幅不同(d>90) 占比 {100.0 * big_diff / max(samples, 1):.1f}%")
    verdict = "不同画面" if diff_pixels / max(samples, 1) > 0.05 else "几乎同一画面"
    print(f"判定: {verdict}")


if __name__ == "__main__":
    main()
