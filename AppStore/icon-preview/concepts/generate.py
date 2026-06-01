"""
Petals app icon concepts (4 variations).
Renders at 4096 supersample, downsamples to 1024 with LANCZOS.
Outputs: A_geometric.png, B_minimal.png, C_glass.png, D_hybrid.png, board.png
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math, os

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
SS = 4096          # supersample
FINAL = 1024
RADIUS_RATIO = 0.2237  # macOS Big Sur+ squircle approximation


# ---------- helpers ----------
def new_canvas(bg=None):
    img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    if bg is not None:
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, SS, SS), fill=bg)
    return img


def squircle_mask(size, ratio=RADIUS_RATIO):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = int(size * ratio)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    """Returns RGBA image with vertical linear gradient."""
    base = Image.new("RGBA", (size, size), top + (255,))
    top_img = Image.new("RGBA", (size, size), top + (255,))
    bot_img = Image.new("RGBA", (size, size), bottom + (255,))
    mask = Image.new("L", (size, size))
    for y in range(size):
        v = int(255 * y / (size - 1))
        for _ in range(1):
            pass
        # row fill
    # faster: build via numpy-less row paste
    grad = Image.new("L", (1, size))
    for y in range(size):
        grad.putpixel((0, y), int(255 * y / (size - 1)))
    grad = grad.resize((size, size))
    out = Image.composite(bot_img, top_img, grad)
    return out


def radial_gradient(size, inner, outer, cx=0.5, cy=0.5, r=0.7):
    """Returns RGBA radial gradient."""
    mask = Image.new("L", (size, size), 0)
    px = mask.load()
    icx, icy = cx * size, cy * size
    rr = r * size
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - icx, y - icy) / rr
            d = min(1.0, d)
            px[x, y] = int(255 * d)
    inner_img = Image.new("RGBA", (size, size), inner + (255,))
    outer_img = Image.new("RGBA", (size, size), outer + (255,))
    out = Image.composite(outer_img, inner_img, mask)
    return out


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def petal_polygon(length, width, tip_sharp=0.35, base_round=0.5, steps=80):
    """Returns list of (x,y) points for a petal pointing up from origin.
    Petal extends from y=0 (base) to y=-length (tip).
    """
    pts = []
    # right side from base to tip
    for i in range(steps + 1):
        t = i / steps
        y = -t * length
        # bezier-ish width envelope: max width around 35% from base
        env = math.sin(t * math.pi) ** 0.85
        # add tip sharpening
        if t > 0.7:
            env *= 1 - ((t - 0.7) / 0.3) ** 1.4 * tip_sharp
        w = (width / 2) * env
        pts.append((w, y))
    # left side from tip back to base
    for i in range(steps, -1, -1):
        t = i / steps
        y = -t * length
        env = math.sin(t * math.pi) ** 0.85
        if t > 0.7:
            env *= 1 - ((t - 0.7) / 0.3) ** 1.4 * tip_sharp
        w = (width / 2) * env
        pts.append((-w, y))
    return pts


def rotate_translate(pts, angle_deg, tx, ty):
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(tx + x * ca - y * sa, ty + x * sa + y * ca) for x, y in pts]


def draw_petal(canvas, cx, cy, length, width, angle, fill, sheen=True):
    """Draw a single petal with optional inner sheen."""
    pts = petal_polygon(length, width)
    pts = rotate_translate(pts, angle, cx, cy)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon(pts, fill=fill)
    if sheen:
        # add a faint highlight near tip
        hl = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hl)
        hl_pts = petal_polygon(length * 0.65, width * 0.55)
        hl_pts = [(x, y - length * 0.18) for x, y in hl_pts]
        hl_pts = rotate_translate(hl_pts, angle, cx, cy)
        hd.polygon(hl_pts, fill=(255, 255, 255, 60))
        hl = hl.filter(ImageFilter.GaussianBlur(SS // 200))
        layer = Image.alpha_composite(layer, hl)
    canvas.alpha_composite(layer)


# ---------- backgrounds ----------
def bg_warm_paper():
    g = radial_gradient(SS, (255, 252, 247), (242, 232, 218), 0.45, 0.4, 0.85)
    return g


def bg_cool_paper():
    g = radial_gradient(SS, (252, 251, 255), (228, 232, 244), 0.5, 0.42, 0.9)
    return g


def bg_off_white():
    g = radial_gradient(SS, (255, 254, 250), (240, 236, 228), 0.5, 0.45, 0.95)
    return g


def bg_soft_pink():
    g = radial_gradient(SS, (255, 250, 248), (250, 234, 232), 0.5, 0.42, 0.95)
    return g


# ---------- CONCEPT A: Geometric Constellation ----------
def concept_A():
    """12 petals at 30° intervals, seasonal hue rotation. Geometric, balanced."""
    canvas = new_canvas()
    canvas.alpha_composite(bg_warm_paper())
    cx, cy = SS // 2, SS // 2
    # 4 season anchor colors (Jan -> winter blue, Apr -> spring pink, Jul -> summer yellow, Oct -> autumn orange)
    season_colors = [
        (110, 145, 210),   # Jan winter
        (180, 150, 220),   # Feb
        (220, 160, 200),   # Mar
        (240, 150, 175),   # Apr spring pink
        (240, 180, 150),   # May
        (245, 210, 130),   # Jun
        (250, 220, 120),   # Jul summer yellow
        (240, 195, 110),   # Aug
        (230, 160, 100),   # Sep
        (215, 130, 95),    # Oct autumn
        (175, 125, 130),   # Nov
        (130, 135, 175),   # Dec
    ]
    L = int(SS * 0.36)
    W = int(SS * 0.16)

    # back layer (slightly rotated, darker)
    for i in range(12):
        angle = i * 30 + 15  # offset 15° from front
        c = season_colors[i]
        c_back = tuple(int(v * 0.85) for v in c)
        draw_petal(canvas, cx, cy, int(L * 0.88), int(W * 0.92),
                   angle, c_back + (170,), sheen=False)

    # front layer
    for i in range(12):
        angle = i * 30
        c = season_colors[i]
        draw_petal(canvas, cx, cy, L, W, angle, c + (235,), sheen=True)

    # center disc
    rd = int(SS * 0.055)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(layer)
    dd.ellipse((cx - rd, cy - rd, cx + rd, cy + rd), fill=(255, 250, 235, 255))
    # inner glow
    dd.ellipse((cx - int(rd * 0.55), cy - int(rd * 0.55),
                cx + int(rd * 0.55), cy + int(rd * 0.55)),
               fill=(255, 230, 170, 255))
    canvas.alpha_composite(layer)

    return canvas


# ---------- CONCEPT B: Single Petal Minimal ----------
def concept_B():
    """One large stylized petal, tilted, coral-to-pink. Editorial minimalism."""
    canvas = new_canvas()
    canvas.alpha_composite(bg_soft_pink())
    cx, cy = SS // 2, int(SS * 0.58)
    L = int(SS * 0.72)
    W = int(SS * 0.42)

    # base petal silhouette (deep coral)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = petal_polygon(L, W, tip_sharp=0.25)
    pts = rotate_translate(pts, -18, cx, cy)
    d.polygon(pts, fill=(232, 102, 122, 255))
    canvas.alpha_composite(layer)

    # gradient overlay (lighter at tip)
    grad = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    # multiple inset petals with lighter colors
    inset_steps = 18
    for i in range(inset_steps):
        t = i / inset_steps
        col = lerp_color((232, 102, 122), (255, 200, 195), t)
        l2 = int(L * (1 - t * 0.55))
        w2 = int(W * (1 - t * 0.55))
        pts2 = petal_polygon(l2, w2, tip_sharp=0.25)
        # shift toward tip for highlight
        pts2 = [(x, y - L * 0.06 * t) for x, y in pts2]
        pts2 = rotate_translate(pts2, -18, cx, cy)
        gd.polygon(pts2, fill=col + (int(70 * (1 - t)),))
    grad = grad.filter(ImageFilter.GaussianBlur(SS // 250))
    canvas.alpha_composite(grad)

    # subtle vein (single curved line)
    vein = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    vd = ImageDraw.Draw(vein)
    # vein along petal axis
    vein_pts = []
    for i in range(40):
        t = i / 39
        y = -t * L * 0.88
        x = 0
        vein_pts.append((x, y))
    vein_pts = rotate_translate(vein_pts, -18, cx, cy)
    vd.line(vein_pts, fill=(255, 220, 220, 110), width=SS // 280)
    canvas.alpha_composite(vein)

    return canvas


# ---------- CONCEPT C: Liquid Glass ----------
def concept_C():
    """7 translucent overlapping petals with glass highlights. macOS 26 vibe."""
    canvas = new_canvas()
    canvas.alpha_composite(bg_cool_paper())
    cx, cy = SS // 2, SS // 2
    L = int(SS * 0.40)
    W = int(SS * 0.24)

    # 7 petals, fewer than A, more arranged
    glass_colors = [
        (255, 145, 175),  # pink
        (255, 175, 130),  # peach
        (255, 215, 130),  # warm yellow
        (170, 220, 150),  # soft green
        (140, 200, 230),  # sky
        (170, 165, 230),  # lavender
        (220, 150, 210),  # magenta-pink
    ]
    n = 7
    for i in range(n):
        angle = i * (360 / n) - 90
        c = glass_colors[i]
        # outer soft glow
        glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        pts = petal_polygon(int(L * 1.06), int(W * 1.12), tip_sharp=0.3)
        pts = rotate_translate(pts, angle, cx, cy)
        gd.polygon(pts, fill=c + (90,))
        glow = glow.filter(ImageFilter.GaussianBlur(SS // 90))
        canvas.alpha_composite(glow)

        # petal body — translucent
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        pts = petal_polygon(L, W, tip_sharp=0.3)
        pts = rotate_translate(pts, angle, cx, cy)
        ld.polygon(pts, fill=c + (130,))
        # rim highlight (slightly inset, white)
        rim_pts = petal_polygon(int(L * 0.94), int(W * 0.85), tip_sharp=0.3)
        rim_pts = rotate_translate(rim_pts, angle, cx, cy)
        ld.polygon(rim_pts, outline=(255, 255, 255, 90), width=SS // 350)
        # inner highlight near tip
        hl = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hl)
        hl_pts = petal_polygon(int(L * 0.55), int(W * 0.45), tip_sharp=0.3)
        hl_pts = [(x, y - L * 0.22) for x, y in hl_pts]
        hl_pts = rotate_translate(hl_pts, angle, cx, cy)
        hd.polygon(hl_pts, fill=(255, 255, 255, 110))
        hl = hl.filter(ImageFilter.GaussianBlur(SS // 180))
        layer = Image.alpha_composite(layer, hl)
        canvas.alpha_composite(layer)

    # central glass orb
    orb = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(orb)
    rd = int(SS * 0.075)
    od.ellipse((cx - rd, cy - rd, cx + rd, cy + rd),
               fill=(255, 255, 255, 200))
    # orb highlight
    od.ellipse((cx - int(rd * 0.6), cy - int(rd * 0.75),
                cx + int(rd * 0.1), cy - int(rd * 0.15)),
               fill=(255, 255, 255, 220))
    orb_blur = orb.filter(ImageFilter.GaussianBlur(SS // 700))
    canvas.alpha_composite(orb_blur)

    return canvas


# ---------- CONCEPT D: Calendar Hybrid ----------
def concept_D():
    """5 petals around a central calendar-grid disc. Calendar + petal fusion."""
    canvas = new_canvas()
    canvas.alpha_composite(bg_off_white())
    cx, cy = SS // 2, SS // 2

    # outer petals: 12 small petals representing months around perimeter
    L = int(SS * 0.20)
    W = int(SS * 0.09)
    ring_r = int(SS * 0.30)
    season_colors = [
        (130, 160, 215),
        (175, 155, 220),
        (215, 165, 200),
        (235, 155, 180),
        (240, 185, 155),
        (245, 215, 140),
        (250, 225, 130),
        (240, 200, 115),
        (225, 165, 110),
        (215, 135, 105),
        (175, 130, 140),
        (135, 145, 185),
    ]
    for i in range(12):
        angle = i * 30 - 90
        a = math.radians(angle + 90)  # petal points outward
        # petal base position
        bx = cx + ring_r * math.cos(math.radians(angle))
        by = cy + ring_r * math.sin(math.radians(angle))
        # we want petal pointing outward from center
        out_angle = angle + 90  # default petal_polygon points "up" = -y
        # rotate so tip points away from center: outward direction is angle from center
        # petal_polygon points up (-y direction). Tip away from center means rotate so up = direction (bx-cx, by-cy)
        dir_angle_deg = math.degrees(math.atan2(by - cy, bx - cx)) + 90
        c = season_colors[i]
        draw_petal(canvas, bx, by, L, W, dir_angle_deg, c + (225,), sheen=True)

    # central white disc (calendar page)
    disc_r = int(SS * 0.22)
    disc = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    # soft shadow behind disc
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.ellipse((cx - disc_r - 30, cy - disc_r - 10,
                cx + disc_r + 30, cy + disc_r + 50),
               fill=(60, 50, 40, 80))
    sh = sh.filter(ImageFilter.GaussianBlur(SS // 80))
    canvas.alpha_composite(sh)

    dd.ellipse((cx - disc_r, cy - disc_r, cx + disc_r, cy + disc_r),
               fill=(255, 253, 248, 255))
    canvas.alpha_composite(disc)

    # calendar grid inside disc (clipped to circle via mask)
    grid_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gld = ImageDraw.Draw(grid_layer)
    rows, cols = 12, 12  # symbolic grid (not 31, would be too dense)
    gx0 = cx - int(disc_r * 0.78)
    gy0 = cy - int(disc_r * 0.78)
    gw = int(disc_r * 1.56)
    cell = gw / cols
    line_color = (200, 188, 168, 200)
    lw = SS // 600
    for r in range(rows + 1):
        y = gy0 + int(r * cell)
        gld.line([(gx0, y), (gx0 + gw, y)], fill=line_color, width=lw)
    for c in range(cols + 1):
        x = gx0 + int(c * cell)
        gld.line([(x, gy0), (x, gy0 + gw)], fill=line_color, width=lw)
    # mask grid to disc
    disc_mask = Image.new("L", canvas.size, 0)
    dmd = ImageDraw.Draw(disc_mask)
    dmd.ellipse((cx - disc_r + 6, cy - disc_r + 6,
                 cx + disc_r - 6, cy + disc_r - 6), fill=255)
    clipped = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    clipped.paste(grid_layer, mask=disc_mask)
    canvas.alpha_composite(clipped)

    # accent event bars (3 colored horizontal bars)
    bars = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(bars)
    bar_specs = [
        (3, 2, 5, (240, 130, 130, 240)),
        (6, 4, 7, (130, 195, 230, 240)),
        (8, 1, 4, (250, 200, 100, 240)),
    ]
    for row, c0, c1, color in bar_specs:
        y = gy0 + int((row + 0.25) * cell)
        x0 = gx0 + int(c0 * cell + cell * 0.15)
        x1 = gx0 + int((c1 + 1) * cell - cell * 0.15)
        h = int(cell * 0.5)
        bd.rounded_rectangle((x0, y, x1, y + h), radius=h // 2, fill=color)
    bars_clipped = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    bars_clipped.paste(bars, mask=disc_mask)
    canvas.alpha_composite(bars_clipped)

    return canvas


# ---------- apply squircle ----------
def finalize(img, name):
    mask = squircle_mask(SS)
    out = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    out.paste(img, mask=mask)
    out = out.resize((FINAL, FINAL), Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    out.save(path, "PNG")
    return out


# ---------- comparison board ----------
def build_board(images, labels):
    # 2x2 grid with labels
    pad = 60
    cell = FINAL
    label_h = 80
    W = pad + (cell + pad) * 2
    H = pad + (cell + label_h + pad) * 2
    board = Image.new("RGB", (W, H), (28, 28, 32))
    d = ImageDraw.Draw(board)
    try:
        from PIL import ImageFont
        font = ImageFont.truetype(
            "/System/Library/Fonts/SFNS.ttf", 36)
    except Exception:
        font = None
    positions = [(0, 0), (1, 0), (0, 1), (1, 1)]
    for (col, row), img, label in zip(positions, images, labels):
        x = pad + col * (cell + pad)
        y = pad + row * (cell + label_h + pad)
        board.paste(img, (x, y), img)
        if font:
            d.text((x, y + cell + 16), label, fill=(235, 235, 240), font=font)
        else:
            d.text((x, y + cell + 16), label, fill=(235, 235, 240))
    board.save(os.path.join(OUT_DIR, "board.png"), "PNG")


if __name__ == "__main__":
    print("Rendering A: Geometric Constellation...")
    a = finalize(concept_A(), "A_geometric.png")
    print("Rendering B: Single Petal Minimal...")
    b = finalize(concept_B(), "B_minimal.png")
    print("Rendering C: Liquid Glass...")
    c = finalize(concept_C(), "C_glass.png")
    print("Rendering D: Calendar Hybrid...")
    d = finalize(concept_D(), "D_hybrid.png")
    print("Building comparison board...")
    build_board(
        [a, b, c, d],
        ["A · Geometric Constellation",
         "B · Single Petal Minimal",
         "C · Liquid Glass",
         "D · Calendar Hybrid"])
    print("Done. Outputs in:", OUT_DIR)
