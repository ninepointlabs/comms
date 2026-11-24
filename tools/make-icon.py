#!/usr/bin/env python3
"""Draw the Comms icon: a blue speech bubble (rounded box + tail) with three
white dots and a dark outline, as a 64x64 32-bit TGA with alpha (WoW reads
uncompressed TGA).

    python3 tools/make-icon.py            # writes Media/Icon.tga

No dependencies. 4x4 supersampling for smooth edges.
"""
import math
import os
import struct
import sys

SIZE = 64
SS = 4
BLUE = (79, 179, 255)
WHITE = (245, 248, 255)
DARK = (8, 14, 24)

BOX = (6.0, 9.0, 58.0, 44.0)   # x0, y0, x1, y1 (top-left origin)
RADIUS = 11.0
TAIL = ((16.0, 40.0), (30.0, 40.0), (12.0, 57.0))  # triangle
DOTS = ((20.0, 26.5), (32.0, 26.5), (44.0, 26.5))
DOT_R = 4.2
OUTLINE = 1.8


def rounded_box_dist(x, y):
    x0, y0, x1, y1 = BOX
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - RADIUS, (y1 - y0) / 2 - RADIUS
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    outside = math.hypot(max(qx, 0), max(qy, 0))
    inside = min(max(qx, qy), 0)
    return outside + inside - RADIUS


def tri_dist(x, y):
    # Negative inside; distance to the nearest edge outside.
    (ax, ay), (bx, by), (cx, cy) = TAIL
    def edge(px, py, qx, qy):
        ex, ey = qx - px, qy - py
        t = max(0.0, min(1.0, ((x - px) * ex + (y - py) * ey) / (ex * ex + ey * ey)))
        return math.hypot(x - (px + t * ex), y - (py + t * ey))
    def sign(px, py, qx, qy):
        return (qx - px) * (y - py) - (qy - py) * (x - px)
    s1, s2, s3 = sign(ax, ay, bx, by), sign(bx, by, cx, cy), sign(cx, cy, ax, ay)
    inside = (s1 >= 0 and s2 >= 0 and s3 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0)
    d = min(edge(ax, ay, bx, by), edge(bx, by, cx, cy), edge(cx, cy, ax, ay))
    return -d if inside else d


def pixel(px, py):
    acc = [0.0, 0.0, 0.0]
    cover = 0.0
    for sy in range(SS):
        for sx in range(SS):
            x = px + (sx + 0.5) / SS
            y = py + (sy + 0.5) / SS
            d = min(rounded_box_dist(x, y), tri_dist(x, y))
            if d <= 0:
                dot = min(math.hypot(x - dx, y - dy) for dx, dy in DOTS) - DOT_R
                col = WHITE if dot <= 0 else BLUE
            elif d <= OUTLINE:
                col = DARK
            else:
                continue
            cover += 1
            for i in range(3):
                acc[i] += col[i]
    if cover == 0:
        return (0, 0, 0, 0)
    rgb = tuple(int(round(acc[i] / cover)) for i in range(3))
    return rgb + (int(round(cover / (SS * SS) * 255)),)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "Media", "Icon.tga")
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    body = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixel(x, y)
            body += bytes((b, g, r, a))
    with open(out, "wb") as f:
        f.write(header + bytes(body))
    print("wrote", out)


if __name__ == "__main__":
    main()
