#!/usr/bin/env python3
"""Generate Mac App Store marketing screenshots for Petals.

Petals is a macOS app that shows an entire year on one screen, layering a
free-placement decoration canvas on top of an EventKit calendar, plus a
separate infinite-canvas whiteboard (vision board). The app is SwiftUI and
cannot be run on this Linux host, so these screenshots are faithful mockups
rebuilt directly from the real layout code:

  CalendarGridView.swift / CalendarLayout.swift  — grid geometry
  EventBarLayer.swift                            — event bars
  MoodBoardBackground.swift                      — calendar dot background
  VisionBoardView.swift / InfiniteCanvasBackground.swift — whiteboard
  Themes.json, AppSettings.swift                 — palette & defaults

Output: 2880x1800 PNG (Mac App Store retina size).
"""

import datetime
import math
import os
import base64

import cairosvg

W, H = 2880, 1800
FONT = "Noto Sans CJK KR"
OUT = os.path.dirname(os.path.abspath(__file__))
YEAR = 2026
TODAY = (5, 21)  # 2026-05-21

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
# veryShortStandaloneWeekdaySymbols (en), indexed by Apple weekday-1 (Sun=0)
WEEKDAYS = ["S", "M", "T", "W", "T", "F", "S"]

# EventKit-style calendar colors
BLUE, GREEN, RED = "#1A73E8", "#34A853", "#EA4335"
PURPLE, TEAL, ORANGE, PINK = "#9C27B0", "#00897B", "#FB8C00", "#E91E63"

# (month, startDay, endDay, lane, title, color)
EVENTS = [
    (1, 2, 6, 0, "New Year Workshop", BLUE),
    (1, 14, 16, 1, "Design Review", TEAL),
    (1, 22, 28, 0, "Project A", PURPLE),
    (2, 3, 9, 0, "Trip · Tokyo", RED),
    (2, 11, 13, 1, "Team Sync", GREEN),
    (2, 18, 25, 0, "Quarter Close", PURPLE),
    (3, 2, 6, 1, "Sprint 12", BLUE),
    (3, 9, 20, 0, "Beta Testing", TEAL),
    (3, 24, 31, 1, "Spring Campaign", PINK),
    (4, 1, 9, 0, "Q2 Kickoff", BLUE),
    (4, 13, 17, 1, "Conference", ORANGE),
    (4, 20, 30, 0, "User Interviews", GREEN),
    (5, 4, 12, 1, "Team Offsite", TEAL),
    (5, 18, 29, 0, "v2.0 Launch Prep", RED),
    (6, 1, 9, 0, "Retainer", BLUE),
    (6, 12, 26, 1, "Summer Campaign", ORANGE),
    (7, 6, 9, 0, "Performance Review", PURPLE),
    (7, 13, 22, 1, "Vacation · Jeju", PINK),
    (8, 3, 19, 0, "Rebranding", PURPLE),
    (8, 24, 28, 1, "Workshop", GREEN),
    (9, 1, 11, 0, "Back-to-School", TEAL),
    (9, 15, 18, 1, "Design System", BLUE),
    (10, 5, 16, 0, "v2.0 Beta", BLUE),
    (10, 21, 24, 1, "Security Audit", RED),
    (11, 2, 6, 1, "Year-End Planning", GREEN),
    (11, 23, 30, 0, "Black Friday", RED),
    (12, 1, 5, 1, "Retrospective", TEAL),
    (12, 14, 22, 0, "Year-End Review", PURPLE),
    (12, 24, 31, 1, "Winter Holiday", PINK),
]

EVENT_FONT = 17.0      # mirrors AppSettings.eventFontSizeDefault (scaled)
DAY_FONT = 15.0
_uid = [0]


def uid():
    _uid[0] += 1
    return f"u{_uid[0]}"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def days_in_month(m):
    if m == 2:
        leap = YEAR % 4 == 0 and (YEAR % 100 != 0 or YEAR % 400 == 0)
        return 29 if leap else 28
    return 31 if m in (1, 3, 5, 7, 8, 10, 12) else 30


def weekday(m, d):
    """Apple weekday: 1=Sun .. 7=Sat."""
    return datetime.date(YEAR, m, d).isoweekday() % 7 + 1


# --------------------------------------------------------------------------
# Window chrome (macOS)
# --------------------------------------------------------------------------

def window(x, y, w, h, dark, title, content, toolbar_svg, sidebar=None):
    """A macOS window: traffic lights, unified title bar + toolbar, content.

    Returns (svg, content_rect). When `sidebar` is given it is a tuple
    (width, svg) drawn full-height on the left (NavigationSplitView style).
    """
    r = 22
    tb = 54           # title bar height
    tool = 92         # toolbar strip height
    if dark:
        bar, body = "#2C2E40", "#222433"
        line, titlecol = "#3C3F55", "#C0CAF5"
        sbbg = "#26283A"
    else:
        bar, body = "#ECECEE", "#E7E7EA"
        line, titlecol = "#D2D2D7", "#5A5A60"
        sbbg = "#F4F4F6"

    e = []
    e.append(f'<rect x="{x}" y="{y+26}" width="{w}" height="{h}" rx="{r}" '
             f'fill="#000" opacity="0.34" filter="url(#winshadow)"/>')
    e.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
             f'fill="{body}"/>')

    cy = y + tb + tool
    ch = h - tb - tool
    sbw = sidebar[0] if sidebar else 0

    # sidebar panel (full height under the rounded corners)
    if sidebar:
        sid = uid()
        e.append(f'<clipPath id="{sid}"><path d="M{x+r} {y} L{x+sbw} {y} '
                 f'L{x+sbw} {y+h} L{x+r} {y+h} Q{x} {y+h} {x} {y+h-r} '
                 f'L{x} {y+r} Q{x} {y} {x+r} {y} Z"/></clipPath>')
        e.append(f'<g clip-path="url(#{sid})">'
                 f'<rect x="{x}" y="{y}" width="{sbw}" height="{h}" '
                 f'fill="{sbbg}"/>{sidebar[1]}</g>')
        e.append(f'<line x1="{x+sbw}" y1="{y+tb}" x2="{x+sbw}" y2="{y+h}" '
                 f'stroke="{line}" stroke-width="1.5"/>')

    # title bar
    e.append(f'<path d="M{x} {y+tb} L{x} {y+r} Q{x} {y} {x+r} {y} '
             f'L{x+w-r} {y} Q{x+w} {y} {x+w} {y+r} L{x+w} {y+tb} Z" '
             f'fill="{bar}"/>')
    for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
        e.append(f'<circle cx="{x+32+i*27}" cy="{y+tb/2}" r="9" fill="{c}"/>')
    e.append(f'<text x="{x+w/2}" y="{y+tb/2+7}" font-family="{FONT}" '
             f'font-size="20" font-weight="600" fill="{titlecol}" '
             f'text-anchor="middle">{esc(title)}</text>')

    # toolbar strip
    ty = y + tb
    e.append(f'<rect x="{x+sbw}" y="{ty}" width="{w-sbw}" height="{tool}" '
             f'fill="{bar}"/>')
    e.append(f'<line x1="{x+sbw}" y1="{ty+tool}" x2="{x+w}" y2="{ty+tool}" '
             f'stroke="{line}" stroke-width="1.5"/>')
    e.append(toolbar_svg)

    # content (clipped to rounded bottom)
    cid = uid()
    e.append(f'<clipPath id="{cid}"><path d="M{x+sbw} {cy} L{x+w} {cy} '
             f'L{x+w} {y+h-r} Q{x+w} {y+h} {x+w-r} {y+h} '
             f'L{x+sbw+r} {y+h} Q{x+sbw} {y+h} {x+sbw} {y+h-r} Z"/></clipPath>')
    e.append(f'<g clip-path="url(#{cid})">{content}</g>')
    return "".join(e), (x + sbw, cy, w - sbw, ch)


def _btn(x, y, w, h, dark):
    fill = "#3A3D52" if dark else "#FFFFFF"
    stroke = "#4A4D63" if dark else "#D7D7DC"
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>')


def _chev(cx, cy, col, d, sw=3.4):
    if d == "left":
        return (f'<path d="M{cx+7} {cy-9} L{cx-2} {cy} L{cx+7} {cy+9}" '
                f'fill="none" stroke="{col}" stroke-width="{sw}" '
                f'stroke-linecap="round" stroke-linejoin="round"/>')
    return (f'<path d="M{cx-2} {cy-9} L{cx+7} {cy} L{cx-2} {cy+9}" '
            f'fill="none" stroke="{col}" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def _icon(name, cx, cy, col, accent):
    if name == "mode":  # sparkles.rectangle.stack
        return (f'<g fill="none" stroke="{col}" stroke-width="2.4">'
                f'<rect x="{cx-11}" y="{cy-4}" width="20" height="14" rx="3"/>'
                f'<path d="M{cx-7} {cy-4} v-4 h20 v14 h-4" />'
                f'<path d="M{cx+6} {cy-9} l1.4 3 3 1.4 -3 1.4 -1.4 3 '
                f'-1.4 -3 -3 -1.4 3 -1.4 Z" fill="{accent}" stroke="none"/>'
                f'</g>')
    if name == "filter":  # line.3.horizontal.decrease.circle
        return (f'<g stroke="{col}" stroke-width="2.6" stroke-linecap="round">'
                f'<line x1="{cx-9}" y1="{cy-6}" x2="{cx+9}" y2="{cy-6}"/>'
                f'<line x1="{cx-6}" y1="{cy}" x2="{cx+6}" y2="{cy}"/>'
                f'<line x1="{cx-3}" y1="{cy+6}" x2="{cx+3}" y2="{cy+6}"/></g>')
    if name == "font":  # textformat.size
        return (f'<text x="{cx}" y="{cy+8}" font-family="{FONT}" '
                f'font-size="22" font-weight="700" fill="{col}" '
                f'text-anchor="middle">Aa</text>')
    if name == "theme":  # paintpalette
        e = [f'<circle cx="{cx}" cy="{cy}" r="10" fill="none" '
             f'stroke="{col}" stroke-width="2.4"/>']
        for i, c in enumerate([accent, "#34A853", "#1A73E8"]):
            a = -math.pi / 2 + i * 2 * math.pi / 3
            e.append(f'<circle cx="{cx+5*math.cos(a):.1f}" '
                     f'cy="{cy+5*math.sin(a):.1f}" r="2.8" fill="{c}"/>')
        return "".join(e)
    if name == "brush":  # paintbrush
        return (f'<g stroke="{accent}" stroke-width="2.6" fill="none" '
                f'stroke-linecap="round"><path d="M{cx-8} {cy+8} '
                f'L{cx+3} {cy-3}"/><path d="M{cx+1} {cy-5} L{cx+8} {cy+2} '
                f'L{cx+5} {cy+5} Z" fill="{accent}"/></g>')
    if name == "photo":
        return (f'<g fill="none" stroke="{col}" stroke-width="2.4">'
                f'<rect x="{cx-11}" y="{cy-9}" width="22" height="18" rx="3"/>'
                f'<circle cx="{cx-4}" cy="{cy-3}" r="2.6" fill="{col}"/>'
                f'<path d="M{cx-11} {cy+6} L{cx-2} {cy-2} L{cx+4} {cy+3} '
                f'L{cx+8} {cy-1} L{cx+11} {cy+2}"/></g>')
    if name == "text":
        return (f'<text x="{cx}" y="{cy+9}" font-family="{FONT}" '
                f'font-size="26" font-weight="700" fill="{col}" '
                f'text-anchor="middle">T</text>')
    if name == "sticker":  # star.square.on.square
        return (f'<g fill="none" stroke="{col}" stroke-width="2.2">'
                f'<rect x="{cx-10}" y="{cy-6}" width="18" height="18" rx="3"/>'
                f'<path d="M{cx-6} {cy-10} h16 v16" />'
                f'<path d="M{cx-2} {cy+1} l1.6 3.3 3.6 0.5 -2.6 2.6 0.6 3.6 '
                f'-3.2 -1.7 -3.2 1.7 0.6 -3.6 -2.6 -2.6 3.6 -0.5 Z" '
                f'fill="{accent}" stroke="none"/></g>')
    if name == "reset":
        return (f'<path d="M{cx+9} {cy-2} A9 9 0 1 0 {cx+9} {cy+3}" '
                f'fill="none" stroke="{col}" stroke-width="2.6" '
                f'stroke-linecap="round"/>'
                f'<path d="M{cx+9} {cy-9} L{cx+9} {cy-1} L{cx+2} {cy-2} Z" '
                f'fill="{col}"/>')
    if name == "calendar":
        return (f'<g fill="none" stroke="{col}" stroke-width="2.4">'
                f'<rect x="{cx-11}" y="{cy-9}" width="22" height="20" rx="3"/>'
                f'<line x1="{cx-11}" y1="{cy-3}" x2="{cx+11}" y2="{cy-3}"/>'
                f'</g>')
    if name in ("plus", "minus"):
        e = [f'<line x1="{cx-8}" y1="{cy}" x2="{cx+8}" y2="{cy}" '
             f'stroke="{col}" stroke-width="2.8" stroke-linecap="round"/>']
        if name == "plus":
            e.append(f'<line x1="{cx}" y1="{cy-8}" x2="{cx}" y2="{cy+8}" '
                     f'stroke="{col}" stroke-width="2.8" '
                     f'stroke-linecap="round"/>')
        return "".join(e)
    if name == "front":
        return (f'<g fill="none" stroke="{col}" stroke-width="2.2">'
                f'<rect x="{cx-10}" y="{cy-10}" width="13" height="13"/>'
                f'<rect x="{cx-3}" y="{cy-3}" width="13" height="13" '
                f'fill="{accent}" stroke="{accent}"/></g>')
    if name == "inspect":
        return (f'<g stroke="{col}" stroke-width="2.4" stroke-linecap="round">'
                f'<line x1="{cx-10}" y1="{cy-6}" x2="{cx+10}" y2="{cy-6}"/>'
                f'<line x1="{cx-10}" y1="{cy}" x2="{cx+10}" y2="{cy}"/>'
                f'<line x1="{cx-10}" y1="{cy+6}" x2="{cx+10}" y2="{cy+6}"/>'
                f'<circle cx="{cx-3}" cy="{cy-6}" r="3" fill="#FFF"/>'
                f'<circle cx="{cx+4}" cy="{cy}" r="3" fill="#FFF"/>'
                f'<circle cx="{cx-1}" cy="{cy+6}" r="3" fill="#FFF"/></g>')
    return ""


def toolbar_calendar(x, y, w, h, dark, zoom_sel=0, page_label=None):
    """Calendar-mode toolbar: mode toggle, year nav, zoom, right icons."""
    cy = y + h / 2
    if dark:
        fg, sub = "#C0CAF5", "#7B88A1"
        seg, segsel, accent = "#1E2030", "#414868", "#7AA2F7"
    else:
        fg, sub = "#3A3A3F", "#86868B"
        seg, segsel, accent = "#E2E2E6", "#FFFFFF", "#FF6B35"
    e = [f'<g font-family="{FONT}">']

    # mode toggle (far left)
    mx = x + 26
    e.append(_btn(mx, cy - 22, 44, 44, dark))
    e.append(_icon("mode", mx + 22, cy, sub, accent))

    # year navigation
    lx = mx + 70
    e.append(_chev(lx + 6, cy, sub, "left"))
    e.append(f'<text x="{lx+46}" y="{cy+11}" font-size="30" '
             f'font-weight="700" fill="{fg}">{YEAR}</text>')
    e.append(_chev(lx + 134, cy, sub, "right"))
    e.append(_btn(lx + 160, cy - 19, 96, 38, dark))
    e.append(f'<text x="{lx+208}" y="{cy+8}" font-size="20" fill="{fg}" '
             f'text-anchor="middle">Today</text>')

    # divider
    e.append(f'<line x1="{lx+274}" y1="{cy-16}" x2="{lx+274}" y2="{cy+16}" '
             f'stroke="{sub}" stroke-width="1.5" opacity="0.5"/>')

    # zoom segmented control
    sx, sw = lx + 300, 330
    e.append(f'<rect x="{sx}" y="{cy-21}" width="{sw}" height="42" rx="10" '
             f'fill="{seg}"/>')
    for i, lab in enumerate(["Year", "Quarter", "Month"]):
        gw = sw / 3
        gx = sx + i * gw
        if i == zoom_sel:
            e.append(f'<rect x="{gx+3}" y="{cy-18}" width="{gw-6}" '
                     f'height="36" rx="8" fill="{segsel}"/>')
        col = fg if i == zoom_sel else sub
        wt = "700" if i == zoom_sel else "500"
        e.append(f'<text x="{gx+gw/2}" y="{cy+8}" font-size="20" '
                 f'font-weight="{wt}" fill="{col}" '
                 f'text-anchor="middle">{lab}</text>')

    # page navigation (visible when not year view)
    if page_label:
        px = sx + sw + 24
        e.append(_chev(px + 6, cy, sub, "left"))
        e.append(f'<text x="{px+58}" y="{cy+9}" font-size="22" '
                 f'font-weight="700" fill="{fg}" text-anchor="middle">'
                 f'{esc(page_label)}</text>')
        e.append(_chev(px + 110, cy, sub, "right"))

    # right-side icon buttons
    rx = x + w - 26
    for ic in ["brush", "theme", "font", "filter"]:
        rx -= 56
        e.append(_btn(rx, cy - 22, 44, 44, dark))
        e.append(_icon(ic, rx + 22, cy, sub, accent))
    e.append("</g>")
    return "".join(e)


def toolbar_whiteboard(x, y, w, h, dark, zoom="100%"):
    """Whiteboard-mode toolbar: mode toggle + zoom, center tools, selection."""
    cy = y + h / 2
    fg, sub, accent = "#3A3A3F", "#86868B", "#FF6B35"
    e = [f'<g font-family="{FONT}">']

    # mode toggle + zoom controls (left)
    mx = x + 26
    e.append(_btn(mx, cy - 22, 44, 44, dark))
    e.append(_icon("mode", mx + 22, cy, sub, accent))

    zx = mx + 64
    e.append(_btn(zx, cy - 19, 38, 38, dark))
    e.append(_icon("minus", zx + 19, cy, sub, accent))
    e.append(f'<text x="{zx+78}" y="{cy+8}" font-size="20" font-weight="600" '
             f'fill="{fg}" text-anchor="middle">{zoom}</text>')
    e.append(_btn(zx + 118, cy - 19, 38, 38, dark))
    e.append(_icon("plus", zx + 137, cy, sub, accent))
    e.append(_btn(zx + 164, cy - 19, 38, 38, dark))
    e.append(_icon("reset", zx + 183, cy, sub, accent))

    # center tools
    tools = ["photo", "text", "sticker"]
    tw = 50
    cxs = x + w / 2 - (len(tools) * tw) / 2
    for i, ic in enumerate(tools):
        bx = cxs + i * tw
        e.append(_btn(bx, cy - 22, 44, 44, dark))
        e.append(_icon(ic, bx + 22, cy, sub, accent))

    # selection tools (right, shown because an item is selected)
    rx = x + w - 26
    for ic in ["front", "inspect"]:
        rx -= 56
        e.append(_btn(rx, cy - 22, 44, 44, dark))
        e.append(_icon(ic, rx + 22, cy, sub, accent))
    e.append("</g>")
    return "".join(e)


# --------------------------------------------------------------------------
# Calendar grid — faithful to CalendarGridView / CalendarLayout
# --------------------------------------------------------------------------

def moodboard(x, y, w, h, grid_hex, dark):
    base = "#15161F" if dark else "url(#mbgrad)"
    e = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{base}"/>']
    step = 30
    dots = []
    yy = y + step
    while yy < y + h:
        xx = x + step
        while xx < x + w:
            dots.append(f'<circle cx="{xx:.0f}" cy="{yy:.0f}" r="2.1"/>')
            xx += step
        yy += step
    e.append(f'<g fill="{grid_hex}" opacity="0.4">{"".join(dots)}</g>')
    return "".join(e)


def cal_grid(x, y, w, h, theme, months_shown, start_month,
             events=EVENTS, show_today=True):
    """Render the calendar grid exactly like CalendarGridView.

    Year view: 12 rows x 31 cols (1 row/month).
    Quarter/Month view: 8 cols, 4 subrows/month, months stacked.
    """
    bg = theme["backgroundColor"]
    grid = theme["gridLineColor"]
    today_c = theme["todayLineColor"]
    mlab = theme["monthLabelColor"]
    dlab = theme["dayLabelColor"]
    wknd = theme.get("weekendColor")

    days_per_row = 8 if months_shown in (1, 3) else 31
    rows_per_month = 4 if months_shown in (1, 3) else 1
    total_rows = months_shown * rows_per_month

    month_label_w = w * 0.034
    row_h = h / total_rows
    label_band = row_h * 0.28
    cell_h = row_h - label_band
    cell_w = (w - month_label_w) / days_per_row

    bar_h = EVENT_FONT + 6
    vis_rows = max(1, min(int(cell_h / bar_h), 7))

    e = [f'<g transform="translate({x} {y})">']
    e.append(f'<rect width="{w}" height="{h}" fill="{bg}"/>')

    end_month = start_month + months_shown - 1

    # ---- per-cell fills, day labels, month labels --------------------------
    for month in range(start_month, end_month + 1):
        days = days_in_month(month)
        moff = month - start_month
        for subrow in range(rows_per_month):
            vrow = moff * rows_per_month + subrow
            row_y = vrow * row_h
            event_y = row_y + label_band
            first_day = subrow * days_per_row + 1
            last_day = min((subrow + 1) * days_per_row, 31)

            for day in range(first_day, last_day + 1):
                col = day - first_day
                cx0 = month_label_w + col * cell_w
                # cell fill
                if day > days:
                    e.append(f'<rect x="{cx0:.1f}" y="{event_y:.1f}" '
                             f'width="{cell_w:.1f}" height="{cell_h:.1f}" '
                             f'fill="{grid}" opacity="0.08"/>')
                elif wknd:
                    wd = weekday(month, day)
                    if wd in (1, 7):
                        e.append(f'<rect x="{cx0:.1f}" y="{event_y:.1f}" '
                                 f'width="{cell_w:.1f}" height="{cell_h:.1f}" '
                                 f'fill="{wknd}" opacity="0.5"/>')
                # day label "{day} {weekday}"
                if day <= days:
                    wd = weekday(month, day)
                    we = wd in (1, 7)
                    numc = f'{today_c}' if we else dlab
                    numo = '0.75' if we else '1'
                    wdc = f'{today_c}' if we else dlab
                    wdo = '0.75' if we else '0.6'
                    tx = cx0 + cell_w / 2
                    e.append(
                        f'<text x="{tx:.1f}" y="{row_y+label_band*0.5+DAY_FONT*0.36:.1f}" '
                        f'font-family="{FONT}" font-size="{DAY_FONT}" '
                        f'text-anchor="middle">'
                        f'<tspan fill="{numc}" fill-opacity="{numo}">{day}</tspan>'
                        f'<tspan fill="{wdc}" fill-opacity="{wdo}"> '
                        f'{WEEKDAYS[wd-1]}</tspan></text>')
            if subrow == 0:
                month_y = row_y + rows_per_month * row_h / 2
                e.append(f'<text x="{month_label_w/2:.1f}" '
                         f'y="{month_y+EVENT_FONT*0.4:.1f}" '
                         f'font-family="{FONT}" font-size="{EVENT_FONT+5:.0f}" '
                         f'font-weight="500" fill="{mlab}" '
                         f'text-anchor="middle">{MONTHS[month-1]}</text>')

    # ---- grid lines --------------------------------------------------------
    for i in range(1, total_rows + 1):
        boundary = i % rows_per_month == 0
        col = dlab if boundary else grid
        op = '0.55' if boundary else '0.5'
        sw = 2.2 if boundary else 1.1
        x0 = 0 if boundary else month_label_w
        gy = i * row_h
        e.append(f'<line x1="{x0:.1f}" y1="{gy:.1f}" x2="{w:.1f}" '
                 f'y2="{gy:.1f}" stroke="{col}" stroke-opacity="{op}" '
                 f'stroke-width="{sw}"/>')
    for i in range(days_per_row + 1):
        boundary = i == 0
        col = dlab if boundary else grid
        op = '0.55' if boundary else '0.5'
        sw = 2.2 if boundary else 1.1
        gx = month_label_w + i * cell_w
        e.append(f'<line x1="{gx:.1f}" y1="0" x2="{gx:.1f}" y2="{h:.1f}" '
                 f'stroke="{col}" stroke-opacity="{op}" stroke-width="{sw}"/>')

    # ---- event bars (split at subrow boundaries) ---------------------------
    def cell_origin(month, day):
        moff = month - start_month
        subrow = (day - 1) // days_per_row
        col = (day - 1) % days_per_row
        vrow = moff * rows_per_month + subrow
        return (month_label_w + col * cell_w, vrow * row_h + label_band)

    for (m, sd, ed, lane, title, color) in events:
        if m < start_month or m > end_month or lane >= vis_rows:
            continue
        day = sd
        while day <= ed:
            subrow = (day - 1) // days_per_row
            row_end = (subrow + 1) * days_per_row
            seg_end = min(ed, row_end)
            ox, oy = cell_origin(m, day)
            bw = (seg_end - day + 1) * cell_w
            by = oy + lane * bar_h
            e.append(f'<rect x="{ox:.1f}" y="{by:.1f}" width="{bw:.1f}" '
                     f'height="{bar_h-1:.1f}" rx="2" fill="{color}"/>')
            if day == sd:
                cid = uid()
                e.append(f'<clipPath id="{cid}"><rect x="{ox:.1f}" '
                         f'y="{by:.1f}" width="{bw:.1f}" '
                         f'height="{bar_h:.1f}"/></clipPath>')
                e.append(f'<text x="{ox+3:.1f}" y="{by+bar_h/2+EVENT_FONT*0.36:.1f}" '
                         f'font-family="{FONT}" font-size="{EVENT_FONT}" '
                         f'fill="#FFFFFF" clip-path="url(#{cid})">'
                         f'{esc(title)}</text>')
            day = seg_end + 1

    # ---- today highlight (cell-box stroke, not a line) ---------------------
    if show_today:
        tm, td = TODAY
        if start_month <= tm <= end_month:
            moff = tm - start_month
            subrow = (td - 1) // days_per_row
            col = (td - 1) % days_per_row
            vrow = moff * rows_per_month + subrow
            tx = month_label_w + col * cell_w
            tyy = vrow * row_h
            e.append(f'<rect x="{tx+1.5:.1f}" y="{tyy+1.5:.1f}" '
                     f'width="{cell_w-3:.1f}" height="{row_h-3:.1f}" '
                     f'fill="none" stroke="{today_c}" stroke-width="3.4"/>')

    e.append("</g>")
    return "".join(e)


def calendar_window(wx, wy, ww, wh, theme, dark, months_shown, start_month,
                    title, zoom_sel, page_label=None, extra_overlay=""):
    """Compose a full calendar window: moodboard + inset rounded grid card."""
    grid_hex = theme["gridLineColor"]
    tbar = toolbar_calendar(wx, wy + 54, ww, 92, dark, zoom_sel, page_label)
    _, (cx, cy, cw, ch) = window(wx, wy, ww, wh, dark, title, "", tbar)

    side = cw * 0.013
    top = ch * 0.18
    bot = ch * 0.022
    card_x = cx + side
    card_y = cy + top
    card_w = cw - 2 * side
    card_h = ch - top - bot

    content = moodboard(cx, cy, cw, ch, grid_hex, dark)
    cid = uid()
    content += (f'<clipPath id="{cid}"><rect x="{card_x:.1f}" '
                f'y="{card_y:.1f}" width="{card_w:.1f}" height="{card_h:.1f}" '
                f'rx="10"/></clipPath>')
    content += (f'<rect x="{card_x-2:.1f}" y="{card_y:.1f}" '
                f'width="{card_w+4:.1f}" height="{card_h+4:.1f}" rx="10" '
                f'fill="#000" opacity="0.16" filter="url(#itemshadow)"/>')
    content += (f'<g clip-path="url(#{cid})">'
                + cal_grid(card_x, card_y, card_w, card_h, theme,
                           months_shown, start_month) + '</g>')
    if extra_overlay:
        content += extra_overlay.format(cx=cx, cy=cy, cw=cw, ch=ch,
                                        card_x=card_x, card_y=card_y,
                                        card_w=card_w, card_h=card_h)
    svg, _ = window(wx, wy, ww, wh, dark, title, content, tbar)
    return svg, (cx, cy, cw, ch, card_x, card_y, card_w, card_h)


# --------------------------------------------------------------------------
# Decoration items (canvas items / vision board items)
# --------------------------------------------------------------------------

def photo(x, y, w, h, rot, grad, radius=4, frame=True):
    cx, cy = x + w / 2, y + h / 2
    inner = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" '
             f'fill="url(#{grad})"/>')
    if frame:
        inner = (f'<rect x="{x-9}" y="{y-9}" width="{w+18}" '
                 f'height="{h+18}" rx="{radius+3}" fill="#FFFFFF" '
                 f'filter="url(#itemshadow)"/>' + inner)
    return f'<g transform="rotate({rot} {cx} {cy})">{inner}</g>'


# Fluent Emoji 3D sticker assets (MIT) — see stickers/ATTRIBUTION.txt.
# Illustrated sticker graphics by Microsoft, matching the app's sticker layer.
STK_DIR = os.path.join(OUT, "stickers")
_STK = {}


def sticker(code, cx, cy, size, rot=0):
    if code not in _STK:
        with open(os.path.join(STK_DIR, code + ".png"), "rb") as f:
            _STK[code] = base64.b64encode(f.read()).decode()
    half = size / 2
    return (f'<g transform="rotate({rot} {cx} {cy})">'
            f'<ellipse cx="{cx}" cy="{cy+size*0.36}" rx="{size*0.40}" '
            f'ry="{size*0.12}" fill="#000" opacity="0.16" '
            f'filter="url(#itemshadow)"/>'
            f'<image x="{cx-half}" y="{cy-half}" width="{size}" '
            f'height="{size}" '
            f'href="data:image/png;base64,{_STK[code]}"/></g>')


def selection(x, y, w, h, accent="#2B7FFF"):
    """1px accent outline + 8 white circle handles (DraggableVisionBoardItem)."""
    e = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" '
         f'stroke="{accent}" stroke-width="2"/>']
    pts = [(x, y), (x + w / 2, y), (x + w, y),
           (x, y + h / 2), (x + w, y + h / 2),
           (x, y + h), (x + w / 2, y + h), (x + w, y + h)]
    for hx, hy in pts:
        e.append(f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="9" fill="#FFFFFF" '
                 f'stroke="{accent}" stroke-width="3"/>')
    return "".join(e)


# --------------------------------------------------------------------------
# Shared SVG defs / layout helpers
# --------------------------------------------------------------------------

def defs():
    return '''<defs>
  <filter id="winshadow" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur stdDeviation="34"/></filter>
  <filter id="itemshadow" x="-50%" y="-50%" width="200%" height="200%">
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
  <linearGradient id="ph5" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#A0E7A0"/>
    <stop offset="1" stop-color="#5BB98C"/></linearGradient>
  <linearGradient id="ph6" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#FF9EC4"/>
    <stop offset="1" stop-color="#C77DFF"/></linearGradient>
</defs>'''


def header(text, sub, color, subcolor):
    return (f'<text x="{W/2}" y="190" font-family="{FONT}" font-size="96" '
            f'font-weight="800" fill="{color}" text-anchor="middle" '
            f'letter-spacing="-1">{esc(text)}</text>'
            f'<text x="{W/2}" y="278" font-family="{FONT}" font-size="41" '
            f'font-weight="500" fill="{subcolor}" '
            f'text-anchor="middle">{esc(sub)}</text>')


def bg(stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return (f'<defs><linearGradient id="bgg" x1="0" y1="0" x2="0.35" y2="1">'
            f'{s}</linearGradient></defs>'
            f'<rect width="{W}" height="{H}" fill="url(#bgg)"/>')


def save(name, svg):
    full = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" '
            f'height="{H}" viewBox="0 0 {W} {H}">{defs()}{svg}</svg>')
    png = os.path.join(OUT, name + ".png")
    cairosvg.svg2png(bytestring=full.encode(), write_to=png,
                     output_width=W, output_height=H)
    print("wrote", png)


# --------------------------------------------------------------------------
# Themes (Themes.json)
# --------------------------------------------------------------------------

MINIMAL = {"backgroundColor": "#FFFFFF", "gridLineColor": "#E0E0E0",
           "todayLineColor": "#FF6B35", "monthLabelColor": "#333333",
           "dayLabelColor": "#666666", "weekendColor": "#F5F5F5"}
TOKYO = {"backgroundColor": "#1A1B26", "gridLineColor": "#292E42",
         "todayLineColor": "#7AA2F7", "monthLabelColor": "#C0CAF5",
         "dayLabelColor": "#565F89", "weekendColor": "#1E1F2B"}
CLASSIC = {"backgroundColor": "#F5F0E8", "gridLineColor": "#C8B8A0",
           "todayLineColor": "#8B4513", "monthLabelColor": "#3C2A14",
           "dayLabelColor": "#5C4A34", "weekendColor": "#EDE4D4"}
NORD = {"backgroundColor": "#ECEFF4", "gridLineColor": "#D8DEE9",
        "todayLineColor": "#5E81AC", "monthLabelColor": "#2E3440",
        "dayLabelColor": "#4C566A", "weekendColor": "#D8E0ED"}


# --------------------------------------------------------------------------
# Screenshot 1 — Year overview
# --------------------------------------------------------------------------

def sc1():
    e = [bg([("0", "#FFEFE4"), ("1", "#FFD8C4")])]
    e.append(header("Your Whole Year, One Screen",
                    "No scrolling, no zooming — every plan at a glance",
                    "#3A2A20", "#9A6A50"))
    win, _ = calendar_window(300, 372, 2280, 1316, MINIMAL, False,
                             12, 1, f"Petals — {YEAR}", 0)
    e.append(win)
    save("01-year-overview", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 2 — Canvas decoration over the calendar
# --------------------------------------------------------------------------

def sc2():
    e = [bg([("0", "#F4EAFF"), ("1", "#FFE0F0")])]
    e.append(header("Your Calendar Becomes a Mood Board",
                    "Drop photos, text, stickers and shapes anywhere",
                    "#33234A", "#7A5C8E"))

    win, geo = calendar_window(300, 372, 2280, 1316, MINIMAL, False,
                               12, 1, f"Petals — {YEAR}", 0)
    cx, cy, cw, ch, kx, ky, kw, kh = geo

    items = []
    items.append(photo(cx + cw * 0.07, cy + ch * 0.05, 300, 215, -7, "ph4"))
    items.append(photo(cx + cw * 0.70, cy + ch * 0.04, 320, 230, 6, "ph2"))
    items.append(photo(cx + cw * 0.55, cy + ch * 0.60, 280, 290, -5, "ph3"))
    items.append(f'<text x="{cx+cw*0.29:.0f}" y="{cy+ch*0.50:.0f}" '
                 f'font-family="{FONT}" font-size="96" font-weight="800" '
                 f'fill="#FF6B6B" text-anchor="middle" '
                 f'transform="rotate(-5 {cx+cw*0.29:.0f} {cy+ch*0.50:.0f})">'
                 f'2026 GOALS</text>')
    items.append(f'<text x="{cx+cw*0.66:.0f}" y="{cy+ch*0.30:.0f}" '
                 f'font-family="{FONT}" font-size="46" font-weight="700" '
                 f'fill="#6A4FB0" transform="rotate(4 {cx+cw*0.66:.0f} '
                 f'{cy+ch*0.30:.0f})">Make it happen!</text>')
    # Fluent Emoji 3D stickers — illustrated sticker graphics
    items.append(sticker("cherry_blossom", cx + cw * 0.085,
                          cy + ch * 0.52, 175, -11))
    items.append(sticker("butterfly", cx + cw * 0.93,
                          cy + ch * 0.31, 190, 15))
    items.append(sticker("rainbow", cx + cw * 0.45,
                          cy + ch * 0.84, 180, -4))
    items.append(sticker("ribbon", cx + cw * 0.89,
                          cy + ch * 0.79, 145, 13))
    items.append(sticker("sparkles", cx + cw * 0.255,
                          cy + ch * 0.205, 124, -9))
    items.append(sticker("strawberry", cx + cw * 0.605,
                          cy + ch * 0.485, 128, 17))
    # a selected image item with handles
    sx, sy, sw, sh = cx + cw * 0.55, cy + ch * 0.60, 280, 290
    items.append(selection(sx, sy, sw, sh))

    e.append(win)
    e.append("".join(items))
    save("02-canvas-moodboard", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 3 — Themes
# --------------------------------------------------------------------------

def sc3():
    e = [bg([("0", "#1B1D2E"), ("1", "#10111C")])]
    e.append(header("Nine Themes for Every Mood",
                    "Light, dark, pastel, classic — switch with a single tap",
                    "#E6EAFF", "#8A93C8"))
    win, _ = calendar_window(300, 348, 2280, 1118, TOKYO, True,
                             12, 1, f"Petals — {YEAR}", 0)
    e.append(win)

    swatches = [
        ("Minimal", "#FFFFFF", "#FF6B35", "#E0E0E0"),
        ("Pastel", "#FFF5F5", "#FF8FA3", "#E8D5D5"),
        ("Classic", "#F5F0E8", "#8B4513", "#C8B8A0"),
        ("Nord", "#ECEFF4", "#5E81AC", "#D8DEE9"),
        ("Tokyo Night", "#1A1B26", "#7AA2F7", "#292E42"),
        ("Dracula", "#282A36", "#FF79C6", "#44475A"),
        ("Midnight", "#1A1A2E", "#00D4FF", "#2A2A4A"),
        ("Monochrome", "#FFFFFF", "#000000", "#000000"),
        ("Solarized", "#FDF6E3", "#CB4B16", "#EEE8D5"),
    ]
    n = len(swatches)
    sw, gap = 232, 26
    total = n * sw + (n - 1) * gap
    sx = (W - total) / 2
    sy = 348 + 1118 + 58
    sel = 4
    for i, (nm, b, ac, gl) in enumerate(swatches):
        x = sx + i * (sw + gap)
        if i == sel:
            e.append(f'<rect x="{x-7}" y="{sy-7}" width="{sw+14}" '
                     f'height="158" rx="22" fill="none" stroke="#7AA2F7" '
                     f'stroke-width="5"/>')
        e.append(f'<rect x="{x}" y="{sy}" width="{sw}" height="104" rx="16" '
                 f'fill="{b}" stroke="{gl}" stroke-width="2"/>')
        for r in range(3):
            e.append(f'<line x1="{x+22}" y1="{sy+32+r*22}" '
                     f'x2="{x+sw-22}" y2="{sy+32+r*22}" stroke="{gl}" '
                     f'stroke-width="3"/>')
        e.append(f'<rect x="{x+sw*0.5}" y="{sy+17}" width="5" height="70" '
                 f'fill="{ac}"/>')
        e.append(f'<text x="{x+sw/2}" y="{sy+142}" font-family="{FONT}" '
                 f'font-size="27" font-weight="600" fill="#C0CAF5" '
                 f'text-anchor="middle">{esc(nm)}</text>')
    save("03-themes", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 4 — Quarter view (zoom layouts)
# --------------------------------------------------------------------------

def sc4():
    e = [bg([("0", "#E2F6EF"), ("1", "#C4E9DD")])]
    e.append(header("Zoom In by Quarter or Month",
                    "Change the zoom level and the layout adapts with it",
                    "#1E3A32", "#4F7A6C"))
    win, _ = calendar_window(300, 372, 2280, 1316, NORD, False,
                             3, 4, f"Petals — {YEAR}", 1, page_label="4–6")
    e.append(win)
    save("04-quarter-view", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 5 — Whiteboard (vision board)
# --------------------------------------------------------------------------

def sc5():
    e = [bg([("0", "#EAF0FF"), ("1", "#D6E0F5")])]
    e.append(header("An Infinite Whiteboard for Your Ideas",
                    "A free-form vision board, separate from your calendar",
                    "#23304A", "#5C6E92"))

    wx, wy, ww, wh = 300, 360, 2280, 1300
    sbw = 360

    # sidebar content
    boards = ["2026 Vision Board", "Travel Bucket List", "Home Ideas",
              "Reading Log"]
    sb = []
    sb.append(f'<g font-family="{FONT}">')
    for i, nm in enumerate(boards):
        ry = wy + 54 + 92 + 26 + i * 58
        if i == 0:
            sb.append(f'<rect x="{wx+14}" y="{ry-8}" width="{sbw-28}" '
                      f'height="48" rx="9" fill="#2B7FFF"/>')
            col = "#FFFFFF"
        else:
            col = "#3A3A3F"
        sb.append(f'<text x="{wx+34}" y="{ry+22}" font-size="24" '
                  f'fill="{col}">{esc(nm)}</text>')
    by = wy + wh - 56
    sb.append(f'<line x1="{wx+1}" y1="{by-14}" x2="{wx+sbw}" y2="{by-14}" '
              f'stroke="#D2D2D7" stroke-width="1.5"/>')
    sb.append(_icon("plus", wx + 38, by + 14, "#86868B", "#FF6B35"))
    sb.append(f'<text x="{wx+58}" y="{by+22}" font-size="23" '
              f'fill="#4A4A50">New Board</text>')
    sb.append("</g>")

    tbar = toolbar_whiteboard(wx + sbw, wy + 54, ww - sbw, 92, False, "100%")
    _, (cx, cy, cw, ch) = window(wx, wy, ww, wh, False, "Whiteboard","",
                                 tbar, sidebar=(sbw, "".join(sb)))

    # infinite dotted canvas
    content = [f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" '
               f'fill="#FCFCFD"/>']
    step = 40
    dots = []
    yy = cy + step
    while yy < cy + ch:
        xx = cx + step
        while xx < cx + cw:
            dots.append(f'<rect x="{xx-1.6:.0f}" y="{yy-1.6:.0f}" '
                        f'width="3.2" height="3.2"/>')
            xx += step
        yy += step
    content.append(f'<g fill="#000000" opacity="0.16">{"".join(dots)}</g>')

    # vision board items
    it = []
    it.append(photo(cx + cw * 0.06, cy + ch * 0.10, 360, 270, -6, "ph2",
                    radius=10))
    it.append(photo(cx + cw * 0.60, cy + ch * 0.07, 340, 250, 5, "ph5",
                    radius=10))
    it.append(photo(cx + cw * 0.30, cy + ch * 0.52, 300, 320, 4, "ph6",
                    radius=10))
    it.append(photo(cx + cw * 0.66, cy + ch * 0.50, 360, 250, -4, "ph4",
                    radius=10))
    # big text
    it.append(f'<text x="{cx+cw*0.40:.0f}" y="{cy+ch*0.22:.0f}" '
              f'font-family="{FONT}" font-size="104" font-weight="800" '
              f'fill="#2B3A67">2026 Vision</text>')
    it.append(f'<text x="{cx+cw*0.07:.0f}" y="{cy+ch*0.52:.0f}" '
              f'font-family="{FONT}" font-size="46" font-weight="700" '
              f'fill="#E0518A" transform="rotate(-6 {cx+cw*0.07:.0f} '
              f'{cy+ch*0.52:.0f})">Stay healthy</text>')
    it.append(f'<text x="{cx+cw*0.62:.0f}" y="{cy+ch*0.84:.0f}" '
              f'font-family="{FONT}" font-size="42" font-weight="600" '
              f'fill="#3A6B4A">Launch the project!</text>')
    # shapes
    it.append(f'<circle cx="{cx+cw*0.50:.0f}" cy="{cy+ch*0.40:.0f}" '
              f'r="78" fill="none" stroke="#4A90D9" stroke-width="6"/>')
    it.append(f'<rect x="{cx+cw*0.85:.0f}" y="{cy+ch*0.20:.0f}" '
              f'width="160" height="110" fill="#FFD86B" opacity="0.55" '
              f'transform="rotate(10 {cx+cw*0.85+80:.0f} '
              f'{cy+ch*0.20+55:.0f})"/>')
    # Fluent Emoji 3D stickers
    it.append(sticker("glowing_star", cx + cw * 0.55, cy + ch * 0.66, 150, 8))
    it.append(sticker("sparkling_heart", cx + cw * 0.20,
                       cy + ch * 0.30, 140, -6))
    it.append(sticker("sunflower", cx + cw * 0.93, cy + ch * 0.70, 152, 10))
    it.append(sticker("party_popper", cx + cw * 0.46,
                       cy + ch * 0.13, 138, -12))
    # selected item with handles
    sx, sy = cx + cw * 0.60, cy + ch * 0.07
    it.append(f'<g transform="rotate(5 {sx+170:.0f} {sy+125:.0f})">'
              + selection(sx, sy, 340, 250) + '</g>')
    content.append("".join(it))

    cid = uid()
    full = (f'<clipPath id="{cid}"><rect x="{cx}" y="{cy}" width="{cw}" '
            f'height="{ch}"/></clipPath>'
            f'<g clip-path="url(#{cid})">{"".join(content)}</g>')
    svg, _ = window(wx, wy, ww, wh, False, "Whiteboard",full, tbar,
                    sidebar=(sbw, "".join(sb)))
    e.append(svg)
    save("05-whiteboard", "".join(e))


# --------------------------------------------------------------------------
# Screenshot 6 — Native Mac
# --------------------------------------------------------------------------

def sc6():
    e = [bg([("0", "#F3ECDC"), ("1", "#E3D6BC")])]
    e.append(header("Built for Mac",
                    "EventKit integration · iCloud sync · native SwiftUI",
                    "#3C2A14", "#8A6E44"))
    wx, wy, ww, wh = 300, 340, 2280, 1130
    win, _ = calendar_window(wx, wy, ww, wh, CLASSIC, False,
                             12, 1, f"Petals — {YEAR}", 0)
    e.append(win)

    feats = [
        ("calendar", "Calendar Sync",
         "All your iCloud, Google & Exchange calendars"),
        ("cloud", "iCloud Sync",
         "Your decorated calendar on every Mac"),
        ("bolt", "Native Speed",
         "A full year rendered in under a second"),
    ]
    cw2, gap = 700, 40
    total = 3 * cw2 + 2 * gap
    fx = (W - total) / 2
    fy = wy + wh + 50
    accent = "#8B4513"
    for i, (ic, t, d) in enumerate(feats):
        x = fx + i * (cw2 + gap)
        e.append(f'<rect x="{x}" y="{fy}" width="{cw2}" height="172" rx="24" '
                 f'fill="#FFFFFF" opacity="0.66"/>')
        cxx, cyy = x + 78, fy + 86
        e.append(f'<circle cx="{cxx}" cy="{cyy}" r="44" fill="{accent}" '
                 f'opacity="0.14"/>')
        e.append(_featicon(ic, cxx, cyy, accent))
        e.append(f'<text x="{x+152}" y="{fy+74}" font-family="{FONT}" '
                 f'font-size="37" font-weight="700" fill="#3C2A14">'
                 f'{esc(t)}</text>')
        e.append(f'<text x="{x+152}" y="{fy+118}" font-family="{FONT}" '
                 f'font-size="25" fill="#7A5E3A">{esc(d)}</text>')
    save("06-native-mac", "".join(e))


def _featicon(name, cx, cy, col):
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
                f'a20 20 0 0 1 38 4 a14 14 0 0 1 2 27 Z" fill="none" '
                f'stroke="{col}" stroke-width="3.6" stroke-linejoin="round"/>')
    return (f'<path d="M{cx+4} {cy-24} L{cx-16} {cy+4} L{cx-2} {cy+4} '
            f'L{cx-6} {cy+24} L{cx+16} {cy-6} L{cx+2} {cy-6} Z" '
            f'fill="{col}"/>')


if __name__ == "__main__":
    sc1()
    sc2()
    sc3()
    sc4()
    sc5()
    sc6()
    print("done")
