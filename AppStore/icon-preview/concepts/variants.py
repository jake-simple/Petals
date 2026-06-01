"""5 Liquid Glass variations of Concept C.

V1 Spring Bloom — warm 7-petal, soft pink ground (refined baseline)
V2 Aurora Night — 7-petal cool jewel tones on deep navy
V3 Sunset Glow  — 7-petal warm magenta/orange/gold on peach ground
V4 Mono Crystal — single hue sapphire monochrome, high clarity
V5 Twelve Months — 12 small glass petals (1 year = 12 months metaphor)
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import (
    new_canvas, squircle_mask, radial_gradient,
    petal_polygon, rotate_translate, SS, FINAL
)
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = os.path.dirname(os.path.abspath(__file__))


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_glass_petal(canvas, cx, cy, length, width, angle, color,
                     body_alpha=160, glow_alpha=110, hl_alpha=130,
                     glow_blur_div=90, hl_blur_div=180,
                     rim_alpha=110, rim_div=350, tip_sharp=0.3):
    # outer glow
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    pts = petal_polygon(int(length * 1.06), int(width * 1.12), tip_sharp=tip_sharp)
    pts = rotate_translate(pts, angle, cx, cy)
    gd.polygon(pts, fill=color + (glow_alpha,))
    glow = glow.filter(ImageFilter.GaussianBlur(SS // glow_blur_div))
    canvas.alpha_composite(glow)

    # body
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    pts = petal_polygon(length, width, tip_sharp=tip_sharp)
    pts = rotate_translate(pts, angle, cx, cy)
    ld.polygon(pts, fill=color + (body_alpha,))
    # rim
    rim_pts = petal_polygon(int(length * 0.94), int(width * 0.85), tip_sharp=tip_sharp)
    rim_pts = rotate_translate(rim_pts, angle, cx, cy)
    ld.polygon(rim_pts, outline=(255, 255, 255, rim_alpha), width=SS // rim_div)

    # highlight
    hl = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hl_pts = petal_polygon(int(length * 0.55), int(width * 0.45), tip_sharp=tip_sharp)
    hl_pts = [(x, y - length * 0.22) for x, y in hl_pts]
    hl_pts = rotate_translate(hl_pts, angle, cx, cy)
    hd.polygon(hl_pts, fill=(255, 255, 255, hl_alpha))
    hl = hl.filter(ImageFilter.GaussianBlur(SS // hl_blur_div))
    layer = Image.alpha_composite(layer, hl)
    canvas.alpha_composite(layer)


def draw_center_orb(canvas, cx, cy, r, body=(255, 255, 255, 220),
                    highlight=(255, 255, 255, 235), blur_div=700):
    orb = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(orb)
    od.ellipse((cx - r, cy - r, cx + r, cy + r), fill=body)
    od.ellipse((cx - int(r * 0.6), cy - int(r * 0.75),
                cx + int(r * 0.1), cy - int(r * 0.15)),
               fill=highlight)
    orb = orb.filter(ImageFilter.GaussianBlur(SS // blur_div))
    canvas.alpha_composite(orb)


# ---------- V1 Spring Bloom (warm refined baseline) ----------
def V1_spring_bloom():
    canvas = new_canvas()
    canvas.alpha_composite(radial_gradient(SS, (255, 251, 250), (250, 232, 234), 0.5, 0.42, 0.95))
    cx, cy = SS // 2, SS // 2
    L = int(SS * 0.40)
    W = int(SS * 0.24)
    colors = [
        (255, 145, 175),  # pink
        (255, 175, 145),  # peach
        (255, 210, 145),  # warm yellow
        (220, 220, 150),  # chartreuse
        (195, 215, 210),  # mint mist
        (200, 185, 235),  # lavender
        (230, 160, 200),  # magenta-pink
    ]
    n = 7
    for i in range(n):
        angle = i * (360 / n) - 90
        draw_glass_petal(canvas, cx, cy, L, W, angle, colors[i],
                         body_alpha=170, hl_alpha=120)
    draw_center_orb(canvas, cx, cy, int(SS * 0.075))
    return canvas


# ---------- V2 Aurora Night ----------
def V2_aurora_night():
    canvas = new_canvas()
    # deep navy radial → midnight edge
    canvas.alpha_composite(radial_gradient(SS, (40, 50, 90), (12, 14, 32), 0.5, 0.45, 1.0))
    cx, cy = SS // 2, SS // 2
    L = int(SS * 0.40)
    W = int(SS * 0.24)
    colors = [
        (130, 220, 230),  # cyan
        (140, 200, 255),  # ice blue
        (170, 170, 255),  # periwinkle
        (210, 150, 255),  # violet
        (255, 150, 220),  # pink magenta
        (255, 180, 200),  # rose
        (180, 240, 200),  # mint aurora
    ]
    n = 7
    for i in range(n):
        angle = i * (360 / n) - 90
        # brighter glow + more saturation on dark bg
        draw_glass_petal(canvas, cx, cy, L, W, angle, colors[i],
                         body_alpha=175, glow_alpha=140, hl_alpha=150,
                         rim_alpha=170)
    draw_center_orb(canvas, cx, cy, int(SS * 0.075),
                    body=(255, 255, 255, 235),
                    highlight=(255, 255, 255, 250))
    return canvas


# ---------- V3 Sunset Glow ----------
def V3_sunset_glow():
    canvas = new_canvas()
    canvas.alpha_composite(radial_gradient(SS, (255, 235, 210), (250, 175, 145), 0.5, 0.4, 1.05))
    cx, cy = SS // 2, SS // 2
    L = int(SS * 0.40)
    W = int(SS * 0.24)
    colors = [
        (255, 105, 130),  # hot pink
        (255, 130, 100),  # coral
        (255, 165, 90),   # orange
        (255, 200, 100),  # amber
        (255, 230, 130),  # gold
        (255, 165, 165),  # warm rose
        (240, 110, 160),  # magenta
    ]
    n = 7
    for i in range(n):
        angle = i * (360 / n) - 90
        draw_glass_petal(canvas, cx, cy, L, W, angle, colors[i],
                         body_alpha=180, glow_alpha=120, hl_alpha=130)
    draw_center_orb(canvas, cx, cy, int(SS * 0.080),
                    body=(255, 250, 220, 230),
                    highlight=(255, 255, 245, 245))
    return canvas


# ---------- V4 Mono Crystal (sapphire monochrome) ----------
def V4_mono_crystal():
    canvas = new_canvas()
    canvas.alpha_composite(radial_gradient(SS, (240, 246, 255), (200, 215, 240), 0.5, 0.42, 1.0))
    cx, cy = SS // 2, SS // 2
    L = int(SS * 0.40)
    W = int(SS * 0.24)
    # single hue gradient in 7 steps from light to deep sapphire
    base_light = (130, 175, 240)
    base_deep = (45, 90, 200)
    n = 7
    for i in range(n):
        angle = i * (360 / n) - 90
        # alternate light/deep across petals for crystal-faceted feel
        t = (i % 2) * 0.6 + 0.2
        c = lerp_color(base_light, base_deep, t)
        draw_glass_petal(canvas, cx, cy, L, W, angle, c,
                         body_alpha=185, glow_alpha=110, hl_alpha=150,
                         rim_alpha=180)
    # crystalline center
    draw_center_orb(canvas, cx, cy, int(SS * 0.080),
                    body=(220, 235, 255, 235),
                    highlight=(255, 255, 255, 250))
    return canvas


# ---------- V5 Twelve Months ----------
def V5_twelve_months():
    canvas = new_canvas()
    canvas.alpha_composite(radial_gradient(SS, (252, 251, 255), (228, 232, 244), 0.5, 0.42, 0.9))
    cx, cy = SS // 2, SS // 2
    # 12 glass petals (smaller) — one per month, seasonal hue
    L = int(SS * 0.36)
    W = int(SS * 0.14)
    season_colors = [
        (140, 175, 235),  # Jan winter blue
        (180, 165, 230),  # Feb
        (215, 170, 215),  # Mar
        (240, 165, 190),  # Apr spring
        (245, 195, 170),  # May
        (250, 220, 150),  # Jun
        (250, 230, 140),  # Jul summer
        (245, 210, 135),  # Aug
        (235, 180, 130),  # Sep
        (225, 150, 130),  # Oct autumn
        (190, 145, 165),  # Nov
        (155, 160, 200),  # Dec
    ]
    for i in range(12):
        angle = i * 30 - 90
        draw_glass_petal(canvas, cx, cy, L, W, angle, season_colors[i],
                         body_alpha=175, glow_alpha=100, hl_alpha=125,
                         glow_blur_div=110, rim_alpha=130, tip_sharp=0.35)
    draw_center_orb(canvas, cx, cy, int(SS * 0.07),
                    body=(255, 252, 240, 230),
                    highlight=(255, 250, 230, 250))
    return canvas


# ---------- finalize + board ----------
def finalize(img, name):
    mask = squircle_mask(SS)
    out = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    out.paste(img, mask=mask)
    out = out.resize((FINAL, FINAL), Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    out.save(path, "PNG")
    return out


def build_board(images, labels, fname="board_variants.png"):
    cols, rows = 3, 2
    pad = 60
    cell = FINAL
    label_h = 80
    W = pad + (cell + pad) * cols
    H = pad + (cell + label_h + pad) * rows
    board = Image.new("RGB", (W, H), (28, 28, 32))
    d = ImageDraw.Draw(board)
    try:
        from PIL import ImageFont
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 36)
    except Exception:
        font = None
    for idx, (img, label) in enumerate(zip(images, labels)):
        col = idx % cols
        row = idx // cols
        x = pad + col * (cell + pad)
        y = pad + row * (cell + label_h + pad)
        board.paste(img, (x, y), img)
        if font:
            d.text((x, y + cell + 16), label, fill=(235, 235, 240), font=font)
        else:
            d.text((x, y + cell + 16), label, fill=(235, 235, 240))
    board.save(os.path.join(OUT_DIR, fname), "PNG")


if __name__ == "__main__":
    print("V1 Spring Bloom...")
    v1 = finalize(V1_spring_bloom(), "V1_spring_bloom.png")
    print("V2 Aurora Night...")
    v2 = finalize(V2_aurora_night(), "V2_aurora_night.png")
    print("V3 Sunset Glow...")
    v3 = finalize(V3_sunset_glow(), "V3_sunset_glow.png")
    print("V4 Mono Crystal...")
    v4 = finalize(V4_mono_crystal(), "V4_mono_crystal.png")
    print("V5 Twelve Months...")
    v5 = finalize(V5_twelve_months(), "V5_twelve_months.png")
    print("Board...")
    build_board(
        [v1, v2, v3, v4, v5],
        ["V1 · Spring Bloom",
         "V2 · Aurora Night",
         "V3 · Sunset Glow",
         "V4 · Mono Crystal",
         "V5 · Twelve Months"])
    print("Done.")
