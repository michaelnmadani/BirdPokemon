"""Render the Down Under Bird Collector icon: a kookaburra-ish bird perched
on a branch against an outback sunset. Pure PIL shapes, supersampled."""
import sys, math
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersample canvas

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def background():
    img = Image.new("RGB", (S, S))
    top, mid, bottom = (32, 74, 92), (226, 120, 52), (246, 196, 92)
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / S
        c = lerp(top, mid, t / 0.62) if t < 0.62 else lerp(mid, bottom, (t - 0.62) / 0.38)
        d.line([(0, y), (S, y)], fill=c)
    # sun
    sun = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sun).ellipse([S*0.50, S*0.34, S*0.86, S*0.70], fill=255)
    img.paste((255, 222, 140), mask=sun.filter(ImageFilter.GaussianBlur(6)))
    # distant hills (Uluru-ish mesa)
    d.polygon([(0, S*0.80), (S*0.08, S*0.72), (S*0.30, S*0.70), (S*0.38, S*0.78), (S, S*0.80), (S, S), (0, S)],
              fill=(150, 62, 34))
    d.rectangle([0, S*0.86, S, S], fill=(110, 46, 28))
    # Southern Cross
    for (x, y, r) in [(0.18, 0.12, 22), (0.26, 0.22, 26), (0.13, 0.25, 18), (0.20, 0.33, 28), (0.235, 0.27, 12)]:
        star(d, S*x, S*y, r, (255, 248, 220))
    return img

def star(d, cx, cy, r, fill):
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + rr * math.cos(a), cy - rr * math.sin(a)))
    d.polygon(pts, fill=fill)

def bird(d, ox=0, oy=0, k=1.0, color=(24, 22, 28), eye=(250, 240, 220)):
    P = lambda x, y: (ox + x * k, oy + y * k)
    # tail
    d.polygon([P(760, 1180), P(560, 1560), P(660, 1590), P(860, 1250)], fill=color)
    # body
    d.ellipse([P(700, 860), P(1240, 1360)], fill=color)
    # head (big kookaburra head)
    d.ellipse([P(980, 600), P(1400, 1000)], fill=color)
    # beak
    d.polygon([P(1330, 760), P(1680, 850), P(1340, 900)], fill=color)
    # wing highlight cut
    # legs
    d.line([P(980, 1340), P(960, 1410)], fill=color, width=int(26 * k))
    d.line([P(1060, 1340), P(1060, 1400)], fill=color, width=int(26 * k))
    # branch (in front of the tail)
    d.line([P(560, 1430), P(1560, 1330)], fill=color, width=int(54 * k))
    d.line([P(1250, 1362), P(1420, 1240)], fill=color, width=int(30 * k))
    if eye:
        d.ellipse([P(1185, 735), P(1245, 795)], fill=eye)
        d.ellipse([P(1205, 752), P(1235, 782)], fill=color)

def icon(size):
    img = background()
    bird(ImageDraw.Draw(img))
    return img.resize((size, size), Image.LANCZOS)

def launch_logo(size):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bird(ImageDraw.Draw(img), color=(40, 92, 70, 255), eye=(234, 245, 250, 255))
    return img.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    kind, size, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    (icon if kind == "icon" else launch_logo)(size).save(out, optimize=True)
