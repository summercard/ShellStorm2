# Measuring a Render Against a Reference

Run this on **both** images, in the same version, with the same crop. The reference supplies the target; the render is compared to it. Never import one project's target numbers into another project — re-measure.

## Script (python3 + Pillow)

```python
# usage: python3 stats.py REF.png RENDER.png [--crop y0,y1]
import sys
from PIL import Image

def load(p, crop=None):
    im = Image.open(p).convert("RGB")
    if crop:
        y0, y1 = crop
        im = im.crop((0, y0, im.width, y1))
    return im

def stats(im):
    px = list(im.getdata())
    n = len(px)
    L, warm, cool, white, mid = [], 0, 0, 0, 0
    for r, g, b in px:
        l = 0.2126*r + 0.7152*g + 0.0722*b
        L.append(l)
        mx, mn = max(r, g, b), min(r, g, b)
        v = mx / 255.0
        s = 0 if mx == 0 else (mx - mn) / mx
        if mx == mn:
            h = 0
        elif mx == r:
            h = (60 * ((g - b) / (mx - mn))) % 360
        elif mx == g:
            h = 60 * ((b - r) / (mx - mn)) + 120
        else:
            h = 60 * ((r - g) / (mx - mn)) + 240
        if s >= 0.15 and v >= 0.10:
            if h < 60 or h >= 300: warm += 1
            elif 150 <= h <= 270: cool += 1
        if v >= 0.93 and s <= 0.10: white += 1
        if 40 <= l <= 170: mid += 1
    L.sort()
    q = lambda p: L[min(n-1, int(n*p))]
    return {"meanL": sum(L)/n, "p25": q(.25), "p50": q(.50), "p75": q(.75),
            "p95": q(.95), "p99": q(.99),
            "warm%": 100*warm/n, "cool%": 100*cool/n,
            "white%": 100*white/n, "mid%": 100*mid/n}

def regions(im, cols=3, rows=3):
    out = {}
    w, h = im.width // cols, im.height // rows
    for j in range(rows):
        for i in range(cols):
            out[f"r{j}c{i}"] = stats(im.crop((i*w, j*h, (i+1)*w, (j+1)*h)))["meanL"]
    return out

ref, ren = load(sys.argv[1]), load(sys.argv[2])
for name, im in (("ref", ref), ("render", ren)):
    print(name, {k: round(v, 1) for k, v in stats(im).items()})
```

Add named region boxes (left facade, stairs, right wall, arch window, foreground) where a 3×3 grid is too coarse; judge each within **±10** of the reference's region mean. For the stairs case, the five named regions were left facade 71.6, stairs 54.4, right wall 41.1, arch window 65.3, foreground 56.8 — and the rejected render was 130–171 everywhere.

## Metric definitions (keep identical across both images)

| Metric | Definition |
|---|---|
| `meanL` | mean of `0.2126R + 0.7152G + 0.0722B`, 0–255 |
| `p25…p99` | percentiles of L — they expose a crushed or blown tonal range that the mean hides |
| `warm%` | hue < 60° or ≥ 300°, saturation ≥ 0.15, value ≥ 0.10 |
| `cool%` | hue 150–270°, same saturation/value gate |
| `white%` | value ≥ 0.93 and saturation ≤ 0.10 |
| `mid%` | L in 40–170 |

A reference with `cool% ≈ 0` is legitimate: its cool read can be near-white highlights over neutral dark shadows. Do not manufacture a cool-coloured block to satisfy a "30/70" rule in such a frame; check where the minority temperature actually sits before writing a colour instruction.

## Two pitfalls that cost a round trip each

**Pick one warm/cool definition per task and never mix it.** The script above gates on hue + saturation + value. A simpler channel-cast test — warm when `r-b ≥ 14 and r ≥ 80`, cool when `b-r ≥ 14 and b ≥ 80` — gives very different percentages on the same image (a reference measured 8.1% warm by channel cast while a hue-based pass on another dark frame read 63%). Both are valid; mixing them across a project makes every target unreachable. State the definition in the task book next to the numbers so the worker reproduces the same one.

**Pillow only — no numpy assumption.** `numpy` is not installed on this Mac (`ModuleNotFoundError: No module named 'numpy'`). Keep the script pure Python: `im.tobytes()` plus a list index is fast enough (1.44 MP ≈ a few seconds, including the sort for percentiles). Do not add a `pip install` step to a grading task.

**Midtone band is not universal either.** The band above is `40 ≤ L ≤ 170`; a dark reference may need `45 ≤ L ≤ 150` to mean anything. Choose the band from the reference's own histogram and keep it fixed for the project.

## Report format

One table, three columns — reference / previous render / this render — plus a pass column. Then the same table for named regions. A report that gives only the new numbers, or only a seven-dimension self-score, cannot be checked and should be sent back.

The worker must run **this same script** and paste its output. "几乎重合" without the table is a claim, not a measurement.
