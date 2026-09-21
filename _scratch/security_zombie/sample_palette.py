import bpy
from pathlib import Path
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
pal_path=str(P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png')
img=bpy.data.images.load(pal_path)
img.scale(100,100)  # 10x10 cells, 1px each (nearest)
px=img.pixels[:]  # RGBA float list length 100*100*4
# sample center of each cell (cell c = col x, row y) => pixel index
def cell_color(col,row):
    # image is 100x100, cell col 0..9 row 0..9; sample at (col*10+5, row*10+5)
    x=col*10+5; y=row*10+5
    i=(y*100+x)*4
    return (round(px[i],3),round(px[i+1],3),round(px[i+2],3))
print('PALETTE_PATH', pal_path)
print('SIZE', img.size)
for row in range(10):
    line=[]
    for col in range(10):
        r,g,b=cell_color(col,row)
        line.append(f'({col},{row}):{r:.2f},{g:.2f},{b:.2f}')
    print(' | '.join(line))
