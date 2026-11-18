"""Bake the six impact poses per attribute at 4x and downsample with premultiplied alpha."""
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw

CELL, SS, FRAMES = 96, 4, 6
ROWS = [
    ("fire", "#ff5930", "#fff1a0"),
    ("ice", "#65caff", "#edffff"),
    ("poison", "#62d247", "#e5ff97"),
    ("lightning", "#719aff", "#f2fbff"),
    ("bounce", "#ff9935", "#fff2a0"),
    ("homing", "#30ddb0", "#defff2"),
    ("return", "#ab73ff", "#ffe3ff"),
    ("sticky", "#44d598", "#d6fff0"),
    ("ricochet", "#3a9bff", "#d7f5ff"),
    ("piercing", "#65deeb", "#ebfeff"),
    ("explosive", "#ff6937", "#ffdf88"),
    ("seeker", "#84db4a", "#f2ffb8"),
    ("blackhole", "#7538b9", "#dfa7ff"),
    ("balloon", "#f46da9", "#ffe7f2"),
]


def tile(key, edge, hot, frame):
    image = Image.new("RGBA", (CELL * SS, CELL * SS))
    draw = ImageDraw.Draw(image)
    t = frame / (FRAMES - 1)
    reach = 15 + 25 * (1 - (1 - t) ** 2)

    def point(x, y):
        return (round((CELL / 2 + x) * SS), round((CELL / 2 + y) * SS))

    def poly(points, color):
        draw.polygon([point(x, y) for x, y in points], fill=color)

    def line(points, color, width):
        draw.line([point(x, y) for x, y in points], fill=color,
                  width=max(1, round(width * SS)), joint="curve")

    def arc(x, y, r, start, end, color, width):
        draw.arc([point(x-r, y-r), point(x+r, y+r)], start, end,
                 fill=color, width=max(1, round(width * SS)))

    def radial(angle, radius, tangent=0):
        return (cos(angle)*radius - sin(angle)*tangent, sin(angle)*radius + cos(angle)*tangent)

    if key == "fire":
        for i, length in enumerate([0.73, 1, 0.64]):
            x, h = (i-1)*13, reach*length
            y = 11 - t*9
            poly([(x-8,y), (x-10,y-h*.45), (x-3,y-h*.68),
                  (x+3,y-h-3), (x+7,y-h*.62), (x+4,y-h*.39), (x+10,y-5)], edge)
            poly([(x-4,y), (x-3,y-h*.36), (x+3,y-h*.60), (x+2,y-h*.26), (x+5,y-2)], hot)
    elif key == "ice":
        for i in range(6):
            a = i*pi/3 + 0.28
            r = reach*(1 if i%2 else .75)
            base = r*(.14+.46*t)
            poly([radial(a,base),radial(a,r*.75,-4),radial(a,r),radial(a,r*.63,3)],edge)
            poly([radial(a,base),radial(a,r*.75,-4),radial(a,r)],hot)
    elif key == "poison":
        for i,(x,y,r) in enumerate([(-13,3,12),(10,-8,15),(21,13,6),(-4,-21,7)]):
            f = .4+.6*t
            x,y,r = x*f, y*f-9*t, r*(.65+.5*t)
            arc(x,y,r,18+85*t,345-70*t,edge,4-1.7*t)
            arc(x,y,r-2,205,275,hot,2.6)
    elif key == "lightning":
        for i in range(3):
            a=i*2*pi/3-.95
            flip = (-1)**(frame+i)
            pts=[radial(a,3+9*t), radial(a,reach*.46,6*flip),
                 radial(a,reach*.59,-3*flip),radial(a,reach)]
            line(pts,edge,5-2*t)
            line(pts,hot,2.3-t)
            line([pts[1],radial(a,reach*.64,13*flip),radial(a,reach*.85,11*flip)],edge,2)
    elif key == "bounce":
        for offset in (0,10):
            x = -reach*.85 + offset
            pts=[(x,-reach*.48),(x+reach*.52,reach*.48),(x+reach*1.35,-reach*.65)]
            line(pts,edge if offset else hot,4.8-1.5*t)
    elif key == "homing":
        r=35-22*t
        for i in range(4):
            a=i*pi/2+.24
            line([radial(a,r+5,-6), radial(a,r-2),radial(a,r+5,6)],edge,4)
            line([radial(a,r-3),radial(a,r-8)],hot,2.5)
        arc(0,0,4+2*t,0,360,hot,2)
    elif key == "return":
        for half in (0,180):
            a = half+35+155*t
            r = 13+12*sin(pi*t)
            arc(0,0,r,a-130,a,edge,5)
            arc(0,0,r-1,a-43,a,hot,2.5)
            theta=a*pi/180
            poly([radial(theta,r,-4),radial(theta,r-5,-1),
                  radial(theta,r,8),radial(theta,r+5,-2)],hot)
    elif key == "sticky":
        # A tethered splat stretches, then settles into three droplets.
        for angle, length in [(.3, 25), (2.4, 20), (4.3, 28)]:
            r = 8 + length * sin(t*pi*.72)
            x, y = radial(angle, r)
            poly([radial(angle, 3, -8), radial(angle, r, -2),
                  radial(angle, r, 2), radial(angle, 3, 8)], edge)
            draw.ellipse([point(x-5, y-5), point(x+5, y+5)], fill=edge)
            line([(x-2, y-2), (x+1, y-3)], hot, 2)
        draw.ellipse([point(-9,-8), point(9,8)], fill=edge)
    elif key == "ricochet":
        # Sharp ricochet tangent with a blue contact flash and a travelling tip.
        pts = [(-reach, -reach*.3), (-5, 6), (reach*.85, -reach*.65)]
        line(pts, edge, 7-3*t)
        line([pts[1], pts[2]], hot, 2.5)
        arc(-5, 6, 7+13*t, 35, 150, hot, 2.7)
    elif key == "piercing":
        for y, width in [(-8, 2), (0, 5), (8, 2)]:
            r = reach * (1 if y == 0 else .65)
            poly([(-r,y+width), (r,y-width), (r+4,y-width*1.4), (-r*.5,y+width*1.7)], edge)
            line([(-r*.35,y+width*.45),(r,y-width)], hot, 1.8)
    elif key == "explosive":
        for i in range(9):
            a = i*2*pi/9
            r = reach * (.72 if i%2 else 1)
            poly([radial(a,8+13*t,-4),radial(a,r,-2),radial(a,r+3),
                  radial(a,12+11*t,5)], edge)
        arc(0,0,7+19*t,0,360,hot,5-3*t)
    elif key == "seeker":
        # Three points follow curved paths, converging like a swarm.
        r = 31 - 22*t
        for i in range(3):
            a = i*2*pi/3 + t
            line([radial(a-.7,r+7),radial(a-.32,r+3),radial(a,r)],edge,4.5)
            poly([radial(a,r+5,-4), radial(a,r-5), radial(a,r+3,4)],hot)
    elif key == "blackhole":
        r = 29 - 17*t
        draw.ellipse([point(-r,-r*.7),point(r,r*.7)], fill="#261531")
        for i in range(2):
            a = i*pi + t*2.3
            pts = [radial(a + j*.17, r*(.6+j*.055)) for j in range(15)]
            line(pts, edge, 7-2*t)
            line(pts[-7:], hot, 2.5)
    elif key == "balloon":
        # The membrane peels away in curved fragments after the initial inflation.
        r = 12 + 21*sin(min(t*1.55,1)*pi/2)
        for angle in [12, 100, 190, 278]:
            x,y = radial(angle*pi/180, 5*t)
            arc(x, y, r, angle+10*t, angle+78-28*t, edge, 5-2*t)
            arc(x, y, r-2, angle+6, angle+25, hot, 2)
    if frame < 2:
        r=6-3*frame
        poly([(-r,0),(0,-r),(r,0),(0,r)],"#fffbef")
    return image.resize((CELL,CELL), Image.Resampling.LANCZOS)


if __name__ == "__main__":
    sheet = Image.new("RGBA", (CELL * FRAMES, CELL * len(ROWS)))
    for row, (key, edge, hot) in enumerate(ROWS):
        for frame in range(FRAMES):
            sheet.paste(tile(key,edge,hot,frame), (frame*CELL,row*CELL))
    output = Path(__file__).resolve().parents[3] / "assets/art/vfx/textures/projectile_enchant_hits.png"
    sheet.save(output, optimize=True)
