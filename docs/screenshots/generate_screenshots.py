#!/usr/bin/env python3
"""Generate Mac App Store marketing screenshots for Petals.

Petals is a macOS app that shows an entire year on one screen, layering a
free-placement decoration canvas on top of an EventKit calendar. Since the app
is built with SwiftUI and cannot be run on this Linux host, these screenshots
are faithful mockups built from the product spec (Petals_제품구현스펙_v1.0.md),
the bundled theme palette (Theme/Themes.json) and ContentView.swift.

Output: 2880x1800 PNG (Mac App Store retina size).
"""

import datetime
import math
import os

import cairosvg

W, H = 2880, 1800
FONT = "Noto Sans CJK KR"
OUT = os.path.dirname(os.path.abspath(__file__))
YEAR = 2026
TODAY = (5, 21)  # 2026-05-21

# Calendar event colors (EventKit-style)
BLUE = "#1A73E8"
GREEN = "#34A853"
RED = "#EA4335"
PURPLE = "#9C27B0"
TEAL = "#00897B"
ORANGE = "#FB8C00"
PINK = "#E91E63"

# (month, startDay, endDay, lane, title, color)
EVENTS = [
    (1, 2, 6, 0, "신년 워크숍", BLUE),
    (1, 14, 16, 1, "디자인 리뷰", TEAL),
    (1, 22, 28, 0, "프로젝트 A", PURPLE),
    (2, 3, 9, 0, "출장 · 도쿄", RED),
    (2, 11, 13, 1, "팀 미팅", GREEN),
    (2, 18, 25, 0, "분기 마감", PURPLE),
    (3, 2, 6, 1, "스프린트 12", BLUE),
    (3, 9, 20, 0, "베타 테스트", TEAL),
    (3, 24, 31, 1, "봄 캠페인", PINK),
    (4, 1, 3, 0, "Q2 킥오프", BLUE),
    (4, 13, 17, 1, "컨퍼런스", ORANGE),
    (4, 20, 30, 0, "사용자 인터뷰", GREEN),
    (5, 4, 8, 1, "팀 오프사이트", TEAL),
    (5, 18, 29, 0, "v2.0 출시 준비", RED),
    (6, 1, 5, 0, "리테이너", BLUE),
    (6, 10, 24, 1, "여름 캠페인", ORANGE),
    (7, 6, 9, 0, "성과 리뷰", PURPLE),
    (7, 13, 22, 1, "휴가 · 제주", PINK),
    (8, 3, 19, 0, "리브랜딩", PURPLE),
    (8, 24, 28, 1, "워크숍", GREEN),
    (9, 1, 11, 0, "신학기 프로모션", TEAL),
    (9, 15, 18, 1, "디자인 시스템", BLUE),
    (10, 5, 16, 0, "v2.0 베타", BLUE),
    (10, 21, 24, 1, "보안 점검", RED),
    (11, 2, 6, 1, "연말 기획", GREEN),
    (11, 23, 30, 0, "블랙 프라이데이", RED),
    (12, 1, 5, 1, "회고", TEAL),
    (12, 14, 22, 0, "연말 결산", PURPLE),
    (12, 24, 31, 1, "겨울 휴가", PINK),
]

MONTHS_KR = ["1월", "2월", "3월", "4월", "5월", "6월",
             "7월", "8월", "9월", "10월", "11월", "12월"]


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def days_in_month(m):
    if m == 2:
        return 29 if (YEAR % 4 == 0 and (YEAR % 100 != 0 or YEAR % 400 == 0)) else 28
    return 31 if m in (1, 3, 5, 7, 8, 10, 12) else 30


def is_weekend(m, d):
    try:
        wd = datetime.date(YEAR, m, d).weekday()
        return wd >= 5
    except ValueError:
        return False


# --------------------------------------------------------------------------
# Window chrome
# --------------------------------------------------------------------------

def window(x, y, w, h, dark, title, content, zoom_sel=0):
    """A macOS window with traffic lights, title bar and a toolbar."""
    r = 22
    tb = 48          # title bar height
    tool = 92        # toolbar height
    if dark:
        bar = "#2A2C3E"
        bar2 = "#232533"
        line = "#3A3D52"
        titlecol = "#C0CAF5"
    else:
        bar = "#F2F2F4"
        bar2 = "#E9E9EC"
        line = "#D5D5DA"
        titlecol = "#56565C"

    e = []
    # drop shadow
    e.append(f'<rect x="{x}" y="{y+26}" width="{w}" height="{h}" rx="{r}" '
             f'fill="#000000" opacity="0.34" filter="url(#winshadow)"/>')
    # window body
    e.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
             f'fill="{bar2}"/>')
    # title bar
    e.append(f'<path d="M{x} {y+tb} L{x} {y+r} Q{x} {y} {x+r} {y} '
             f'L{x+w-r} {y} Q{x+w} {y} {x+w} {y+r} L{x+w} {y+tb} Z" '
             f'fill="{bar}"/>')
    # traffic lights
    for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
        e.append(f'<circle cx="{x+30+i*26}" cy="{y+tb/2}" r="8.5" fill="{c}"/>')
    e.append(f'<text x="{x+w/2}" y="{y+tb/2+6}" font-family="{FONT}" '
             f'font-size="19" font-weight="600" fill="{titlecol}" '
             f'text-anchor="middle">{esc(title)}</text>')
    # toolbar
    ty = y + tb
    e.append(f'<rect x="{x}" y="{ty}" width="{w}" height="{tool}" fill="{bar}"/>')
    e.append(f'<line x1="{x}" y1="{ty+tool}" x2="{x+w}" y2="{ty+tool}" '
             f'stroke="{line}" stroke-width="1.5"/>')
    e.append(toolbar(x, ty, w, tool, dark, zoom_sel))
    # content clip
    cy = ty + tool
    ch = h - tb - tool
    cid = f"clip{x}{y}"
    e.append(f'<clipPath id="{cid}"><path d="M{x} {cy} L{x+w} {cy} '
             f'L{x+w} {y+h-r} Q{x+w} {y+h} {x+w-r} {y+h} '
             f'L{x+r} {y+h} Q{x} {y+h} {x} {y+h-r} Z"/></clipPath>')
    e.append(f'<g clip-path="url(#{cid})">{content}</g>')
    return "".join(e), (x, cy, w, ch)


def toolbar(x, y, w, h, dark, zoom_sel=0):
    """Year nav, zoom segmented control and right-side icon buttons."""
    cy = y + h / 2
    if dark:
        fg = "#C0CAF5"
        sub = "#7B88A1"
        btn = "#363a4f"
        seg = "#1E2030"
        segsel = "#414868"
        accent = "#7AA2F7"
    else:
        fg = "#3A3A3F"
        sub = "#8A8A90"
        btn = "#FFFFFF"
        seg = "#E2E2E6"
        segsel = "#FFFFFF"
        accent = "#FF6B35"
    e = ['<g font-family="%s">' % FONT]
    # left: year navigation
    lx = x + 30
    e.append(_chev(lx + 4, cy, sub, "left"))
    e.append(f'<text x="{lx+44}" y="{cy+11}" font-size="30" font-weight="700" '
             f'fill="{fg}">{YEAR}</text>')
    e.append(_chev(lx + 132, cy, sub, "right"))
    e.append(f'<rect x="{lx+158}" y="{cy-19}" width="92" height="38" rx="9" '
             f'fill="{btn}" stroke="{seg}" stroke-width="1.5"/>')
    e.append(f'<text x="{lx+204}" y="{cy+8}" font-size="20" fill="{fg}" '
             f'text-anchor="middle">오늘</text>')
    # zoom segmented control
    sx = lx + 280
    sw = 264
    e.append(f'<rect x="{sx}" y="{cy-21}" width="{sw}" height="42" rx="10" '
             f'fill="{seg}"/>')
    labels = ["연별", "분기", "월별"]
    seln = zoom_sel
    for i, lab in enumerate(labels):
        seg_w = sw / 3
        gx = sx + i * seg_w
        if i == seln:
            e.append(f'<rect x="{gx+3}" y="{cy-18}" width="{seg_w-6}" '
                     f'height="36" rx="8" fill="{segsel}"/>')
        col = fg if i == seln else sub
        wt = "700" if i == seln else "500"
        e.append(f'<text x="{gx+seg_w/2}" y="{cy+8}" font-size="20" '
                 f'font-weight="{wt}" fill="{col}" text-anchor="middle">{lab}</text>')
    # right side icon buttons
    rx = x + w - 30
    for icon in ["canvas", "theme", "font", "filter"]:
        rx -= 56
        e.append(f'<rect x="{rx}" y="{cy-22}" width="44" height="44" rx="10" '
                 f'fill="{btn}" stroke="{seg}" stroke-width="1.5"/>')
        e.append(_icon(icon, rx + 22, cy, sub, accent))
    e.append("</g>")
    return "".join(e)


def _chev(cx, cy, col, d):
    if d == "left":
        return (f'<path d="M{cx+7} {cy-9} L{cx-2} {cy} L{cx+7} {cy+9}" '
                f'fill="none" stroke="{col}" stroke-width="3.4" '
                f'stroke-linecap="round" stroke-linejoin="round"/>')
    return (f'<path d="M{cx-2} {cy-9} L{cx+7} {cy} L{cx-2} {cy+9}" '
            f'fill="none" stroke="{col}" stroke-width="3.4" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def _icon(name, cx, cy, col, accent):
    if name == "filter":
        return (f'<g stroke="{col}" stroke-width="2.6" stroke-linecap="round">'
                f'<line x1="{cx-9}" y1="{cy-6}" x2="{cx+9}" y2="{cy-6}"/>'
                f'<line x1="{cx-6}" y1="{cy}" x2="{cx+6}" y2="{cy}"/>'
                f'<line x1="{cx-3}" y1="{cy+6}" x2="{cx+3}" y2="{cy+6}"/></g>')
    if name == "font":
        return (f'<text x="{cx}" y="{cy+8}" font-family="{FONT}" font-size="22" '
                f'font-weight="700" fill="{col}" text-anchor="middle">Aa</text>')
    if name == "theme":
        e = [f'<circle cx="{cx}" cy="{cy}" r="10" fill="none" '
             f'stroke="{col}" stroke-width="2.4"/>']
        for i, c in enumerate([accent, "#34A853", "#1A73E8"]):
            a = -math.pi / 2 + i * 2 * math.pi / 3
            e.append(f'<circle cx="{cx+5*math.cos(a):.1f}" '
                     f'cy="{cy+5*math.sin(a):.1f}" r="2.8" fill="{c}"/>')
        return "".join(e)
    # canvas / brush
    return (f'<g stroke="{accent}" stroke-width="2.6" fill="none" '
            f'stroke-linecap="round"><path d="M{cx-8} {cy+8} '
            f'L{cx+4} {cy-4}"/><path d="M{cx+2} {cy-6} L{cx+8} {cy} '
            f'L{cx+6} {cy+2}" fill="{accent}"/></g>')


# --------------------------------------------------------------------------
# Calendar grid
# --------------------------------------------------------------------------

def moodboard(cx, cy, cw, ch, dark):
    if dark:
        g = '<rect x="%d" y="%d" width="%d" height="%d" fill="#15161F"/>' % (
            cx, cy, cw, ch)
        dot = "#2A2C3E"
    else:
        g = ('<rect x="%d" y="%d" width="%d" height="%d" '
             'fill="url(#mbgrad)"/>') % (cx, cy, cw, ch)
        dot = "#DEDEE4"
    dots = []
    step = 46
    yy = cy + step
    while yy < cy + ch:
        xx = cx + step
        while xx < cx + cw:
            dots.append(f'<circle cx="{xx}" cy="{yy}" r="2.2" fill="{dot}"/>')
            xx += step
        yy += step
    return g + "".join(dots)


def year_grid(cx, cy, cw, ch, theme, events=EVENTS):
    """Full-year linear calendar: 12 month rows x 31 day columns."""
    bg = theme["backgroundColor"]
    grid = theme["gridLineColor"]
    today_c = theme["todayLineColor"]
    mlab = theme["monthLabelColor"]
    dlab = theme["dayLabelColor"]
    wknd = theme["weekendColor"]
    inactive = theme.get("inactive", grid)

    label_w = 86
    head_h = 44
    cell_w = (cw - label_w) / 31.0
    cell_h = (ch - head_h) / 12.0

    e = [f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" fill="{bg}"/>']

    gx0 = cx + label_w
    gy0 = cy + head_h

    # weekend / inactive cell fills
    for mi in range(12):
        m = mi + 1
        dim = days_in_month(m)
        ry = gy0 + mi * cell_h
        for di in range(31):
            d = di + 1
            x = gx0 + di * cell_w
            if d > dim:
                e.append(f'<rect x="{x:.1f}" y="{ry:.1f}" '
                         f'width="{cell_w:.1f}" height="{cell_h:.1f}" '
                         f'fill="{inactive}" opacity="0.5"/>')
            elif is_weekend(m, d):
                e.append(f'<rect x="{x:.1f}" y="{ry:.1f}" '
                         f'width="{cell_w:.1f}" height="{cell_h:.1f}" '
                         f'fill="{wknd}"/>')

    # day header
    for di in range(31):
        x = gx0 + di * cell_w + cell_w / 2
        e.append(f'<text x="{x:.1f}" y="{cy+28}" font-family="{FONT}" '
                 f'font-size="17" fill="{dlab}" text-anchor="middle">{di+1}</text>')

    # grid lines
    for di in range(32):
        x = gx0 + di * cell_w
        e.append(f'<line x1="{x:.1f}" y1="{gy0:.1f}" x2="{x:.1f}" '
                 f'y2="{cy+ch:.1f}" stroke="{grid}" stroke-width="1"/>')
    for mi in range(13):
        y = gy0 + mi * cell_h
        e.append(f'<line x1="{cx:.1f}" y1="{y:.1f}" x2="{cx+cw:.1f}" '
                 f'y2="{y:.1f}" stroke="{grid}" stroke-width="1"/>')

    # month labels + day numbers
    for mi in range(12):
        m = mi + 1
        ry = gy0 + mi * cell_h
        e.append(f'<text x="{cx+label_w/2:.1f}" y="{ry+cell_h/2+8:.1f}" '
                 f'font-family="{FONT}" font-size="24" font-weight="700" '
                 f'fill="{mlab}" text-anchor="middle">{MONTHS_KR[mi]}</text>')
        for di in range(days_in_month(m)):
            x = gx0 + di * cell_w
            e.append(f'<text x="{x+5:.1f}" y="{ry+19:.1f}" '
                     f'font-family="{FONT}" font-size="14" '
                     f'fill="{dlab}">{di+1}</text>')

    # today line
    tm, td = TODAY
    tx = gx0 + (td - 1) * cell_w + cell_w / 2
    e.append(f'<line x1="{tx:.1f}" y1="{gy0:.1f}" x2="{tx:.1f}" '
             f'y2="{cy+ch:.1f}" stroke="{today_c}" stroke-width="3.4"/>')
    e.append(f'<circle cx="{tx:.1f}" cy="{gy0:.1f}" r="6.5" fill="{today_c}"/>')

    # event bars
    bar_h = min(16, (cell_h - 26) / 2.6)
    for (m, sd, ed, lane, title, color) in events:
        mi = m - 1
        ry = gy0 + mi * cell_h
        bx = gx0 + (sd - 1) * cell_w
        bw = (ed - sd + 1) * cell_w
        by = ry + 24 + lane * (bar_h + 4)
        e.append(f'<rect x="{bx+1.5:.1f}" y="{by:.1f}" '
                 f'width="{bw-3:.1f}" height="{bar_h:.1f}" rx="3.5" '
                 f'fill="{color}"/>')
        cidn = f"ev{m}{sd}{lane}"
        e.append(f'<clipPath id="{cidn}"><rect x="{bx+1.5:.1f}" '
                 f'y="{by:.1f}" width="{bw-3:.1f}" height="{bar_h:.1f}"/>'
                 f'</clipPath>')
        e.append(f'<text x="{bx+8:.1f}" y="{by+bar_h-3.5:.1f}" '
                 f'font-family="{FONT}" font-size="{bar_h*0.72:.1f}" '
                 f'fill="#FFFFFF" clip-path="url(#{cidn})">{esc(title)}</text>')

    return "".join(e), (gx0, gy0, cell_w, cell_h)


def quarter_grid(cx, cy, cw, ch, theme, start_month):
    """Quarter view: 3 months, each as an 8-column day grid."""
    bg = theme["backgroundColor"]
    grid = theme["gridLineColor"]
    today_c = theme["todayLineColor"]
    mlab = theme["monthLabelColor"]
    dlab = theme["dayLabelColor"]
    wknd = theme["weekendColor"]

    e = [f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" fill="{bg}"/>']
    col_w = cw / 3.0
    dpr = 8
    rows = 4  # 31 days -> 4 rows of 8

    for qi in range(3):
        m = start_month + qi
        ox = cx + qi * col_w
        head = 70
        e.append(f'<text x="{ox+col_w/2:.1f}" y="{cy+48:.1f}" '
                 f'font-family="{FONT}" font-size="34" font-weight="700" '
                 f'fill="{mlab}" text-anchor="middle">{MONTHS_KR[m-1]}</text>')
        gx0 = ox + 34
        gy0 = cy + head
        gw = col_w - 68
        gh = ch - head - 40
        cell_w = gw / dpr
        cell_h = gh / rows
        dim = days_in_month(m)

        for di in range(31):
            d = di + 1
            r = di // dpr
            c = di % dpr
            x = gx0 + c * cell_w
            y = gy0 + r * cell_h
            if d <= dim and is_weekend(m, d):
                e.append(f'<rect x="{x:.1f}" y="{y:.1f}" '
                         f'width="{cell_w:.1f}" height="{cell_h:.1f}" '
                         f'fill="{wknd}"/>')
            if d <= dim:
                e.append(f'<text x="{x+8:.1f}" y="{y+24:.1f}" '
                         f'font-family="{FONT}" font-size="17" '
                         f'fill="{dlab}">{d}</text>')
                if (m, d) == TODAY:
                    e.append(f'<circle cx="{x+15:.1f}" cy="{y+18:.1f}" '
                             f'r="15" fill="none" stroke="{today_c}" '
                             f'stroke-width="3"/>')
        for ci in range(dpr + 1):
            x = gx0 + ci * cell_w
            e.append(f'<line x1="{x:.1f}" y1="{gy0:.1f}" x2="{x:.1f}" '
                     f'y2="{gy0+rows*cell_h:.1f}" stroke="{grid}" '
                     f'stroke-width="1"/>')
        for ri in range(rows + 1):
            y = gy0 + ri * cell_h
            e.append(f'<line x1="{gx0:.1f}" y1="{y:.1f}" '
                     f'x2="{gx0+dpr*cell_w:.1f}" y2="{y:.1f}" '
                     f'stroke="{grid}" stroke-width="1"/>')

        # event bars within this month
        bar_h = 20
        for (em, sd, ed, lane, title, color) in EVENTS:
            if em != m:
                continue
            d = sd
            while d <= ed:
                r = (d - 1) // dpr
                row_end = (r + 1) * dpr
                seg_end = min(ed, row_end)
                c0 = (d - 1) % dpr
                c1 = (seg_end - 1) % dpr
                x = gx0 + c0 * cell_w
                bw = (c1 - c0 + 1) * cell_w
                y = gy0 + r * cell_h + 30 + lane * (bar_h + 4)
                e.append(f'<rect x="{x+2:.1f}" y="{y:.1f}" '
                         f'width="{bw-4:.1f}" height="{bar_h:.1f}" rx="4" '
                         f'fill="{color}"/>')
                cidn = f"q{m}{d}{lane}"
                e.append(f'<clipPath id="{cidn}"><rect x="{x+2:.1f}" '
                         f'y="{y:.1f}" width="{bw-4:.1f}" '
                         f'height="{bar_h:.1f}"/></clipPath>')
                if d == sd:
                    e.append(f'<text x="{x+9:.1f}" y="{y+15:.1f}" '
                             f'font-family="{FONT}" font-size="14" '
                             f'fill="#FFFFFF" clip-path="url(#{cidn})">'
                             f'{esc(title)}</text>')
                d = seg_end + 1

    return "".join(e)


# --------------------------------------------------------------------------
# Canvas decoration items
# --------------------------------------------------------------------------

def photo(x, y, w, h, rot, grad_id):
    cx, cy = x + w / 2, y + h / 2
    return (f'<g transform="rotate({rot} {cx} {cy})">'
            f'<rect x="{x-9}" y="{y-9}" width="{w+18}" height="{h+18+26}" '
            f'rx="6" fill="#FFFFFF" filter="url(#itemshadow)"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" '
            f'fill="url(#{grad_id})"/></g>')


def sticker_star(cx, cy, r, col, rot=0):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * 0.42
        pts.append(f"{cx+rad*math.cos(ang):.1f},{cy+rad*math.sin(ang):.1f}")
    return (f'<polygon points="{" ".join(pts)}" fill="{col}" '
            f'transform="rotate({rot} {cx} {cy})"/>')


def sticker_flower(cx, cy, r, col, center="#FFD54F"):
    e = []
    for i in range(6):
        a = i * math.pi / 3
        e.append(f'<circle cx="{cx+r*0.62*math.cos(a):.1f}" '
                 f'cy="{cy+r*0.62*math.sin(a):.1f}" r="{r*0.46:.1f}" '
                 f'fill="{col}"/>')
    e.append(f'<circle cx="{cx}" cy="{cy}" r="{r*0.42:.1f}" fill="{center}"/>')
    return "".join(e)


def sticker_heart(cx, cy, s, col):
    return (f'<path d="M{cx} {cy+s*0.75} C{cx-s*1.3} {cy-s*0.3} '
            f'{cx-s*0.55} {cy-s*0.95} {cx} {cy-s*0.25} '
            f'C{cx+s*0.55} {cy-s*0.95} {cx+s*1.3} {cy-s*0.3} '
            f'{cx} {cy+s*0.75} Z" fill="{col}"/>')


def washi(x, y, w, h, rot, col):
    cx, cy = x + w / 2, y + h / 2
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{col}" '
            f'opacity="0.72" transform="rotate({rot} {cx} {cy})"/>')


# --------------------------------------------------------------------------
# Shared defs
# --------------------------------------------------------------------------

def defs():
    return f'''<defs>
  <filter id="winshadow" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur stdDeviation="34"/></filter>
  <filter id="itemshadow" x="-40%" y="-40%" width="180%" height="180%">
    <feGaussianBlur stdDeviation="9"/></filter>
  <linearGradient id="mbgrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FBFBFC"/>
    <stop offset="1" stop-color="#EFEFF2"/></linearGradient>
  <linearGradient id="ph1" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#FFB36B"/>
    <stop offset="1" stop-color="#FF6B6B"/></linearGradient>
  <linearGradient id="ph2" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#7AA2F7"/>
    <stop offset="1" stop-color="#9D7CF7"/></linearGradient>
  <linearGradient id="ph3" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#84E1C8"/>
    <stop offset="1" stop-color="#4AB8A0"/></linearGradient>
  <linearGradient id="ph4" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#FFD86B"/>
    <stop offset="1" stop-color="#FF9E6B"/></linearGradient>
</defs>'''


def header(text, sub, color, subcolor):
    return (f'<text x="{W/2}" y="186" font-family="{FONT}" font-size="98" '
            f'font-weight="800" fill="{color}" text-anchor="middle" '
            f'letter-spacing="-1">{esc(text)}</text>'
            f'<text x="{W/2}" y="276" font-family="{FONT}" font-size="42" '
            f'font-weight="500" fill="{subcolor}" '
            f'text-anchor="middle">{esc(sub)}</text>')


def bg(stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return (f'<defs><linearGradient id="bgg" x1="0" y1="0" x2="0.4" y2="1">'
            f'{s}</linearGradient></defs>'
            f'<rect width="{W}" height="{H}" fill="url(#bgg)"/>')


def save(name, svg):
    full = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" ' \
           f'height="{H}" viewBox="0 0 {W} {H}">{defs()}{svg}</svg>'
    svg_path = os.path.join(OUT, name + ".svg")
    png_path = os.path.join(OUT, name + ".png")
    with open(svg_path, "w") as f:
        f.write(full)
    cairosvg.svg2png(bytestring=full.encode(), write_to=png_path,
                     output_width=W, output_height=H)
    os.remove(svg_path)
    print("wrote", png_path)


# --------------------------------------------------------------------------
# Themes
# --------------------------------------------------------------------------

MINIMAL = {"backgroundColor": "#FFFFFF", "gridLineColor": "#E0E0E0",
           "todayLineColor": "#FF6B35", "monthLabelColor": "#333333",
           "dayLabelColor": "#888888", "weekendColor": "#F7F7F8",
           "inactive": "#EDEDED"}
TOKYO = {"backgroundColor": "#1A1B26", "gridLineColor": "#292E42",
         "todayLineColor": "#7AA2F7", "monthLabelColor": "#C0CAF5",
         "dayLabelColor": "#565F89", "weekendColor": "#1E1F2B",
         "inactive": "#15161F"}
CLASSIC = {"backgroundColor": "#F5F0E8", "gridLineColor": "#C8B8A0",
           "todayLineColor": "#8B4513", "monthLabelColor": "#3C2A14",
           "dayLabelColor": "#7C6A54", "weekendColor": "#EDE4D4",
           "inactive": "#E3D8C4"}
PASTEL = {"backgroundColor": "#FFF5F5", "gridLineColor": "#E8D5D5",
          "todayLineColor": "#FF8FA3", "monthLabelColor": "#8B6B6B",
          "dayLabelColor": "#A08080", "weekendColor": "#FFE3E9",
          "inactive": "#F3E3E3"}
NORD = {"backgroundColor": "#ECEFF4", "gridLineColor": "#D8DEE9",
        "todayLineColor": "#5E81AC", "monthLabelColor": "#2E3440",
        "dayLabelColor": "#4C566A", "weekendColor": "#E1E7F0",
        "inactive": "#DFE3EB"}


# --------------------------------------------------------------------------
# Screenshot 1 — Year overview
# --------------------------------------------------------------------------

def sc1():
    e = [bg([("0", "#FFEFE4"), ("1", "#FFD8C4")])]
    e.append(header("1년 전체를 한 화면에",
                    "스크롤도 줌도 없이 — 올해의 모든 일정을 한눈에",
                    "#3A2A20", "#9A6A50"))
    wx, wy, ww, wh = 300, 372, 2280, 1320
    grid, _ = year_grid(0, 0, 0, 0, MINIMAL)  # placeholder
    win, (cx, cy, cw, ch) = window(wx, wy, ww, wh, False, f"Petals — {YEAR}", "")
    # rebuild content now that we know content rect
    content = moodboard(cx, cy, cw, ch, False)
    icx, icy = cx + 70, cy + 132
    icw, ich = cw - 140, ch - 132 - 56
    g, _ = year_grid(icx, icy, icw, ich, MINIMAL)
    card = (f'<rect x="{icx-2}" y="{icy-2}" width="{icw+4}" height="{ich+4}" '
            f'rx="8" fill="#000" opacity="0.12" filter="url(#itemshadow)"/>')
    content += card + f'<g>{g}</g>'
    win, _ = window(wx, wy, ww, wh, False, f"Petals — {YEAR}", content)
    e.append(win)
    save("01-year-overview", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 2 — Canvas decoration
# --------------------------------------------------------------------------

def sc2():
    e = [bg([("0", "#F4EAFF"), ("1", "#FFE0F0")])]
    e.append(header("캘린더가 곧 무드보드",
                    "사진 · 텍스트 · 스티커 · 도형을 캘린더 위 어디든 자유롭게",
                    "#33234A", "#7A5C8E"))
    wx, wy, ww, wh = 300, 372, 2280, 1320
    win, (cx, cy, cw, ch) = window(wx, wy, ww, wh, False, f"Petals — {YEAR}", "")
    content = moodboard(cx, cy, cw, ch, False)
    icx, icy = cx + 70, cy + 132
    icw, ich = cw - 140, ch - 132 - 56
    g, _ = year_grid(icx, icy, icw, ich, MINIMAL)
    card = (f'<rect x="{icx-2}" y="{icy-2}" width="{icw+4}" height="{ich+4}" '
            f'rx="8" fill="#000" opacity="0.12" filter="url(#itemshadow)"/>')
    content += card + g

    # canvas items layered on top
    items = []
    items.append(washi(icx + 60, cy + 60, 240, 58, -8, "#FFB3C9"))
    items.append(washi(icx + icw - 360, cy + 78, 230, 54, 6, "#A9D8FF"))
    items.append(photo(icx + 120, cy + 96, 300, 220, -7, "ph4"))
    items.append(photo(icx + icw - 470, cy + 150, 330, 240, 6, "ph2"))
    items.append(photo(icx + icw - 720, icy + ich - 330, 280, 300, -4, "ph3"))
    # big goal text
    items.append(f'<text x="{icx+icw*0.30:.0f}" y="{icy+ich*0.52:.0f}" '
                 f'font-family="{FONT}" font-size="92" font-weight="800" '
                 f'fill="#FF6B6B" text-anchor="middle" '
                 f'transform="rotate(-5 {icx+icw*0.30:.0f} {icy+ich*0.52:.0f})">'
                 f'2026 GOALS</text>')
    items.append(f'<text x="{icx+icw*0.62:.0f}" y="{icy+ich*0.30:.0f}" '
                 f'font-family="{FONT}" font-size="44" font-weight="700" '
                 f'fill="#6A4FB0" transform="rotate(4 {icx+icw*0.62:.0f} '
                 f'{icy+ich*0.30:.0f})">꿈을 현실로 ✶</text>')
    # stickers
    items.append(sticker_flower(icx + 90, icy + ich * 0.42, 52, "#FF9EC4"))
    items.append(sticker_star(icx + icw - 140, icy + 90, 46, "#FFC93C", 12))
    items.append(sticker_heart(icx + icw * 0.50, icy + ich - 150, 40, "#FF6B8A"))
    items.append(sticker_flower(icx + icw - 220, icy + ich - 120, 44,
                                "#9D7CF7", "#FFE0A0"))
    # highlight ring over a date range with selection handles
    rx, ry, rw, rh = icx + icw * 0.40, icy + ich * 0.66, 300, 120
    items.append(f'<rect x="{rx:.0f}" y="{ry:.0f}" width="{rw}" height="{rh}" '
                 f'rx="60" fill="none" stroke="#FF6B35" stroke-width="6"/>')
    for hx, hy in [(rx, ry), (rx + rw, ry), (rx, ry + rh), (rx + rw, ry + rh)]:
        items.append(f'<circle cx="{hx:.0f}" cy="{hy:.0f}" r="9" '
                     f'fill="#FFFFFF" stroke="#2B7FFF" stroke-width="3.5"/>')

    content += "".join(items)
    win, _ = window(wx, wy, ww, wh, False, f"Petals — {YEAR}", content)
    e.append(win)
    save("02-canvas-moodboard", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 3 — Themes
# --------------------------------------------------------------------------

def sc3():
    e = [bg([("0", "#1B1D2E"), ("1", "#10111C")])]
    e.append(header("9가지 테마, 당신의 분위기대로",
                    "라이트 · 다크 · 파스텔 · 클래식까지 — 한 번의 탭으로",
                    "#E6EAFF", "#8A93C8"))
    wx, wy, ww, wh = 300, 348, 2280, 1190
    win, (cx, cy, cw, ch) = window(wx, wy, ww, wh, True, f"Petals — {YEAR}", "")
    content = moodboard(cx, cy, cw, ch, True)
    icx, icy = cx + 70, cy + 36
    icw, ich = cw - 140, ch - 36 - 50
    g, _ = year_grid(icx, icy, icw, ich, TOKYO)
    content += g
    win, _ = window(wx, wy, ww, wh, True, f"Petals — {YEAR}", content)
    e.append(win)

    # theme swatch strip
    swatches = [
        ("Minimal", "#FFFFFF", "#FF6B35", "#E0E0E0"),
        ("Pastel", "#FFF5F5", "#FF8FA3", "#E8D5D5"),
        ("Classic", "#F5F0E8", "#8B4513", "#C8B8A0"),
        ("Nord", "#ECEFF4", "#5E81AC", "#D8DEE9"),
        ("Tokyo Night", "#1A1B26", "#7AA2F7", "#292E42"),
        ("Dracula", "#282A36", "#FF79C6", "#44475A"),
        ("Midnight", "#1A1A2E", "#00D4FF", "#2A2A4A"),
        ("Solarized", "#FDF6E3", "#CB4B16", "#EEE8D5"),
    ]
    n = len(swatches)
    sw = 230
    gap = 30
    total = n * sw + (n - 1) * gap
    sx = (W - total) / 2
    sy = wy + wh + 56
    sel = 4
    for i, (nm, b, ac, gl) in enumerate(swatches):
        x = sx + i * (sw + gap)
        ring = ""
        if i == sel:
            ring = (f'<rect x="{x-7}" y="{sy-7}" width="{sw+14}" '
                    f'height="{154}" rx="22" fill="none" stroke="#7AA2F7" '
                    f'stroke-width="5"/>')
        e.append(ring)
        e.append(f'<rect x="{x}" y="{sy}" width="{sw}" height="100" rx="16" '
                 f'fill="{b}" stroke="{gl}" stroke-width="2"/>')
        for r in range(3):
            e.append(f'<line x1="{x+22}" y1="{sy+30+r*22}" '
                     f'x2="{x+sw-22}" y2="{sy+30+r*22}" stroke="{gl}" '
                     f'stroke-width="3"/>')
        e.append(f'<rect x="{x+sw*0.5}" y="{sy+16}" width="5" height="68" '
                 f'fill="{ac}"/>')
        e.append(f'<text x="{x+sw/2}" y="{sy+138}" font-family="{FONT}" '
                 f'font-size="28" font-weight="600" fill="#C0CAF5" '
                 f'text-anchor="middle">{esc(nm)}</text>')
    save("03-themes", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 4 — Zoom levels
# --------------------------------------------------------------------------

def sc4():
    e = [bg([("0", "#E2F6EF"), ("1", "#C4E9DD")])]
    e.append(header("연 · 분기 · 월, 원하는 만큼",
                    "줌 레벨을 바꿔 더 깊게 들여다보세요",
                    "#1E3A32", "#4F7A6C"))
    wx, wy, ww, wh = 300, 372, 2280, 1320
    win, (cx, cy, cw, ch) = window(wx, wy, ww, wh, False, f"Petals — {YEAR} · 2분기", "", 1)
    content = moodboard(cx, cy, cw, ch, False)
    icx, icy = cx + 70, cy + 60
    icw, ich = cw - 140, ch - 60 - 56
    card = (f'<rect x="{icx-2}" y="{icy-2}" width="{icw+4}" height="{ich+4}" '
            f'rx="8" fill="#000" opacity="0.12" filter="url(#itemshadow)"/>')
    g = quarter_grid(icx, icy, icw, ich, NORD, 4)
    content += card + g
    win, _ = window(wx, wy, ww, wh, False, f"Petals — {YEAR} · 2분기", content, 1)
    e.append(win)
    save("04-zoom-levels", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 5 — Native Mac
# --------------------------------------------------------------------------

def sc5():
    e = [bg([("0", "#F3ECDC"), ("1", "#E3D6BC")])]
    e.append(header("Mac을 위해 만들어졌습니다",
                    "EventKit 연동 · iCloud 동기화 · 네이티브 SwiftUI",
                    "#3C2A14", "#8A6E44"))
    wx, wy, ww, wh = 300, 348, 2280, 1150
    win, (cx, cy, cw, ch) = window(wx, wy, ww, wh, False, f"Petals — {YEAR}", "")
    content = moodboard(cx, cy, cw, ch, False)
    icx, icy = cx + 60, cy + 32
    icw, ich = cw - 120, ch - 32 - 44
    g, _ = year_grid(icx, icy, icw, ich, CLASSIC)
    content += g
    win, _ = window(wx, wy, ww, wh, False, f"Petals — {YEAR}", content)
    e.append(win)

    feats = [
        ("calendar", "캘린더 연동",
         "iCloud · Google · Exchange 모든 캘린더를 그대로"),
        ("cloud", "iCloud 동기화",
         "모든 Mac에서 꾸민 캘린더가 자동으로"),
        ("bolt", "네이티브 속도",
         "SwiftUI · SwiftData로 1초 안에 1년 렌더링"),
    ]
    n = 3
    cw2 = 700
    gap = 40
    total = n * cw2 + (n - 1) * gap
    fx = (W - total) / 2
    fy = wy + wh + 52
    accent = "#8B4513"
    for i, (icon, t, d) in enumerate(feats):
        x = fx + i * (cw2 + gap)
        e.append(f'<rect x="{x}" y="{fy}" width="{cw2}" height="170" rx="24" '
                 f'fill="#FFFFFF" opacity="0.66"/>')
        cxx, cyy = x + 78, fy + 85
        e.append(f'<circle cx="{cxx}" cy="{cyy}" r="44" '
                 f'fill="{accent}" opacity="0.14"/>')
        e.append(_bigicon(icon, cxx, cyy, accent))
        e.append(f'<text x="{x+152}" y="{fy+72}" font-family="{FONT}" '
                 f'font-size="36" font-weight="700" fill="#3C2A14">'
                 f'{esc(t)}</text>')
        e.append(f'<text x="{x+152}" y="{fy+116}" font-family="{FONT}" '
                 f'font-size="25" fill="#7A5E3A">{esc(d)}</text>')
    save("05-native-mac", "".join(e))


def _bigicon(name, cx, cy, col):
    if name == "calendar":
        return (f'<g fill="none" stroke="{col}" stroke-width="3.6" '
                f'stroke-linejoin="round"><rect x="{cx-22}" y="{cy-18}" '
                f'width="44" height="40" rx="6"/>'
                f'<line x1="{cx-22}" y1="{cy-5}" x2="{cx+22}" y2="{cy-5}"/>'
                f'<line x1="{cx-12}" y1="{cy-26}" x2="{cx-12}" y2="{cy-12}" '
                f'stroke-linecap="round"/>'
                f'<line x1="{cx+12}" y1="{cy-26}" x2="{cx+12}" y2="{cy-12}" '
                f'stroke-linecap="round"/></g>')
    if name == "cloud":
        return (f'<path d="M{cx-26} {cy+12} a16 16 0 0 1 4 -31 '
                f'a20 20 0 0 1 38 4 a14 14 0 0 1 2 27 Z" '
                f'fill="none" stroke="{col}" stroke-width="3.6" '
                f'stroke-linejoin="round"/>')
    # bolt
    return (f'<path d="M{cx+4} {cy-24} L{cx-16} {cy+4} L{cx-2} {cy+4} '
            f'L{cx-6} {cy+24} L{cx+16} {cy-6} L{cx+2} {cy-6} Z" '
            f'fill="{col}"/>')


if __name__ == "__main__":
    sc1()
    sc2()
    sc3()
    sc4()
    sc5()
    print("done")
