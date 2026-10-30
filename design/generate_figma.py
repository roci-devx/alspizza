"""
Generates Figma-importable SVG designs for every Al's Pizza screen.

    python design/generate_figma.py

Output: design/figma/*.svg — drag the files (or the all-screens board) into Figma.
Text stays editable (Fredoka + Nunito are built into Figma), shapes import as
vector layers, gradients and shadows come across as fills/effects.
"""
from __future__ import annotations

import base64
import io
import math
import random
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "figma"
OUT.mkdir(exist_ok=True)

# ── Brand tokens (lib/core/theme.dart) ───────────────────────────────────────
CREAM, CREAM_DEEP, PAPER = "#FCF7EC", "#F5EBD6", "#FFFDF8"
BROWN, BROWN_SOFT, INK, MUTED, LINE = "#5A210F", "#7A4A33", "#2E140A", "#8C7462", "#EADCC4"
ORANGE, ORANGE_LIGHT, ORANGE_DEEP = "#E8962A", "#F6B54E", "#D9771B"
RED, BASIL, CHEESE, SUCCESS = "#B02013", "#356726", "#F7C548", "#2F7A32"
S1, S2, S3, GRID, AXIS = "#D9771B", "#8A3B1F", "#3E7D32", "#EDE5D6", "#8C7F72"
DISPLAY, BODY = "Fredoka", "Nunito"

PHONE_W, PHONE_H = 390, 844
DESK_W, DESK_H = 1440, 960


def logo_data_uri(size: int = 320) -> str:
    src = ROOT.parent / "assets" / "images" / "logo_mark_640.png"
    try:
        from PIL import Image

        im = Image.open(src)
        im.thumbnail((size, size))
        buf = io.BytesIO()
        im.save(buf, format="PNG", optimize=True)
        data = buf.getvalue()
    except Exception:
        data = src.read_bytes()
    return "data:image/png;base64," + base64.b64encode(data).decode()


LOGO = logo_data_uri()
STOCK = ROOT.parent / "backend" / "public" / "stock"
_clip_ids = iter(range(10_000))


def photo(x, y, w, h, slug, r=18, name=None):
    """Stock photo from backend/public/stock, embedded so the SVG stands alone in Figma."""
    src = STOCK / f"{slug}.jpg"
    if not src.exists():
        return ""
    from PIL import Image

    im = Image.open(src).convert("RGB")
    scale = max(w * 2 / im.width, h * 2 / im.height)
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    left, top = (im.width - int(w * 2)) // 2, (im.height - int(h * 2)) // 2
    im = im.crop((left, top, left + int(w * 2), top + int(h * 2)))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=78, optimize=True)
    uri = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    cid = f"clip{next(_clip_ids)}"
    return (f'<g id="{escape(name or "Photo / " + slug)}"><clipPath id="{cid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>'
            f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="{uri}" preserveAspectRatio="xMidYMid slice" clip-path="url(#{cid})"/></g>')

DEFS = f"""
<style>@import url('https://fonts.googleapis.com/css2?family=Fredoka:wght@600;700&amp;family=Nunito:wght@500;600;700;800;900&amp;display=swap');</style>
<defs>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="8" stdDeviation="9" flood-color="{BROWN}" flood-opacity="0.10"/></filter>
  <filter id="shadowStrong" x="-20%" y="-20%" width="140%" height="170%"><feDropShadow dx="0" dy="10" stdDeviation="11" flood-color="{BROWN}" flood-opacity="0.26"/></filter>
  <linearGradient id="gPrimary" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{ORANGE_LIGHT}"/><stop offset="1" stop-color="{ORANGE}"/></linearGradient>
  <linearGradient id="gBrown" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#8A3B1F"/><stop offset="1" stop-color="{BROWN}"/></linearGradient>
  <linearGradient id="gSidebar" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BROWN}"/><stop offset="1" stop-color="#3B1508"/></linearGradient>
  <linearGradient id="gPromo" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E8962A"/><stop offset="1" stop-color="#C9461C"/></linearGradient>
  <linearGradient id="gBasil" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4E8A34"/><stop offset="1" stop-color="#2C5E24"/></linearGradient>
  <linearGradient id="gEta" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FFF0CF"/><stop offset="1" stop-color="#FFE2A8"/></linearGradient>
  <radialGradient id="gHero" cx="0.5" cy="0.55" r="0.6"><stop offset="0" stop-color="#FFF0CF"/><stop offset="1" stop-color="{CREAM}"/></radialGradient>
  <radialGradient id="gCrust" cx="0.5" cy="0.5" r="0.5"><stop offset="0.86" stop-color="#E09A4A"/><stop offset="0.94" stop-color="#F3C27A"/><stop offset="1" stop-color="#C0702E"/></radialGradient>
  <radialGradient id="gCheese" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFE6A0"/><stop offset="0.7" stop-color="#FBD064"/><stop offset="1" stop-color="#F2B640"/></radialGradient>
  <radialGradient id="gPep" cx="0.45" cy="0.4" r="0.6"><stop offset="0" stop-color="#C9361F"/><stop offset="0.75" stop-color="#A4231A"/><stop offset="1" stop-color="#7E160F"/></radialGradient>
</defs>"""


def svg_doc(w: int, h: int, body: str, name: str, bg: str = CREAM) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
        f"<title>{escape(name)}</title>{DEFS}"
        f'<g id="{escape(name)}"><rect width="{w}" height="{h}" fill="{bg}"/>{body}</g></svg>'
    )


# ── Primitives ───────────────────────────────────────────────────────────────
def rect(x, y, w, h, r=0, fill="#fff", stroke=None, sw=1.5, shadow=None, opacity=None, name=None):
    a = f' id="{escape(name)}"' if name else ""
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    f = f' filter="url(#{shadow})"' if shadow else ""
    o = f' opacity="{opacity}"' if opacity is not None else ""
    return f'<rect{a} x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{s}{f}{o}/>'


def circle(cx, cy, r, fill, stroke=None, sw=2, opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    o = f' opacity="{opacity}"' if opacity is not None else ""
    return f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fill}"{s}{o}/>'


def text(x, y, s, size=14, weight=600, color=INK, family=BODY, anchor="start", ls=0, opacity=None):
    o = f' opacity="{opacity}"' if opacity is not None else ""
    lsp = f' letter-spacing="{ls}"' if ls else ""
    return f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}"{lsp}{o}>{escape(s)}</text>'


def display(x, y, s, size=22, color=BROWN, anchor="start", weight=700):
    return text(x, y, s, size, weight, color, DISPLAY, anchor)


def group(name, *parts):
    return f'<g id="{escape(name)}">{"".join(parts)}</g>'


def image(x, y, w, h, href=LOGO):
    return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="{href}" preserveAspectRatio="xMidYMid meet"/>'


# Simple, clean icon set (24px grid) so the file has no icon-font dependency.
ICONS = {
    "home": "M3 11 12 3l9 8v10h-6v-6H9v6H3z",
    "pizza": "M12 2C7.5 2 3.6 4.4 2 8l10 14L22 8c-1.6-3.6-5.5-6-10-6zm-3 8a1.6 1.6 0 1 1 0-3.2A1.6 1.6 0 0 1 9 10zm3 5a1.6 1.6 0 1 1 0-3.2 1.6 1.6 0 0 1 0 3.2zm3-6a1.6 1.6 0 1 1 0-3.2A1.6 1.6 0 0 1 15 9z",
    "tag": "M2 12V3h9l11 11-9 9L2 12zm5-4.5A1.5 1.5 0 1 0 7 4.5a1.5 1.5 0 0 0 0 3z",
    "receipt": "M5 2h14v20l-3-2-2 2-2-2-2 2-2-2-3 2zm3 5h8v2H8zm0 4h8v2H8zm0 4h5v2H8z",
    "person": "M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5 0-9 2.5-9 6v2h18v-2c0-3.5-4-6-9-6z",
    "close": "M5.6 4.2 12 10.6l6.4-6.4 1.4 1.4-6.4 6.4 6.4 6.4-1.4 1.4-6.4-6.4-6.4 6.4-1.4-1.4 6.4-6.4-6.4-6.4z",
    "pin": "M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z",
    "store": "M3 4h18l1 5c0 1.7-1.3 3-3 3s-3-1.3-3-3c0 1.7-1.3 3-3 3s-3-1.3-3-3c0 1.7-1.3 3-3 3S1 10.7 1 9zm1 9.5V20h16v-6.5",
    "bag": "M6 7V6a6 6 0 0 1 12 0v1h3l-1 15H4L3 7zm2 0h8V6a4 4 0 0 0-8 0z",
    "scooter": "M5 18a3 3 0 1 0 0-.1zM19 18a3 3 0 1 0 0-.1zM14 5h3l3 7h-4l-2 4H8l-3-5h7z",
    "search": "M10 3a7 7 0 1 0 4.2 12.6l5.1 5.1 1.4-1.4-5.1-5.1A7 7 0 0 0 10 3zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10z",
    "plus": "M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z",
    "minus": "M5 11h14v2H5z",
    "check": "M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z",
    "chevron": "M9 6l6 6-6 6-1.4-1.4L12.2 12 7.6 7.4z",
    "lock": "M6 10V8a6 6 0 0 1 12 0v2h1v12H5V10zm2 0h8V8a4 4 0 0 0-8 0z",
    "fire": "M12 2s6 5 6 11a6 6 0 0 1-12 0c0-3 2-5 2-5s0 3 2 3c0-5 2-9 2-9z",
    "chat": "M4 4h16v12H8l-4 4z",
    "call": "M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z",
    "clock": "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 5v5.4l4.5 2.7-1 1.7L11 13V7z",
    "card": "M2 5h20v14H2zm2 3v2h16V8zm0 6v3h7v-3z",
    "apple": "M16.5 12.6c0-2.5 2-3.6 2.1-3.7-1.2-1.7-3-1.9-3.6-1.9-1.5-.2-3 .9-3.7.9-.8 0-2-.9-3.2-.8-1.7 0-3.2 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8s1.9.8 3.1.8c1.3 0 2.1-1.2 2.9-2.4.9-1.3 1.3-2.6 1.3-2.7 0 0-2.4-1-2.2-4zM14.2 5.3c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1.1.1 2.1-.6 2.8-1.4z",
    "dash": "M3 3h8v8H3zm10 0h8v5h-8zm0 7h8v11h-8zM3 13h8v8H3z",
    "menu": "M3 6h18v2H3zm0 5h18v2H3zm0 5h18v2H3z",
    "people": "M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm8 1a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM1 20c0-3.3 3.6-6 8-6s8 2.7 8 6v1H1zm16.5-6c2.9.3 5.5 2.1 5.5 4.5V20h-4v-1c0-1.9-.6-3.6-1.5-5z",
    "table": "M3 3h18v18H3zm2 4v4h6V7zm8 0v4h6V7zm-8 6v6h6v-6zm8 0v6h6v-6z",
    "tune": "M3 6h10v2H3zm14 0h4v2h-4zm-2-2h2v6h-2zM3 16h4v2H3zm8 0h10v2H11zm-2-2h2v6H9z",
    "download": "M11 3h2v9l3.5-3.5 1.4 1.4L12 15.8 6.1 9.9l1.4-1.4L11 12zM4 18h16v2H4z",
}


def icon(name, x, y, size=24, color=BROWN):
    s = size / 24
    return f'<path d="{ICONS[name]}" transform="translate({x},{y}) scale({s:.3f})" fill="{color}"/>'


def button(x, y, w, label, style="primary", h=56, icon_name=None, trailing=None):
    fill = {"primary": "url(#gPrimary)", "dark": BROWN, "outline": "#fff", "ghost": "none"}[style]
    fg = CREAM if style == "dark" else BROWN
    stroke = LINE if style == "outline" else None
    parts = [rect(x, y, w, h, h / 2, fill, stroke, shadow="shadowStrong" if style in ("primary", "dark") else None)]
    tx = x + w / 2
    anchor = "middle"
    if trailing:
        tx, anchor = x + 22 + (30 if icon_name else 0), "start"
        parts.append(display(x + w - 22, y + h / 2 + 7, trailing, 18, fg, "end", 600))
    if icon_name:
        ix = (x + 22) if trailing else (tx - 12 - len(label) * 4.6 - 14)
        parts.append(icon(icon_name, ix, y + h / 2 - 11, 22, fg))
    parts.append(display(tx + (14 if icon_name and not trailing else 0), y + h / 2 + 7, label, 18, fg, anchor, 600))
    return group(f"Button / {label}", *parts)


def pill(x, y, label, selected=False, sub=None, w=None, disabled=False):
    w = w or (len(label) * 8.2 + 34)
    h = 54 if sub else 40
    parts = [rect(x, y, w, h, 18, BROWN if selected else (CREAM_DEEP if disabled else "#fff"), None if selected else LINE)]
    parts.append(text(x + 16, y + (22 if sub else 25), label, 14, 800, CREAM if selected else (MUTED if disabled else INK)))
    if sub:
        parts.append(text(x + 16, y + 40, sub, 12, 700, ORANGE_LIGHT if selected else MUTED))
    return group(f"Pill / {label}", *parts), w


def pills_row(x, y, labels, selected=None, gap=8, max_w=350, subs=None, disabled=()):
    out, cx, cy = [], x, y
    row_h = 54 if subs else 40
    for i, l in enumerate(labels):
        w = len(l) * 8.2 + 34
        if subs and subs[i]:
            w = max(w, len(subs[i]) * 6.6 + 34)
        if cx + w > x + max_w:
            cx, cy = x, cy + row_h + gap
        g, _ = pill(cx, cy, l, l == selected, subs[i] if subs else None, w, l in disabled)
        out.append(g)
        cx += w + gap
    return "".join(out), cy + row_h


def tag(x, y, label, color=RED):
    w = len(label) * 6.8 + 16
    return group(f"Tag / {label}", rect(x, y, w, 20, 8, color), text(x + 8, y + 14, label, 10, 900, "#fff", ls=0.6))


def status_bar(w=PHONE_W, dark=False):
    c = CREAM if dark else INK
    return group(
        "Status bar",
        text(28, 34, "9:41", 16, 800, c),
        rect(w - 80, 24, 18, 11, 2, c, opacity=0.9),
        rect(w - 56, 23, 26, 13, 4, "none", c, 1.5),
        rect(w - 53, 26, 18, 7, 2, c),
    )


TABS = [("home", "Home"), ("pizza", "Menu"), ("tag", "Deals"), ("receipt", "Orders"), ("person", "Account")]


def tab_bar(selected: int):
    y = PHONE_H - 90
    parts = [rect(0, y, PHONE_W, 90, 26, "#fff", shadow="shadow")]
    tw = (PHONE_W - 20) / 5
    for i, (ic, label) in enumerate(TABS):
        cx = 10 + tw * i + tw / 2
        if i == selected:
            parts.append(rect(cx - 30, y + 10, 60, 32, 16, ORANGE, opacity=0.22))
        parts.append(icon(ic, cx - 12, y + 14, 24, BROWN if i == selected else MUTED))
        parts.append(text(cx, y + 60, label, 11, 900 if i == selected else 700, BROWN if i == selected else MUTED, anchor="middle"))
    return group("Tab bar", *parts)


def cart_bar(count=3, total="$47.46", y=PHONE_H - 158):
    return group(
        "Cart bar",
        rect(16, y, PHONE_W - 32, 60, 30, BROWN, shadow="shadowStrong"),
        circle(46, y + 30, 20, ORANGE),
        display(46, y + 37, str(count), 18, BROWN, "middle"),
        display(78, y + 37, "View order", 18, CREAM, weight=600),
        display(PHONE_W - 58, y + 37, total, 18, ORANGE_LIGHT, "end", 600),
        icon("chevron", PHONE_W - 52, y + 18, 24, ORANGE_LIGHT),
    )


def card(x, y, w, h, r=24, name="Card", fill="#fff", stroke=None):
    return rect(x, y, w, h, r, fill, stroke, 2, "shadow", name=name)


# ── Illustrations (SVG versions of lib/core/art) ─────────────────────────────
TOPPING_COLORS = {"mushroom": "#E9D8BC", "green-pepper": "#3E8E2F", "onion": "#B25C9F", "olive": "#2A2421", "sausage": "#8A4521", "ham": "#F2A7A1", "bacon": "#B8402F", "chicken": "#F0D9AE", "pineapple": "#F8D54E", "jalapeno": "#4E9A2B", "tomato": "#D93A2C", "basil": "#356726"}


def pizza(cx, cy, r, toppings=("pepperoni",), crust="hand-tossed", sauce="#C8371E", seed=1, name="Pizza"):
    rnd = random.Random(seed)
    rim = {"pan": 0.15, "thin": 0.07, "stuffed": 0.17}.get(crust, 0.12)
    inner = r * (1 - rim)
    rc = inner * 0.93
    parts = [
        f'<ellipse cx="{cx}" cy="{cy + r * 0.08:.1f}" rx="{r * 0.98:.1f}" ry="{r * 0.96:.1f}" fill="{BROWN}" opacity="0.18"/>',
        circle(cx, cy, r, "url(#gCrust)"),
        f'<path d="M{cx - r * 0.78:.1f},{cy - r * 0.48:.1f} A{r * 0.94:.1f},{r * 0.94:.1f} 0 0 1 {cx - r * 0.1:.1f},{cy - r * 0.93:.1f}" stroke="#fff" stroke-opacity="0.3" stroke-width="{r * rim * 0.3:.1f}" fill="none" stroke-linecap="round"/>',
        circle(cx, cy, inner, sauce),
    ]
    pts = []
    for i in range(48):
        a = i / 48 * math.tau
        rr = rc * (1 + 0.03 * math.sin(a * 7 + seed) + 0.018 * math.sin(a * 13 + seed * 2))
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d = f"M{(pts[-1][0] + pts[0][0]) / 2:.1f},{(pts[-1][1] + pts[0][1]) / 2:.1f}"
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        d += f" Q{p[0]:.1f},{p[1]:.1f} {(p[0] + q[0]) / 2:.1f},{(p[1] + q[1]) / 2:.1f}"
    parts.append(f'<path d="{d}Z" fill="url(#gCheese)"/>')
    for _ in range(14):
        a, dd = rnd.random() * math.tau, rc * 0.9 * math.sqrt(rnd.random())
        parts.append(f'<ellipse cx="{cx + math.cos(a) * dd:.1f}" cy="{cy + math.sin(a) * dd:.1f}" rx="{r * 0.03:.1f}" ry="{r * 0.02:.1f}" fill="#D8892E" opacity="0.32"/>')
    for k in range(4):
        a = k * math.pi / 4
        parts.append(f'<line x1="{cx - math.cos(a) * inner:.1f}" y1="{cy - math.sin(a) * inner:.1f}" x2="{cx + math.cos(a) * inner:.1f}" y2="{cy + math.sin(a) * inner:.1f}" stroke="#7A4416" stroke-opacity="0.18" stroke-width="{r * 0.009:.1f}"/>')
    u = r * 0.085
    area = inner * 0.8
    crowd = 1 if len(toppings) <= 2 else max(0.45, 2.2 / len(toppings))
    for t in toppings:
        tr = random.Random(seed * 100 + sum(map(ord, t)))
        n = max(2, round({"pepperoni": 9, "olive": 12, "sausage": 13, "basil": 6, "tomato": 6}.get(t, 9) * crowd))
        for _ in range(n):
            a, dd = tr.random() * math.tau, area * math.sqrt(tr.random())
            x, y = cx + math.cos(a) * dd, cy + math.sin(a) * dd
            rot = tr.random() * 360
            if t == "pepperoni":
                parts.append(circle(x, y, u, "url(#gPep)"))
                parts.append(circle(x - u * 0.35, y - u * 0.2, u * 0.13, "#E77B62", opacity=0.8))
                parts.append(circle(x + u * 0.3, y + u * 0.25, u * 0.11, "#E77B62", opacity=0.8))
            elif t == "olive":
                parts.append(circle(x, y, u * 0.42, "none", "#2A2421", u * 0.24))
            elif t in ("green-pepper", "onion"):
                col = TOPPING_COLORS[t]
                parts.append(f'<path d="M{x - u * 0.7:.1f},{y:.1f} A{u * 0.8:.1f},{u * 0.8:.1f} 0 0 1 {x + u * 0.7:.1f},{y:.1f}" transform="rotate({rot:.0f} {x:.1f} {y:.1f})" stroke="{col}" stroke-width="{u * (0.3 if t == "green-pepper" else 0.14):.1f}" fill="none" stroke-linecap="round"/>')
            elif t in ("basil",):
                parts.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{u * 0.8:.1f}" ry="{u * 0.42:.1f}" transform="rotate({rot:.0f} {x:.1f} {y:.1f})" fill="#3F7F32"/>')
            elif t == "mushroom":
                parts.append(f'<path d="M{x - u * 0.75:.1f},{y:.1f} Q{x - u * 0.7:.1f},{y - u * 0.8:.1f} {x:.1f},{y - u * 0.8:.1f} Q{x + u * 0.7:.1f},{y - u * 0.8:.1f} {x + u * 0.75:.1f},{y:.1f} L{x + u * 0.25:.1f},{y + u * 0.1:.1f} L{x + u * 0.25:.1f},{y + u * 0.7:.1f} L{x - u * 0.25:.1f},{y + u * 0.7:.1f} L{x - u * 0.25:.1f},{y + u * 0.1:.1f} Z" transform="rotate({rot:.0f} {x:.1f} {y:.1f})" fill="#E9D8BC" stroke="#A8896A" stroke-width="{u * 0.1:.1f}"/>')
            elif t == "tomato":
                parts.append(circle(x, y, u, "#D93A2C"))
                parts.append(circle(x, y, u * 0.8, "#EE6A55"))
            else:
                parts.append(circle(x, y, u * 0.45, TOPPING_COLORS.get(t, "#8A4521")))
    return group(name, *parts)


def food(kind, x, y, s, name=None):
    """Small item illustrations: wings, breadsticks, soda, dessert, dip."""
    name = name or f"Art / {kind}"
    if kind.startswith("pizza"):
        return pizza(x + s / 2, y + s / 2, s * 0.46, seed=int(x + y), name=name)
    parts = [f'<ellipse cx="{x + s / 2}" cy="{y + s * 0.88}" rx="{s * 0.36}" ry="{s * 0.06}" fill="{BROWN}" opacity="0.15"/>']
    if kind == "wings":
        parts.append(f'<path d="M{x + s * .1},{y + s * .55} H{x + s * .9} L{x + s * .8},{y + s * .86} H{x + s * .2} Z" fill="#D3A86B"/>')
        for (fx, fy, rot) in [(.3, .48, -30), (.52, .44, 15), (.72, .5, 45), (.42, .56, 90), (.62, .58, -70)]:
            parts.append(f'<rect x="{x + s * fx - s * .15}" y="{y + s * fy - s * .075}" width="{s * .3}" height="{s * .15}" rx="{s * .075}" fill="#C8461F" transform="rotate({rot} {x + s * fx} {y + s * fy})"/>')
    elif kind == "breadsticks":
        for i in range(5):
            parts.append(f'<rect x="{x + s * .41}" y="{y + s * .1}" width="{s * .11}" height="{s * .56}" rx="{s * .055}" fill="#E5A85A" transform="rotate({-28 + i * 13} {x + s * .46} {y + s * .62})"/>')
        parts.append(circle(x + s * .76, y + s * .7, s * .12, "#F7F3EA"))
        parts.append(circle(x + s * .76, y + s * .7, s * .09, "#C8371E"))
    elif kind.startswith("soda"):
        label = {"soda": RED, "soda-lemon": "#2E8B3D"}.get(kind, RED)
        parts.append(f'<path d="M{x + s * .44},{y + s * .14} H{x + s * .56} C{x + s * .57},{y + s * .24} {x + s * .7},{y + s * .26} {x + s * .7},{y + s * .36} V{y + s * .88} H{x + s * .3} V{y + s * .36} C{x + s * .3},{y + s * .26} {x + s * .43},{y + s * .24} {x + s * .44},{y + s * .14} Z" fill="#3A1A0F"/>')
        parts.append(rect(x + s * .42, y + s * .07, s * .16, s * .08, s * .02, label))
        parts.append(rect(x + s * .3, y + s * .5, s * .4, s * .18, 0, label))
    elif kind == "cookie":
        parts.append(circle(x + s / 2, y + s * .52, s * .38, "#D9A05B"))
        rnd = random.Random(3)
        for _ in range(14):
            a, d = rnd.random() * math.tau, math.sqrt(rnd.random()) * s * .3
            parts.append(circle(x + s / 2 + math.cos(a) * d, y + s * .52 + math.sin(a) * d, s * .025, "#3B1C0E"))
    elif kind == "brownie":
        parts.append(rect(x + s * .14, y + s * .24, s * .72, s * .6, s * .05, "#3B1C0E"))
        for r_ in range(3):
            for c_ in range(3):
                parts.append(rect(x + s * (.17 + c_ * .23), y + s * (.27 + r_ * .19), s * .21, s * .17, s * .02, "#6B3A20"))
    elif kind == "dip":
        parts.append(f'<path d="M{x + s * .2},{y + s * .5} L{x + s * .28},{y + s * .82} H{x + s * .72} L{x + s * .8},{y + s * .5} Z" fill="#EEE9DE"/>')
        parts.append(f'<ellipse cx="{x + s / 2}" cy="{y + s * .5}" rx="{s * .3}" ry="{s * .1}" fill="#F4F1E6" stroke="#E2DDD2"/>')
    elif kind == "box":
        parts.append(rect(x + s * .06, y + s * .02, s * .76, s * .34, s * .04, "#C9955A"))
        parts.append(rect(x + s * .04, y + s * .3, s * .8, s * .62, s * .05, "#D9A86C"))
        parts.append(pizza(x + s * .43, y + s * .45, s * .3, seed=11))
    else:
        parts.append(circle(x + s / 2, y + s / 2, s * .3, ORANGE))
    return group(name, *parts)


# ── Screens ──────────────────────────────────────────────────────────────────
screens: dict[str, tuple[int, int, str, str]] = {}


def phone(slug, name, body, bg=CREAM):
    screens[slug] = (PHONE_W, PHONE_H, name, svg_doc(PHONE_W, PHONE_H, status_bar() + body, name, bg))


def desk(slug, name, body):
    screens[slug] = (DESK_W, DESK_H, name, svg_doc(DESK_W, DESK_H, body, name, "#F7F1E5"))


# 01 Welcome
phone("01-welcome", "01 Welcome", "".join([
    pizza(30, 70, 95, ("pepperoni", "basil"), seed=3, name="Decor pizza 1"),
    pizza(380, 250, 75, ("mushroom", "green-pepper", "olive"), seed=5, name="Decor pizza 2"),
    pizza(10, 640, 85, ("pepperoni", "onion"), seed=7, name="Decor pizza 3"),
    pizza(370, 800, 65, ("sausage", "onion"), seed=2, name="Decor pizza 4"),
    image(90, 200, 210, 200),
    display(195, 450, "Hot, fresh &", 34, anchor="middle"),
    display(195, 490, "made your way.", 34, anchor="middle"),
    text(195, 526, "Order Al’s in a few taps — pickup or", 16, 600, MUTED, anchor="middle"),
    text(195, 548, "delivery, your call.", 16, 600, MUTED, anchor="middle"),
    button(24, 690, 342, "Let’s get started", "primary", icon_name="pizza"),
    text(195, 778, "I already have an account", 15, 800, BROWN, anchor="middle"),
]))

# 02 Sign up
src_pills, _ = pills_row(24, 600, ["Instagram", "TikTok", "Friend", "Google", "Flyer", "Facebook", "Other"], "Instagram", max_w=342)
phone("02-sign-up", "02 Create account (X to skip)", "".join([
    circle(344, 74, 22, "#fff"), icon("close", 332, 62, 24, BROWN),
    pizza(195, 140, 56, ("pepperoni", "mushroom", "basil"), seed=9),
    display(195, 240, "Join Al’s", 32, anchor="middle"),
    text(195, 268, "Save your address, reorder favorites in one", 15, 600, MUTED, anchor="middle"),
    text(195, 288, "tap and get member-only deals.", 15, 600, MUTED, anchor="middle"),
    group("Segmented", rect(24, 312, 342, 50, 25, CREAM_DEEP), rect(28, 316, 167, 42, 21, "#fff", shadow="shadow"), text(111, 343, "Create account", 15, 800, BROWN, anchor="middle"), text(280, 343, "Sign in", 15, 800, MUTED, anchor="middle")),
    *[group(f"Field / {ph}", rect(24, y, 342, 52, 16, "#fff", LINE), icon(ic, 40, y + 14, 22, MUTED), text(74, y + 32, ph, 15, 500, MUTED)) for (y, ph, ic) in [(380, "Full name", "person"), (442, "Email", "chat"), (504, "Mobile number (for order updates)", "call")]],
    text(24, 586, "How did you hear about Al’s? (optional)", 14, 800),
    src_pills,
    button(24, 712, 342, "Create my account"),
    text(195, 800, "Continue as guest", 15, 800, BROWN_SOFT, anchor="middle"),
]))

# 03 Location
def store_card(y, name_, addr, dist, eta, selected=False):
    return group(f"Store card / {name_}",
        card(24, y, 342, 96, stroke=ORANGE if selected else None),
        rect(38, y + 22, 52, 52, 16, ORANGE, opacity=0.2), icon("store", 52, y + 36, 24, BROWN),
        display(104, y + 36, name_, 18), text(104, y + 56, addr, 13, 600, MUTED),
        circle(108, y + 74, 4, SUCCESS), text(118, y + 78, f"Open · 11 AM – 11 PM · Ready in ~{eta} min", 12, 800, SUCCESS),
        display(352, y + 38, dist, 16, ORANGE_DEEP, "end"))
phone("03-location", "03 Find your nearest Al's", "".join([
    text(366, 74, "Just browsing", 14, 800, BROWN_SOFT, anchor="end"),
    group("Radar pin", *[f'<ellipse cx="195" cy="190" rx="{40 + i * 28}" ry="{12 + i * 9}" fill="none" stroke="{ORANGE}" stroke-width="3" opacity="{0.7 - i * 0.2:.1f}"/>' for i in range(3)], icon("pin", 165, 110, 60, RED)),
    display(195, 262, "Find your nearest Al’s", 30, anchor="middle"),
    text(195, 290, "Share your location or type an address —", 15, 600, MUTED, anchor="middle"),
    text(195, 310, "we’ll match you with the closest kitchen.", 15, 600, MUTED, anchor="middle"),
    button(24, 336, 342, "Use my current location", "primary", icon_name="pin"),
    group("Search field", rect(24, 412, 342, 52, 16, "#fff", ORANGE, 2), icon("search", 40, 426, 22, MUTED), text(74, 444, "2230 N Lincoln Ave", 15, 700, INK)),
    text(24, 496, "CLOSEST FIRST", 11, 900, MUTED, ls=0.6),
    store_card(508, "Lincoln Park", "2418 N Clark St", "0.6 mi", 18, True),
    store_card(616, "Wicker Park", "1550 N Milwaukee Ave", "1.6 mi", 20),
    store_card(724, "South Loop", "1200 S Michigan Ave", "4.0 mi", 17),
]))

# 04 Mode
phone("04-pickup-or-delivery", "04 Pickup or delivery (skippable)", "".join([
    display(24, 140, "How do you want it?", 32),
    text(24, 170, "From Lincoln Park · you can switch at checkout.", 15, 600, MUTED),
    group("Pickup card", rect(24, 204, 342, 150, 28, "url(#gPrimary)", shadow="shadowStrong"), display(46, 270, "Pickup", 30), text(46, 298, "Ready in about 18 min", 15, 700, BROWN), circle(300, 279, 46, "#fff", opacity=0.35), icon("bag", 276, 255, 48, BROWN)),
    group("Delivery card", rect(24, 374, 342, 150, 28, "url(#gBrown)", shadow="shadowStrong"), display(46, 440, "Delivery", 30, CREAM), text(46, 468, "To 2230 N Lincoln Ave", 15, 700, CREAM, opacity=0.85), circle(300, 449, 46, "#fff", opacity=0.12), icon("scooter", 276, 425, 48, CREAM)),
    text(195, 790, "I’ll decide later", 15, 800, BROWN_SOFT, anchor="middle"),
]))

# 05 Home
def popular(x, y, title_, price, art, tg=None, slug=None):
    pic = photo(x + 12, y + 12, 144, 144, slug, 20) if slug else ""
    return group(f"Popular / {title_}", card(x, y, 168, 232), rect(x + 12, y + 12, 144, 144, 20, CREAM_DEEP), pic or food(art, x + 20, y + 16, 128), tag(x + 20, y + 20, tg) if tg else "", display(x + 14, y + 184, title_, 16), text(x + 14, y + 206, price, 13, 800, ORANGE_DEEP), circle(x + 140, y + 202, 18, ORANGE), icon("plus", x + 129, y + 191, 22, BROWN))
phone("05-home", "05 Home", "".join([
    image(16, 52, 58, 56), text(84, 72, "Good evening, Jordan", 14, 700, MUTED), display(84, 98, "What are we eating?", 22),
    circle(350, 80, 22, BROWN), display(350, 87, "J", 18, CREAM, "middle"),
    group("Context card", card(20, 124, 350, 112), rect(28, 132, 334, 48, 24, CREAM_DEEP), rect(32, 136, 163, 40, 20, BROWN, shadow="shadowStrong"), icon("bag", 70, 145, 20, CREAM), text(118, 162, "Pickup", 15, 900, CREAM, anchor="middle"), icon("scooter", 230, 145, 20, BROWN_SOFT), text(286, 162, "Delivery", 15, 900, BROWN_SOFT, anchor="middle"), icon("store", 38, 192, 22, ORANGE_DEEP), text(70, 202, "Pickup at Lincoln Park", 15, 800), text(70, 222, "0.6 mi · Ready in ~18 min", 13, 600, MUTED)),
    group("Hero carousel", rect(20, 252, 350, 196, 28, "url(#gPromo)", shadow="shadowStrong"), photo(222, 266, 134, 168, "big-als-dinner-box", 22) or food("box", 214, 266, 170), display(40, 294, "Big Al’s", 24, "#fff"), display(40, 322, "Dinner Box", 24, "#fff"), text(40, 348, "2 Medium pizzas, breadsticks", 13, 600, "#fff", opacity=0.9), text(40, 366, "& 6 wings · $27.99", 13, 600, "#fff", opacity=0.9), rect(40, 396, 112, 36, 18, CREAM), text(96, 419, "Order now", 14, 900, BROWN, anchor="middle")),
    rect(168, 458, 22, 7, 4, ORANGE), rect(194, 458, 7, 7, 4, LINE), rect(205, 458, 7, 7, 4, LINE), rect(216, 458, 7, 7, 4, LINE),
    display(20, 500, "Popular right now", 22), text(20, 520, "What the neighborhood is ordering", 13, 600, MUTED),
    popular(20, 534, "Pepperoni Overload", "from $7.99", "pizza", "POPULAR", "pepperoni-overload"),
    popular(202, 534, "Bone-In Wings", "from $8.99", "wings", "POPULAR", "bone-in-wings"),
    cart_bar(3, "$47.46"),
    tab_bar(0),
]))

# 06 Menu
def menu_tile(y, title_, desc, price, cal, art, tags=(), slug=None):
    pic = photo(32, y + 12, 104, 104, slug, 20) if slug else ""
    parts = [card(20, y, 350, 128), rect(32, y + 12, 104, 104, 20, CREAM_DEEP), pic or food(art, 38, y + 18, 92)]
    tx = 150
    for i, t in enumerate(tags):
        parts.append(tag(tx + i * 70, y + 16, t, RED if t == "POPULAR" else BASIL))
    parts += [display(150, y + 58, title_, 18), text(150, y + 78, desc, 13, 600, MUTED), text(150, y + 104, price, 15, 800, ORANGE_DEEP), text(240, y + 104, cal, 12, 600, MUTED), circle(346, y + 64, 19, ORANGE), icon("plus", 335, y + 53, 22, BROWN)]
    return group(f"Menu item / {title_}", *parts)
chips = "".join(group(f"Chip / {c}", rect(x, 122, w, 40, 20, BROWN if i == 1 else "#fff", None if i == 1 else LINE), text(x + w / 2, 147, c, 14, 800, CREAM if i == 1 else BROWN_SOFT, anchor="middle")) for i, (c, x, w) in enumerate([("Deals & Combos", 16, 134), ("Pizzas", 158, 78), ("Wings", 244, 72), ("Sides", 324, 70)]))
phone("06-menu", "06 Menu", "".join([
    display(20, 100, "Menu", 30),
    group("Store chip", rect(256, 74, 114, 32, 16, "#fff", shadow="shadow"), icon("store", 266, 81, 18, ORANGE_DEEP), text(290, 95, "Lincoln Park", 13, 800)),
    chips,
    display(20, 204, "Pizzas", 24), text(20, 224, "Hand-stretched daily, baked to order", 13, 600, MUTED), icon("clock", 300, 205, 16, MUTED), text(370, 218, "~16 min", 12, 800, MUTED, anchor="end"),
    menu_tile(238, "Pepperoni Overload", "Double layer of cupped pepperoni…", "from $7.99", "230–380 cal/slice", "pizza", ("POPULAR",), "pepperoni-overload"),
    menu_tile(378, "Meat Mountain", "Pepperoni, sausage, ham, bacon…", "from $8.99", "300–460 cal/slice", "pizza", ("POPULAR",), "meat-mountain"),
    menu_tile(518, "Garden Veggie", "Mushrooms, peppers, onions, olives…", "from $7.99", "230–380 cal/slice", "pizza", ("VEGGIE",), "garden-veggie"),
    cart_bar(3, "$47.46"),
    tab_bar(1),
]))

# 07 Builder
size_cards = "".join(group(f"Size / {l}", rect(20 + i * 89, 470, 81, 74, 18, BROWN if i == 2 else "#fff", None if i == 2 else LINE), circle(60 + i * 89, 491, 4 + i * 2, "none", ORANGE_LIGHT if i == 2 else MUTED, 2), text(60 + i * 89, 516, l, 13, 900, CREAM if i == 2 else INK, anchor="middle"), text(60 + i * 89, 533, sub, 11, 700, ORANGE_LIGHT if i == 2 else MUTED, anchor="middle")) for i, (l, sub) in enumerate([("Personal", '6" · 4 sl'), ("Medium", '12" · 8 sl'), ("Large", '14" · 8 sl'), ("X-Large", '16" · 12 sl')]))
crusts, cy_ = pills_row(20, 594, ["Original Pan", "Hand-Tossed", "Thin & Crispy", "Stuffed Crust", "NY Style"], "Stuffed Crust", subs=[None, None, None, "+$3.00", "X-Large only"], disabled=("NY Style",), max_w=350)
phone("07-pizza-builder", "07 Pizza builder", "".join([
    rect(0, 0, PHONE_W, 330, 0, "url(#gHero)"),
    status_bar(),
    circle(42, 84, 22, "#fff"), icon("close", 30, 72, 24, BROWN),
    photo(45, 70, 300, 250, "als-supreme", 32, "Item photo") or pizza(195, 200, 128, ("pepperoni", "sausage", "mushroom", "green-pepper", "onion"), "stuffed", seed=4, name="Live pizza"),
    group("Your pizza badge", rect(268, 236, 82, 20, 10, BROWN), text(309, 250, "YOUR PIZZA", 10, 900, CREAM, anchor="middle", ls=0.6), circle(309, 302, 44, CREAM), pizza(309, 302, 38, ("pepperoni", "sausage", "mushroom", "green-pepper", "onion"), "stuffed", seed=4, name="Live preview")),
    tag(20, 342, "POPULAR"),
    display(20, 392, "Al’s Supreme", 30),
    text(20, 418, "Pepperoni, sausage, mushrooms, green peppers", 15, 600, BROWN_SOFT),
    text(20, 438, "and red onions.", 15, 600, BROWN_SOFT),
    display(20, 460, "Size", 20),
    size_cards,
    display(20, 582, "Crust", 20),
    crusts,
    group("Add bar", rect(0, PHONE_H - 104, PHONE_W, 104, 28, "#fff", shadow="shadow"), circle(40, PHONE_H - 58, 20, BROWN), icon("minus", 29, PHONE_H - 69, 22, CREAM), display(80, PHONE_H - 51, "1", 20, anchor="middle"), circle(120, PHONE_H - 58, 20, BROWN), icon("plus", 109, PHONE_H - 69, 22, CREAM), button(156, PHONE_H - 86, 216, "Add to order", trailing="$27.49")),
]))

# 08 Upsell
def upsell_card(x, y, name_, price, art, added=False):
    return group(f"Upsell / {name_}", rect(x, y, 136, 176, 22, "#fff", BASIL if added else None, 2, "shadow"), food(art, x + 29, y + 8, 78), text(x + 10, y + 108, name_, 13, 900), text(x + 10, y + 160, price, 13, 900, ORANGE_DEEP), circle(x + 112, y + 155, 16, BASIL if added else ORANGE), icon("check" if added else "plus", x + 102, y + 145, 20, "#fff" if added else BROWN))
phone("08-complete-your-meal", "08 Complete your meal popup", "".join([
    rect(0, 0, PHONE_W, PHONE_H, 0, INK, opacity=0.45),
    rect(0, 150, PHONE_W, PHONE_H - 150, 30, CREAM),
    rect(173, 160, 44, 5, 3, LINE),
    display(20, 206, "Complete your meal?", 26), text(20, 230, "Most people grab one of these with their pizza.", 14, 600, MUTED),
    display(20, 270, "Sides", 18),
    upsell_card(20, 282, "Breadsticks", "$6.49", "breadsticks", True), upsell_card(168, 282, "Garlic Knots", "$6.99", "breadsticks"), upsell_card(316, 282, "Cheese Sticks", "$7.99", "breadsticks"),
    display(20, 490, "Desserts", 18),
    upsell_card(20, 502, "Cinnamon Twists", "$5.49", "cookie"), upsell_card(168, 502, "Brownie", "$7.99", "brownie"), upsell_card(316, 502, "Giant Cookie", "$7.99", "cookie"),
    button(20, 740, 168, "Keep browsing", "outline"), button(202, 740, 168, "View order (4)"),
]))

# 09 Cart
def cart_line(y, name_, summary, price, art, qty=1):
    return group(f"Cart line / {name_}", card(20, y, 350, 110), rect(32, y + 12, 74, 74, 18, CREAM_DEEP), food(art, 36, y + 16, 66), display(120, y + 34, name_, 17), text(120, y + 54, summary, 12, 600, MUTED), display(120, y + 92, price, 16, ORANGE_DEEP, weight=600), circle(274, y + 86, 15, BROWN), icon("minus", 266, y + 78, 16, CREAM), display(304, y + 92, str(qty), 16, anchor="middle"), circle(334, y + 86, 15, BROWN), icon("plus", 326, y + 78, 16, CREAM))
phone("09-cart", "09 Cart", "".join([
    display(195, 92, "Your order", 20, anchor="middle"), text(195, 110, "Lincoln Park", 12, 600, MUTED, anchor="middle"),
    cart_line(132, "Al’s Supreme", 'Large 14" · Stuffed Crust · Add Jalapeños', "$27.49", "pizza"),
    cart_line(254, "Bone-In Wings", "12 pc · Honey BBQ · Ranch", "$16.49", "wings"),
    cart_line(376, "Cola", "2-Liter", "$7.98", "soda", 2),
    group("Promo applied", rect(20, 500, 350, 52, 18, BASIL, opacity=0.12), icon("tag", 34, 514, 22, BASIL), text(64, 531, "INSTA20 · 20% off on $25.00+", 14, 900, BASIL)),
    group("Totals", card(20, 572, 350, 156), text(40, 606, "Subtotal", 15, 700), text(350, 606, "$51.96", 15, 800, anchor="end"), text(40, 634, "Promo savings", 15, 700, BASIL), text(350, 634, "−$10.39", 15, 800, BASIL, anchor="end"), text(40, 662, "Estimated tax", 15, 700), text(350, 662, "$4.26", 15, 800, anchor="end"), rect(40, 676, 310, 1, 0, LINE), text(40, 708, "Estimated total", 17, 900), display(350, 710, "$45.83", 20, anchor="end")),
    button(20, 760, 350, "Checkout", icon_name="lock", trailing="$51.96"),
]))

# 10 Checkout
phone("10-checkout", "10 Checkout", "".join([
    display(195, 92, "Checkout", 20, anchor="middle"),
    display(20, 140, "Pickup or delivery?", 20),
    group("Toggle", rect(20, 154, 350, 54, 27, CREAM_DEEP), rect(195, 158, 171, 46, 23, BROWN, shadow="shadowStrong"), icon("bag", 60, 170, 20, BROWN_SOFT), text(116, 187, "Pickup", 15, 900, BROWN_SOFT, anchor="middle"), icon("scooter", 230, 170, 20, CREAM), text(290, 187, "Delivery", 15, 900, CREAM, anchor="middle")),
    display(20, 248, "Deliver to", 20), text(370, 248, "Change", 14, 800, ORANGE_DEEP, anchor="end"),
    group("Address", card(20, 262, 350, 70), icon("pin", 36, 282, 30, ORANGE_DEEP), display(78, 292, "2230 N Lincoln Ave", 18), text(78, 314, "Chicago, IL 60614", 13, 600, MUTED)),
    group("Apt", rect(20, 344, 350, 50, 16, "#fff", LINE), text(56, 375, "Apt 3B", 15, 700)),
    group("ETA", rect(20, 406, 350, 84, 24, "url(#gEta)"), circle(62, 448, 25, ORANGE), icon("scooter", 48, 434, 28, BROWN), display(100, 444, "Arrives in about 32–42 min", 18), text(100, 466, "Delivery fee $3.99", 13, 600, BROWN_SOFT)),
    display(20, 528, "Tip your driver", 20), text(170, 528, "100% goes to your driver", 12, 600, MUTED),
    pills_row(20, 542, ["No tip", "15%", "18%", "20%", "Custom"], "18%", subs=[None, "$7.75", "$9.25", "$10.50", None], max_w=360)[0],
    display(20, 640, "Payment", 20), tag(108, 626, "DEMO", ORANGE_DEEP),
    group("Pay / Apple Pay", rect(20, 654, 350, 56, 18, "#fff", ORANGE, 2, "shadow"), icon("apple", 36, 670, 24, BROWN), text(72, 688, "Apple Pay", 16, 800), circle(346, 682, 12, ORANGE), icon("check", 338, 674, 16, BROWN)),
    button(20, 760, 350, "Place order & pay", icon_name="lock", trailing="$71.65"),
]))

# 11 Payment sheet
phone("11-payment-sheet", "11 Apple Pay sheet (demo)", "".join([
    rect(0, 0, PHONE_W, PHONE_H, 0, INK, opacity=0.45),
    rect(10, 430, 370, 404, 30, "#111111"),
    icon("apple", 32, 456, 28, "#fff"), display(68, 480, "Apple Pay", 22, "#fff", weight=600), icon("close", 338, 456, 24, "#fff"),
    rect(32, 500, 326, 52, 12, ORANGE, opacity=0.25), text(46, 522, "Demo mode — no real money moves. Add Stripe", 12, 600, ORANGE_LIGHT), text(46, 540, "/ PayPal keys to the API to go live.", 12, 600, ORANGE_LIGHT),
    text(32, 588, "Merchant", 14, 600, "#fff", opacity=0.6), text(358, 588, "Al’s Pizza", 14, 800, "#fff", anchor="end"),
    text(32, 616, "Card", 14, 600, "#fff", opacity=0.6), text(358, 616, "Visa •••• 4242", 14, 800, "#fff", anchor="end"),
    rect(32, 636, 326, 1, 0, "#ffffff", opacity=0.15),
    text(32, 676, "Pay Al’s Pizza", 16, 800, "#fff"), display(358, 680, "$71.65", 24, "#fff", "end", 600),
    rect(32, 710, 326, 56, 16, "#ffffff"), display(195, 745, "Double-tap to pay", 18, "#000", "middle", 600),
]))

# 12 Tracking
streets = "".join(f'<line x1="{x}" y1="292" x2="{x - 12}" y2="522" stroke="#fff" stroke-width="{11 if (x // 46) % 3 == 0 else 6}"/>' for x in range(38, 370, 46)) + "".join(f'<line x1="20" y1="{y}" x2="370" y2="{y + 8}" stroke="#fff" stroke-width="{11 if (y // 40) % 3 == 1 else 6}"/>' for y in range(306, 522, 40))
phone("12-tracking", "12 Order tracking — on the way", "".join([
    display(195, 92, "Order #4337", 20, anchor="middle"), icon("close", 20, 76, 24, BROWN), icon("call", 346, 76, 22, BROWN),
    circle(195, 170, 60, "url(#gBrown)"), icon("scooter", 165, 140, 60, "#fff"),
    display(195, 262, "On the way", 30, anchor="middle"),
    group("Map", f'<clipPath id="mapclip"><rect x="20" y="286" width="350" height="230" rx="24"/></clipPath>', f'<g clip-path="url(#mapclip)">', rect(20, 286, 350, 230, 24, "#F3EADA"), rect(236, 300, 90, 70, 18, "#D7E7C4"), f'<path d="M10,476 Q140,440 380,500 V530 H10Z" fill="#D2E6EF"/>', streets, '</g>',
          '<path d="M90,460 Q170,330 300,340" stroke="#E8962A" stroke-opacity="0.35" stroke-width="7" fill="none" stroke-linecap="round"/>',
          '<path d="M90,460 Q130,395 190,365" stroke="#5A210F" stroke-width="7" fill="none" stroke-linecap="round"/>',
          circle(90, 460, 18, BROWN, "#fff", 3), icon("store", 80, 450, 20, "#fff"),
          circle(300, 340, 30, ORANGE, opacity=0.25), circle(300, 340, 18, ORANGE_DEEP, "#fff", 3), icon("home", 290, 330, 20, "#fff"),
          circle(190, 365, 21, "#fff", ORANGE, 3), icon("scooter", 178, 353, 24, BROWN)),
    group("Driver", circle(56, 556, 24, ORANGE), display(56, 563, "M", 20, BROWN, "middle"), display(92, 552, "Marcus T.", 18), text(92, 572, "Silver Honda Civic", 13, 600, MUTED), circle(296, 556, 23, BROWN), icon("chat", 285, 545, 22, CREAM), circle(348, 556, 23, BROWN), icon("call", 337, 545, 22, CREAM)),
    group("Steps", card(20, 600, 350, 106), rect(64, 641, 262, 6, 3, CREAM_DEEP), rect(64, 641, 175, 6, 3, ORANGE),
          *[group(f"Step {l}", circle(64 + i * 87.3, 644, 20, ORANGE if i < 3 else "#fff", None if i < 3 else LINE, 2), icon(ic, 54 + i * 87.3, 634, 20, BROWN if i < 3 else MUTED), text(64 + i * 87.3, 688, l, 12, 900 if i < 3 else 700, BROWN if i < 3 else MUTED, anchor="middle")) for i, (l, ic) in enumerate([("Received", "receipt"), ("In the oven", "fire"), ("On the way", "scooter"), ("Delivered", "home")])]),
    group("ETA chip", rect(50, 722, 290, 42, 21, BROWN), icon("clock", 68, 731, 22, ORANGE_LIGHT), text(98, 748, "Arrives around 7:05 PM · 9 min", 15, 800, CREAM)),
]))

# 13 Chat
def bubble(y, msg, mine, time_):
    w = min(270, len(msg) * 7.6 + 30)
    x = 370 - w if mine else 20
    return group(f"Bubble / {msg[:18]}", rect(x, y, w, 58, 20, ORANGE if mine else "#fff", shadow="shadow"), text(x + 14, y + 26, msg, 15, 600, BROWN if mine else INK), text(x + 14, y + 46, time_, 10, 600, BROWN if mine else MUTED, opacity=0.7))
quick, _ = pills_row(16, 676, ["Please leave it at the door", "I’m coming down"], None, max_w=420)
phone("13-chat", "13 Message your driver", "".join([
    display(195, 90, "Marcus T.", 20, anchor="middle"), text(195, 108, "Silver Honda Civic", 12, 600, MUTED, anchor="middle"), icon("call", 346, 76, 22, BROWN),
    bubble(150, "Hi! Ring buzzer 3 please", True, "6:52 PM"),
    bubble(222, "Got it — buzzer 3. Be there in 5!", False, "6:52 PM"),
    bubble(294, "Please leave it at the door", True, "6:55 PM"),
    bubble(366, "I’ll leave it right at the door 👍", False, "6:55 PM"),
    quick,
    group("Composer", rect(16, 736, 290, 52, 16, "#fff", LINE), text(32, 768, "Message your driver", 15, 500, MUTED), circle(340, 762, 25, ORANGE), icon("chat", 328, 750, 24, BROWN)),
]))

# 14 Orders
def order_card(y, num, status, color, items, meta, total, reorder=False):
    h = 150 if reorder else 112
    return group(f"Order / #{num}", card(20, y, 350, h), display(36, y + 32, f"#{num}", 18), tag(96, y + 18, status, color), display(354, y + 32, total, 18, ORANGE_DEEP, "end"), food("pizza", 30, y + 46, 48), food("wings", 52, y + 46, 48), text(112, y + 70, items, 13, 800), text(112, y + 90, meta, 12, 600, MUTED), button(250, y + 104, 104, "Reorder", "outline", 36) if reorder else "")
phone("14-orders", "14 Orders", "".join([
    display(20, 100, "Orders", 30),
    text(20, 132, "IN PROGRESS", 12, 900, MUTED, ls=0.6),
    order_card(144, 4337, "ON THE WAY", ORANGE_DEEP, "1× Al’s Supreme, 1× Bone-In Wings", "Delivery · Thu, Oct 29 6:48 PM", "$71.65"),
    text(20, 290, "PAST ORDERS", 12, 900, MUTED, ls=0.6),
    order_card(302, 4211, "ENJOY!", BASIL, "1× Pepperoni Overload, 1× Breadsticks", "Pickup · Sat, Oct 24 7:12 PM", "$34.10", True),
    order_card(468, 4102, "ENJOY!", BASIL, "1× Family Feast", "Delivery · Fri, Oct 16 6:30 PM", "$41.87", True),
    tab_bar(3),
]))

# 15 Deals
def ticket(y, big, desc, meta, code, grad):
    return group(f"Deal / {code}", rect(20, y, 350, 132, 22, "#fff", shadow="shadow"), f'<path d="M20,{y + 22} a22,22 0 0 1 22,-22 H133 V{y + 132} H42 a22,22 0 0 1 -22,-22 Z" fill="url(#{grad})"/>', display(77, y + 74, big, 22, "#fff", "middle"), circle(133, y, 12, CREAM), circle(133, y + 132, 12, CREAM), *[rect(132, y + 16 + k * 10, 2, 5, 0, LINE) for k in range(11)], text(150, y + 34, desc, 15, 900), text(150, y + 54, meta, 12, 600, MUTED), rect(150, y + 92, len(code) * 9 + 20, 26, 8, CREAM_DEEP), text(160, y + 110, code, 13, 900, BROWN, ls=0.6), button(282, y + 86, 76, "Apply", "dark", 38))
phone("15-deals", "15 Deals", "".join([
    display(20, 100, "Deals", 30), text(20, 124, "Fresh savings, every day", 14, 600, MUTED),
    ticket(146, "15% off", "15% off your first app order", "First order only", "WELCOME15", "gPromo"),
    ticket(294, "Free delivery", "Free delivery on $20+", "Min $20.00", "FREEDEL", "gBrown"),
    ticket(442, "$6.00 off", "$6 off orders $35+ on game day", "Min $35.00", "GAMEDAY", "gBasil"),
    tab_bar(2),
]))

# 16 Account
def acc_row(y, ic, title_, value=None, divider=True):
    return group(f"Row / {title_}", rect(36, y + 10, 38, 38, 12, CREAM_DEEP), icon(ic, 43, y + 17, 24, BROWN), text(88, y + 35, title_, 15, 800), text(334, y + 35, value or "", 13, 600, MUTED, anchor="end"), icon("chevron", 338, y + 17, 24, MUTED), rect(88, y + 58, 266, 1, 0, LINE) if divider else "")
phone("16-account", "16 Account", "".join([
    display(20, 100, "Account", 30),
    group("Profile", rect(20, 120, 350, 112, 28, "url(#gBrown)", shadow="shadowStrong"), circle(72, 176, 32, ORANGE), display(72, 186, "J", 26, BROWN, "middle"), display(120, 170, "Jordan Rivera", 22, CREAM), text(120, 194, "demo@alspizza.com", 13, 600, CREAM, opacity=0.8)),
    text(20, 268, "ORDERING", 12, 900, MUTED, ls=0.6),
    card(20, 280, 350, 176), acc_row(280, "store", "Your store", "Lincoln Park"), acc_row(338, "pin", "Delivery address", "2230 N Lincoln…"), acc_row(396, "tune", "Pickup or delivery", "Delivery", False),
    text(20, 490, "HELP", 12, 900, MUTED, ls=0.6),
    card(20, 502, 350, 118), acc_row(502, "receipt", "Order history"), acc_row(560, "call", "Call Lincoln Park", None, False),
    tab_bar(4),
]))

# ── Owner (web) ──────────────────────────────────────────────────────────────
NAV = [("dash", "Dashboard"), ("fire", "Live orders"), ("menu", "Menu & prep times"), ("tag", "Promo codes"), ("people", "Customers"), ("table", "Reports"), ("tune", "Settings")]


def sidebar(selected):
    parts = [rect(0, 0, 248, DESK_H, 0, "url(#gSidebar)"), rect(20, 22, 52, 52, 14, CREAM), image(24, 26, 44, 44), display(84, 46, "Al’s Pizza", 19, CREAM), text(84, 66, "Owner dashboard", 12, 600, ORANGE_LIGHT)]
    for i, (ic, label) in enumerate(NAV):
        y = 104 + i * 50
        if i == selected:
            parts.append(rect(12, y, 224, 44, 14, ORANGE))
        parts.append(icon(ic, 28, y + 12, 20, BROWN if i == selected else CREAM))
        parts.append(text(60, y + 27, label, 14, 800, BROWN if i == selected else CREAM))
    parts += [circle(30, DESK_H - 96, 4, "#7BD389"), text(42, DESK_H - 92, "Live updates on", 12, 600, CREAM, opacity=0.75), rect(12, DESK_H - 76, 224, 58, 14, "#ffffff", opacity=0.06), circle(42, DESK_H - 47, 18, ORANGE), display(42, DESK_H - 41, "A", 16, BROWN, "middle"), text(70, DESK_H - 52, "Al", 14, 800, CREAM), text(70, DESK_H - 34, "Sign out", 12, 600, ORANGE_LIGHT)]
    return group("Sidebar", *parts)


def filters(x, y, sel="30 days"):
    parts = [rect(x, y, 170, 42, 14, "#fff", LINE), text(x + 14, y + 26, "All stores (3)", 14, 800), icon("chevron", x + 140, y + 9, 22, MUTED)]
    rx = x + 186
    parts.append(rect(rx, y, 470, 42, 14, "#fff", LINE))
    cx = rx + 4
    for label in ["Today", "Yesterday", "7 days", "30 days", "90 days", "Custom"]:
        w = len(label) * 8 + 26
        if label == sel:
            parts.append(rect(cx, y + 3, w, 36, 11, BROWN))
        parts.append(text(cx + w / 2, y + 26, label, 13, 800, CREAM if label == sel else BROWN_SOFT, anchor="middle"))
        cx += w + 2
    return group("Filter row", *parts)


def panel(x, y, w, h, title_, sub=None, table_toggle=True):
    return group(f"Panel / {title_}", rect(x, y, w, h, 22, "#fff", shadow="shadow"), display(x + 20, y + 34, title_, 18, weight=600), text(x + 20, y + 54, sub, 12, 600, MUTED) if sub else "", text(x + w - 20, y + 34, "Table", 12, 800, BROWN_SOFT, anchor="end") if table_toggle else "")


def kpi(x, y, w, label, value, delta, sub, good=True, spark=None, live=False):
    parts = [rect(x, y, w, 130, 20, "#fff", shadow="shadow"), text(x + 18, y + 30, label, 13, 800, MUTED), text(x + 18, y + 66, value, 28, 800, INK)]
    if live:
        parts += [circle(x + w - 46, y + 25, 4, SUCCESS), text(x + w - 18, y + 29, "LIVE", 10, 900, SUCCESS, anchor="end", ls=0.6)]
    if delta:
        parts.append(text(x + 18, y + 90, ("▲ " if good else "▼ ") + delta, 12, 900, "#006300" if good else "#D03B3B"))
    parts.append(text(x + 18 + (len(delta) * 7 + 24 if delta else 0), y + 90, sub, 12, 600, MUTED))
    if spark:
        pts = " ".join(f"{x + 18 + i * (w - 40) / (len(spark) - 1):.1f},{y + 118 - v * 18:.1f}" for i, v in enumerate(spark))
        parts.append(f'<polyline points="{pts}" fill="none" stroke="#C9BFB2" stroke-width="2" stroke-linejoin="round"/>')
        lx, ly = pts.split(" ")[-1].split(",")
        parts.append(circle(float(lx), float(ly), 4, S1, "#fff", 2))
    return group(f"KPI / {label}", *parts)


def owner_header(title_, sub, sel_filter="30 days", show_filters=True):
    return display(276, 66, title_, 30) + text(276, 90, sub, 14, 600, MUTED) + (filters(276, 110, sel_filter) if show_filters else "")


rnd = random.Random(8)
trend = [0.55 + 0.2 * math.sin(i / 3.5) + i * 0.012 + rnd.random() * 0.12 for i in range(30)]
for i in range(30):
    if i % 7 in (4, 5):
        trend[i] += 0.22
tmax = max(trend)
cw, ch, cx0, cy0 = 1080, 120, 316, 568
line_pts = [(cx0 + i * cw / 29, cy0 - v / tmax * ch) for i, v in enumerate(trend)]
area = f'M{cx0},{cy0} ' + " ".join(f"L{x:.1f},{y:.1f}" for x, y in line_pts) + f" L{cx0 + cw},{cy0} Z"
grid = "".join(f'<line x1="{cx0}" y1="{cy0 - k * ch / 3:.0f}" x2="{cx0 + cw}" y2="{cy0 - k * ch / 3:.0f}" stroke="{GRID}"/>' + text(cx0 - 10, cy0 - k * ch / 3 + 4, f"${k * 2}K", 11, 700, AXIS, anchor="end") for k in range(4))
xlabels = "".join(text(cx0 + i * cw / 29, cy0 + 20, f"Oct {i + 1}", 11, 700, AXIS, anchor="middle") for i in range(0, 30, 5))
hours = [2, 4, 9, 14, 10, 6, 4, 7, 15, 22, 24, 18, 11, 5]
bar_w = 22
bars = "".join(rect(316 + i * 46, 896 - h * 5.2, bar_w, h * 5.2, 4, S1) for i, h in enumerate(hours)) + "".join(text(316 + i * 46 + bar_w / 2, 916, lab, 11, 700, AXIS, anchor="middle") for i, lab in enumerate(["11a", "12p", "1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "10p", "11p", "12a"]) if i % 2 == 0)


def split(x, y, w, title_, segs):
    parts = [text(x, y, title_, 13, 800)]
    total = sum(v for _, v, _ in segs)
    cx = x
    for i, (label, v, col) in enumerate(segs):
        sw = (w - 2 * (len(segs) - 1)) * v / total
        parts.append(rect(cx, y + 10, sw, 26, 0 if 0 < i < len(segs) - 1 else 6, col))
        if sw > 44:
            parts.append(text(cx + sw / 2, y + 28, f"{round(v / total * 100)}%", 11, 900, "#fff", anchor="middle"))
        cx += sw + 2
    lx = x
    for label, v, col in segs:
        parts += [rect(lx, y + 48, 10, 10, 2, col), text(lx + 16, y + 57, f"{label} {v}", 12, 700, BROWN_SOFT)]
        lx += len(label) * 7 + 60
    return group(f"Split / {title_}", *parts)


desk("21-owner-dashboard", "21 Owner — Dashboard", "".join([
    sidebar(0),
    owner_header("Dashboard", "All stores · 30 days"),
    kpi(276, 172, 214, "Orders", "1.8K", "17.9%", "vs prior 30 days", True, [0.3, 0.4, 0.35, 0.5, 0.6, 0.45, 0.7, 0.65, 0.8, 0.7, 0.9, 0.85]),
    kpi(504, 172, 214, "Average order", "$42.13", "1.3%", "vs prior 30 days", False, [0.6, 0.5, 0.55, 0.6, 0.5, 0.45, 0.6, 0.55, 0.5, 0.6, 0.5, 0.55]),
    kpi(732, 172, 214, "App users", "422", "", "161 new · 281 with accounts"),
    kpi(960, 172, 214, "Repeat customers", "81%", "15.9 pts", "302 of 373 came back"),
    kpi(1188, 172, 228, "In the kitchen now", "9", "", "orders in progress", live=True),
    panel(276, 320, 1140, 292, "Net sales", "Food + delivery fees − discounts · excludes tax and driver tips"),
    text(296, 426, "$75,164", 48, 800, INK), text(500, 420, "▲ 16.4%  vs prior 30 days", 14, 900, "#006300"),
    group("Trend chart", grid, f'<path d="{area}" fill="{S1}" opacity="0.10"/>', '<polyline points="' + " ".join(f"{x:.1f},{y:.1f}" for x, y in line_pts) + f'" fill="none" stroke="{S1}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>', circle(line_pts[-1][0], line_pts[-1][1], 4.5, S1, "#fff", 2), xlabels),
    panel(276, 628, 690, 312, "Orders by hour", "When the rush hits · store time"),
    group("Column chart", *[f'<line x1="316" y1="{896 - k * 40}" x2="946" y2="{896 - k * 40}" stroke="{GRID}"/>' for k in range(1, 5)], bars),
    panel(984, 628, 432, 312, "How orders arrive", "Share of orders in this range", False),
    split(1004, 704, 392, "Pickup vs delivery", [("Pickup", 792, S1), ("Delivery", 992, S2)]),
    split(1004, 784, 392, "Who delivered", [("DoorDash", 547, S1), ("Own driver", 316, S2), ("Uber Direct", 98, S3)]),
    split(1004, 864, 392, "Ordering from", [("iOS", 807, S1), ("Android", 591, S2), ("Web", 386, S3)]),
]))


def board_card(x, y, num, kind, mins, name_, items, total, button_label, late=False, courier=None):
    parts = [rect(x, y, 266, 210 if courier else 172, 18, "#fff", "#B02013" if late else None, 2, "shadow"), display(x + 14, y + 30, f"#{num}", 19), rect(x + 74, y + 15, 70 if kind == "DELIVERY" else 58, 20, 8, S2 if kind == "DELIVERY" else S1), text(x + 82, y + 29, kind, 11, 900, "#fff"), text(x + 252, y + 30, f"{mins} min", 12, 900, "#B02013" if late else MUTED, anchor="end"), text(x + 14, y + 52, name_, 13, 800, BROWN_SOFT)]
    for i, it in enumerate(items):
        parts.append(text(x + 14, y + 78 + i * 20, it, 14, 900))
    parts.append(rect(x + 14, y + 80 + len(items) * 20 - 8, 60, 20, 8, INK, opacity=0.1))
    parts.append(text(x + 22, y + 80 + len(items) * 20 + 6, total, 11, 900, INK))
    by = y + 128
    if courier:
        parts += [rect(x + 14, by - 6, 238, 40, 12, "#FBF5EA"), icon("scooter", x + 22, by + 2, 18, BROWN_SOFT), text(x + 46, by + 18, courier, 12, 900)]
        by += 40
    parts.append(button(x + 14, by, 200, button_label, "dark", 36))
    return group(f"Board card / #{num}", *parts)


def board_col(x, title_, count, ic, cards):
    return group(f"Column / {title_}", rect(x, 172, 286, 760, 22, "#EFE6D6"), icon(ic, x + 18, 190, 20, BROWN), display(x + 46, 206, title_, 18, weight=600), rect(x + 246, 190, 26, 22, 10, BROWN), text(x + 259, 206, str(count), 13, 900, CREAM, anchor="middle"), *cards)


desk("22-owner-live-orders", "22 Owner — Live orders (kitchen board)", "".join([
    sidebar(1),
    owner_header("Live orders", "Updates instantly as orders, couriers and the kitchen move", show_filters=False),
    filters(276, 110, None) if False else group("Store filter", rect(276, 110, 170, 42, 14, "#fff", LINE), text(290, 136, "All stores (3)", 14, 800)),
    board_col(276, "New", 2, "fire", [board_card(286, 226, 4355, "PICKUP", 2, "Smoke Tester · (312) 555-0177", ["1× Al’s Supreme", "1× Bone-In Wings"], "$62.29", "Start making"), board_card(286, 410, 4354, "DELIVERY", 4, "Maria Garcia · (773) 555-0112", ["2× Classic Pepperoni"], "$38.40", "Start making", courier="Courier (demo) · assigning…")]),
    board_col(578, "In the oven", 3, "fire", [board_card(588, 226, 4351, "PICKUP", 14, "Liam Okafor · (312) 555-0145", ["1× Meat Mountain", "1× Cola"], "$31.10", "Mark ready", True), board_card(588, 410, 4352, "DELIVERY", 9, "Mei Tanaka · (872) 555-0108", ["1× Family Feast"], "$41.87", "Mark ready", courier="DoorDash · Priya K. · at the store")]),
    board_col(880, "Ready", 1, "bag", [board_card(890, 226, 4349, "PICKUP", 21, "Ethan Kim · (630) 555-0131", ["1× Garden Veggie", "1× Breadsticks"], "$29.75", "Picked up")]),
    board_col(1182, "Out for delivery", 2, "scooter", [board_card(1192, 226, 4347, "DELIVERY", 26, "Grace Rossi · (847) 555-0119", ["1× BBQ Chicken Ranch"], "$33.20", "Delivered", courier="Own driver · Jamal W.")]),
]))

desk("23-owner-menu", "23 Owner — Menu & prep times", "".join([
    sidebar(2),
    owner_header("Menu & prep times", "Pickup ETA = slowest item’s prep time + ~2 min for every order already in the kitchen", show_filters=False),
    panel(276, 120, 1140, 190, "Prep time by food type", "What customers are quoted at checkout. Tweak during a rush.", False),
    *[group(f"Prep / {n}", rect(296 + i * 230, 196, 218, 92, 16, "#FBF5EA"), text(312 + i * 230, 226, n, 14, 900), display(312 + i * 230, 260, f"{m} min", 22, ORANGE_DEEP), circle(456 + i * 230, 242, 15, BROWN), icon("minus", 448 + i * 230, 234, 16, CREAM), circle(494 + i * 230, 242, 15, BROWN), icon("plus", 486 + i * 230, 234, 16, CREAM)) for i, (n, m) in enumerate([("Deals & Combos", 20), ("Pizzas", 16), ("Wings", 14), ("Sides", 10), ("Pasta", 14)])],
    panel(276, 330, 1140, 420, "Pizzas", "13 items · 0 sold out", False),
    *[group(f"Item / {n}", food("pizza", 296, 380 + i * 64, 48), text(360, 400 + i * 64, n, 14, 900), text(360, 420 + i * 64, d, 12, 600, MUTED), text(860, 410 + i * 64, p, 14, 900, ORANGE_DEEP), text(1010, 410 + i * 64, "Prep: 16 min", 12, 600, MUTED), rect(1330, 394 + i * 64, 52, 30, 15, SUCCESS if on else LINE), circle(1367 if on else 1345, 409 + i * 64, 11, "#fff")) for i, (n, d, p, on) in enumerate([("Pepperoni Overload", "Double layer of cupped pepperoni over extra mozzarella.", "from $7.99", True), ("Meat Mountain", "Pepperoni, Italian sausage, ham, bacon and seasoned beef.", "from $8.99", True), ("Al’s Supreme", "Pepperoni, sausage, mushrooms, green peppers and red onions.", "from $8.49", True), ("Classic Pepperoni", "The one everybody agrees on.", "from $6.49", True), ("Hawaiian Sunset", "Ham, bacon and sweet pineapple.", "from $7.99", False), ("Basil Margherita", "Roma tomatoes, fresh basil and mozzarella.", "from $7.49", True)])],
]))


def table(x, y, w, cols, rows, widths):
    parts = []
    cx = x
    for c, cw_ in zip(cols, widths):
        parts.append(text(cx + 10, y + 20, c.upper(), 11, 900, MUTED, ls=0.6))
        cx += cw_
    parts.append(rect(x, y + 32, w, 1, 0, LINE))
    for r_, row in enumerate(rows):
        ry = y + 34 + r_ * 42
        if r_ % 2:
            parts.append(rect(x, ry, w, 42, 0, "#FBF7F0"))
        cx = x
        for c_, (val, cw_) in enumerate(zip(row, widths)):
            parts.append(text(cx + 10, ry + 26, val, 13, 900 if c_ == 0 else 700))
            cx += cw_
    return group("Table", *parts)


desk("24-owner-promos", "24 Owner — Promo codes", "".join([
    sidebar(3),
    owner_header("Promo codes", "Create a code per campaign — results show up on the dashboard under “Which marketing worked”", show_filters=False),
    button(1236, 40, 180, "New promo code", "primary", 46, "plus"),
    panel(276, 120, 1140, 440, "All codes", "Lifetime results", False),
    table(296, 190, 1100, ["Code", "Offer", "Channel", "Campaign", "Uses", "Net sales", "Discount", "In app", "Active"], [
        ["INSTA20", "20% off on $25+", "Instagram", "Fall cheese-pull reels", "241", "$9,812", "$2,103", "—", "On"],
        ["TIKTOK5", "$5 off on $20+", "TikTok", "Stuffed crust challenge", "132", "$4,977", "$660", "—", "On"],
        ["FREEDEL", "Free delivery on $20+", "Email", "October newsletter", "88", "$3,401", "$351", "Yes", "On"],
        ["WELCOME15", "15% off · first order", "In-App", "App onboarding", "61", "$2,388", "$402", "Yes", "On"],
        ["GAMEDAY", "$6 off on $35+", "Facebook", "Sunday football", "54", "$2,911", "$324", "Yes", "On"],
        ["RADIO25", "25% off on $30+", "Radio", "Morning show spot", "47", "$2,240", "$612", "—", "Off"],
    ], [130, 190, 120, 230, 70, 110, 110, 70, 70]),
]))

desk("25-owner-customers", "25 Owner — Customers", "".join([
    sidebar(4),
    owner_header("Customers", "373 customers · 302 ordered more than once", show_filters=False),
    group("Store filter", rect(276, 110, 170, 42, 14, "#fff", LINE), text(290, 136, "All stores (3)", 14, 800)),
    panel(276, 172, 1140, 520, "Everyone who has ordered", "Matched by phone number, so guests and account holders line up", False),
    group("Search", rect(1136, 188, 260, 40, 14, "#fff", LINE), icon("search", 1148, 197, 20, MUTED), text(1176, 213, "Search name, phone, email", 13, 500, MUTED)),
    table(296, 244, 1100, ["Customer", "Phone", "Orders", "Net sales", "First order", "Last order", "Heard about us", "Type"], [
        ["Jordan Rivera  REPEAT", "(312) 555-0150", "38", "$1,612", "Aug 30", "2 hr ago", "Instagram", "Account"],
        ["Maria Garcia  REPEAT", "(773) 555-0112", "31", "$1,288", "Aug 30", "1 day ago", "Friend", "Account"],
        ["Ahmed Patel  REPEAT", "(312) 555-0101", "24", "$977", "Sep 2", "3 days ago", "Google", "Account"],
        ["Sofia Kim", "(872) 555-0133", "1", "$42", "Oct 27", "2 days ago", "TikTok", "Guest"],
        ["Liam Okafor  REPEAT", "(630) 555-0145", "12", "$511", "Sep 14", "5 hr ago", "Flyer", "Account"],
    ], [220, 150, 80, 110, 120, 120, 160, 100]),
]))

desk("26-owner-reports", "26 Owner — Reports (Excel)", "".join([
    sidebar(5),
    owner_header("Reports", "An Excel workbook per store per day: summary, every order, items, promo codes, hourly sales and payments", show_filters=False),
    panel(276, 120, 1140, 150, "Generate a report", "Reports also build automatically at each store’s closing-report time and email out if SMTP is configured.", False),
    rect(296, 196, 220, 46, 14, "#fff", LINE), icon("clock", 310, 207, 22, BROWN), text(342, 225, "Thu, Oct 29, 2026", 14, 800),
    button(530, 196, 190, "Generate .xlsx", "primary", 46, "table"),
    panel(276, 290, 1140, 330, "Daily reports", None, False),
    table(296, 330, 1100, ["Date", "Store", "Orders", "Net sales", "Avg order", "New cust.", "Courier fees", "Generated", ""], [
        ["Wed, Oct 28", "Lincoln Park", "31", "$1,402", "$45.23", "4", "$112", "11:30 PM", "⤓ Excel"],
        ["Wed, Oct 28", "Wicker Park", "17", "$742", "$43.66", "4", "$36", "11:30 PM", "⤓ Excel"],
        ["Wed, Oct 28", "South Loop", "14", "$621", "$44.39", "3", "$45", "11:30 PM", "⤓ Excel"],
        ["Tue, Oct 27", "Lincoln Park", "28", "$1,197", "$42.75", "5", "$98", "11:30 PM", "⤓ Excel"],
        ["Tue, Oct 27", "Wicker Park", "21", "$903", "$43.00", "2", "$61", "11:30 PM", "⤓ Excel"],
    ], [140, 150, 90, 120, 120, 100, 130, 140, 110]),
]))

desk("27-owner-settings", "27 Owner — Settings", "".join([
    sidebar(6),
    owner_header("Settings", "Al’s Pizza — Lincoln Park", show_filters=False),
    button(1236, 40, 180, "Save changes", "primary", 46, "check"),
    panel(276, 120, 560, 330, "Store", None, False),
    *[group(f"Switch / {l}", text(296, 230 + i * 52, l, 14, 800), rect(764, 212 + i * 52, 52, 30, 15, SUCCESS), circle(801, 227 + i * 52, 11, "#fff")) for i, l in enumerate(["Accepting online orders", "Pickup", "Delivery", "Pay at pickup (cash)"])],
    rect(296, 164, 520, 40, 14, "#fff", LINE), text(310, 189, "Al’s Pizza — Lincoln Park", 14, 700),
    panel(856, 120, 560, 330, "Kitchen & tax", None, False),
    text(876, 190, "Extra minutes per order in the kitchen", 14, 800), text(876, 210, "Added to the pickup ETA for every order in progress", 12, 600, MUTED), display(1360, 200, "2", 20, anchor="middle"),
    text(876, 260, "Sales tax: 10.25%", 14, 800), rect(876, 276, 520, 4, 2, LINE), rect(876, 276, 355, 4, 2, BROWN), circle(1231, 278, 9, BROWN),
    text(876, 330, "End-of-day report", 14, 900), rect(876, 344, 180, 40, 14, "#fff", LINE), text(890, 369, "Runs at 23:30", 13, 800), rect(1070, 344, 326, 40, 14, "#fff", LINE), text(1084, 369, "owner@alspizza.com", 13, 700),
    panel(276, 470, 1140, 250, "Delivery", "Customers always see Al’s — the courier network runs behind the scenes", False),
    pills_row(296, 540, ["Auto", "Own drivers only", "DoorDash Drive", "Uber Direct"], "Auto", subs=["Own drivers first, then DoorDash, then Uber", "Staff assign every delivery", "Uber Direct as backup", "DoorDash as backup"], max_w=1100)[0],
    text(296, 640, "Own drivers on duty", 14, 800), display(520, 642, "0", 20), text(640, 640, "Delivery fee (courier)  $3.99", 14, 800), text(920, 640, "Minimum delivery order  $12.00", 14, 800), text(296, 690, "Delivery radius: 6.0 mi", 14, 800),
    panel(276, 740, 560, 190, "Point of sale", "Paid app orders are pushed straight into your POS / kitchen screen", False),
    *[group(f"POS / {l}", circle(306, 812 + i * 28, 8, "none", BROWN, 2), circle(306, 812 + i * 28, 4, BROWN) if i == 0 else "", text(324, 817 + i * 28, l, 14, 800)) for i, l in enumerate(["No POS — use the dashboard as kitchen display", "Square", "Clover", "Toast (partner API)"])],
    panel(856, 740, 560, 190, "Integrations", "Read from the API server’s .env", False),
    *[group(f"Integration / {l}", circle(884, 808 + i * 24, 7, "none", MUTED, 2), text(900, 812 + i * 24, l, 13, 700), text(1396, 812 + i * 24, "Not set", 12, 800, MUTED, anchor="end")) for i, l in enumerate(["Stripe (cards, Apple Pay, Google Pay)", "PayPal", "DoorDash Drive", "Uber Direct", "Twilio (driver chat relay)"])],
]))

desk("20-owner-login", "20 Owner — Sign in", "".join([
    rect(0, 0, 720, DESK_H, 0, "url(#gBrown)"),
    pizza(640, 860, 260, ("pepperoni", "mushroom", "basil"), seed=12, name="Hero pizza"),
    rect(48, 48, 126, 126, 24, CREAM), image(56, 56, 110, 110),
    display(48, 560, "Every order.", 52, CREAM), display(48, 622, "Every store.", 52, CREAM), display(48, 684, "Live.", 52, CREAM),
    text(48, 724, "Live kitchen board · sales & marketing analytics · nightly Excel reports", 16, 600, ORANGE_LIGHT),
    display(880, 380, "Owner sign in", 32), text(880, 408, "Orders, sales and reports for every Al’s location.", 15, 600, MUTED),
    rect(880, 436, 400, 52, 16, "#fff", LINE), text(916, 468, "owner@alspizza.com", 15, 700),
    rect(880, 500, 400, 52, 16, "#fff", LINE), text(916, 532, "••••••••••••", 15, 700),
    button(880, 576, 400, "Sign in"),
]))


# ── Owner app on phones ──────────────────────────────────────────────────────
OWNER_TABS = [("dash", "Dashboard"), ("fire", "Orders"), ("menu", "Menu"), ("table", "Reports"), ("tune", "More")]


def owner_phone_bar(title_):
    return group("App bar", display(20, 92, title_, 22, weight=600), circle(316, 85, 4, SUCCESS), text(370, 90, "Live", 12, 800, MUTED, anchor="end"))


def owner_tabs(selected, badge=None):
    y = PHONE_H - 84
    parts = [rect(0, y, PHONE_W, 84, 0, "#fff", shadow="shadow")]
    tw = PHONE_W / 5
    for i, (ic, label) in enumerate(OWNER_TABS):
        cx = tw * i + tw / 2
        if i == selected:
            parts.append(rect(cx - 30, y + 10, 60, 32, 16, ORANGE, opacity=0.25))
        parts.append(icon(ic, cx - 12, y + 14, 24, BROWN if i == selected else MUTED))
        parts.append(text(cx, y + 62, label, 12, 800 if i == selected else 600, BROWN if i == selected else MUTED, anchor="middle"))
        if badge and label == "Orders":
            parts += [circle(cx + 14, y + 16, 9, RED), text(cx + 14, y + 20, str(badge), 10, 900, "#fff", anchor="middle")]
    return group("Owner tab bar", *parts)


phone("30-owner-app-dashboard", "30 Owner app - Dashboard (phone)", "".join([
    owner_phone_bar("Dashboard"),
    text(20, 118, "All stores \u00b7 Today", 13, 600, MUTED),
    group("Filters", rect(20, 130, 130, 38, 12, "#fff", LINE), text(32, 154, "All stores (3)", 13, 800), rect(160, 130, 210, 38, 12, "#fff", LINE), rect(164, 133, 60, 32, 10, BROWN), text(194, 154, "Today", 12, 800, CREAM, anchor="middle"), text(260, 154, "7 days", 12, 800, BROWN_SOFT, anchor="middle"), text(330, 154, "30 days", 12, 800, BROWN_SOFT, anchor="middle")),
    kpi(20, 184, 170, "Orders", "62", "8.1%", "vs prior day", True, [0.3, 0.5, 0.4, 0.6, 0.55, 0.7, 0.8, 0.75, 0.9, 0.85, 0.95, 1.0]),
    kpi(200, 184, 170, "Average order", "$44.20", "2.0%", "vs prior day", True, [0.5, 0.6, 0.55, 0.6, 0.62, 0.58, 0.6, 0.64, 0.66, 0.6, 0.65, 0.7]),
    kpi(20, 326, 170, "Repeat customers", "81%", "3.2 pts", "came back"),
    kpi(200, 326, 170, "In the kitchen", "5", "", "orders now", live=True),
    group("Net sales", rect(20, 470, 350, 250, 22, "#fff", shadow="shadow"), display(40, 504, "Net sales", 18, weight=600), text(40, 554, "$2,741", 40, 800, INK), text(40, 580, "\u25b2 11.4% vs prior day", 13, 900, "#006300"),
          '<polyline points="40,690 80,670 120,676 160,650 200,660 240,630 280,640 320,610 350,600" fill="none" stroke="#D9771B" stroke-width="2"/>', '<path d="M40,690 80,670 120,676 160,650 200,660 240,630 280,640 320,610 350,600 L350,700 L40,700Z" fill="#D9771B" opacity="0.10"/>', circle(350, 600, 4, S1, "#fff", 2)),
    owner_tabs(0),
]), "#F7F1E5")

phone("31-owner-app-orders", "31 Owner app - Live orders (phone)", "".join([
    owner_phone_bar("Live orders"),
    text(20, 118, "Swipe sideways: New, In the oven, Ready, Out for delivery", 13, 600, MUTED),
    group("Column / New", rect(16, 134, 334, 650, 22, "#EFE6D6"), icon("fire", 32, 150, 20, BROWN), display(60, 166, "New", 18, weight=600), rect(306, 150, 26, 22, 10, BROWN), text(319, 166, "2", 13, 900, CREAM, anchor="middle"),
          board_card(28, 188, 4361, "PICKUP", 1, "Jordan Rivera \u00b7 (312) 555-0150", ["1\u00d7 Al\u2019s Supreme", "1\u00d7 Cinnamon Twists"], "$38.12", "Start making"),
          board_card(28, 372, 4360, "DELIVERY", 3, "Maria Garcia \u00b7 (773) 555-0112", ["2\u00d7 Classic Pepperoni"], "$41.07", "Start making", courier="Courier \u00b7 Priya K. \u00b7 heading to store")),
    rect(356, 134, 34, 650, 22, "#EFE6D6", opacity=0.6),
    owner_tabs(1, badge=2),
]), "#F7F1E5")


def owner_item_row(y, name_, meta, slug, on=True):
    return group(f"Menu row / {name_}", card(16, y, 358, 84, 20), photo(26, y + 10, 64, 64, slug, 16), text(102, y + 38, name_, 15, 900), text(102, y + 58, meta, 12, 600, MUTED), rect(300, y + 28, 46, 28, 14, SUCCESS if on else LINE), circle(332 if on else 314, y + 42, 10, "#fff"))


phone("32-owner-app-menu", "32 Owner app - Menu portal (phone)", "".join([
    owner_phone_bar("Menu"),
    text(20, 118, "Items, photos, ingredients, options and menu types", 13, 600, MUTED),
    pills_row(16, 132, ["Items", "Menu types", "Pizza options"], "Items", max_w=380)[0],
    button(16, 184, 358, "New item", "primary", 48, "plus"),
    display(20, 264, "Pizzas", 20), text(370, 264, "16 min prep", 12, 800, MUTED, anchor="end"),
    owner_item_row(278, "Pepperoni Overload", "from $7.99 \u00b7 1 topping", "pepperoni-overload"),
    owner_item_row(372, "Meat Mountain", "from $8.99 \u00b7 5 toppings", "meat-mountain"),
    owner_item_row(466, "Al\u2019s Supreme", "from $8.49 \u00b7 5 toppings", "als-supreme"),
    owner_item_row(560, "Hawaiian Sunset", "from $7.99 \u00b7 3 toppings \u00b7 SOLD OUT", "hawaiian-sunset", on=False),
    owner_item_row(654, "Basil Margherita", "from $7.49 \u00b7 2 toppings", "basil-margherita"),
    owner_tabs(2),
]), "#F7F1E5")

ingredient_pills, _ = pills_row(32, 600, ["Pepperoni", "Italian Sausage", "Ham", "Bacon", "Mushrooms", "Green Peppers", "Red Onions"], None, max_w=330)
phone("33-owner-app-item-editor", "33 Owner app - Edit item (phone)", "".join([
    display(195, 92, "Edit item", 20, anchor="middle"), icon("close", 20, 76, 24, BROWN),
    group("Photo", card(16, 116, 358, 156), photo(32, 132, 124, 124, "als-supreme", 22), text(172, 156, "This photo shows on the menu", 12, 600, MUTED), text(172, 174, "and home screen.", 12, 600, MUTED), button(172, 190, 186, "Replace photo", "dark", 42), text(184, 254, "Paste a link   \u00b7   Remove", 13, 800, ORANGE_DEEP)),
    group("Basics", card(16, 286, 358, 196), display(32, 318, "Basics", 18, weight=600), rect(32, 332, 326, 44, 14, "#fff", LINE), text(46, 360, "Al\u2019s Supreme", 14, 700), rect(32, 384, 326, 44, 14, "#fff", LINE), text(46, 412, "Menu type: Pizzas", 14, 700), rect(32, 436, 326, 36, 14, "#fff", LINE), text(46, 459, "Item type: Pizza", 13, 700)),
    group("Ingredients", card(16, 496, 358, 236), display(32, 528, "Ingredients", 18, weight=600), text(32, 548, "What comes on it - customers can still customize", 12, 600, MUTED), text(32, 586, "MEATS & VEGGIES", 10, 900, MUTED, ls=0.6), ingredient_pills),
    button(16, 760, 358, "Save changes", "primary", 52, "check"),
]))

# ── Design system sheet ──────────────────────────────────────────────────────
def swatch(x, y, name_, hex_):
    return group(f"Color / {name_}", rect(x, y, 150, 96, 18, hex_, LINE if hex_ in (CREAM, "#ffffff", PAPER) else None, shadow="shadow"), text(x, y + 120, name_, 14, 900), text(x, y + 140, hex_, 12, 700, MUTED))


ds = [display(40, 70, "Al’s Pizza — design system", 36), text(40, 100, "Tokens and components used by the customer app and owner dashboard (lib/core/theme.dart, lib/core/widgets/ui.dart).", 15, 600, MUTED), image(1240, 20, 140, 134)]
for i, (n, h) in enumerate([("Cream (background)", CREAM), ("Cream deep", CREAM_DEEP), ("Brown (primary)", BROWN), ("Brown soft", BROWN_SOFT), ("Ink (text)", INK), ("Muted", MUTED), ("Line", LINE), ("Orange (accent)", ORANGE)]):
    ds.append(swatch(40 + i * 170, 140, n, h))
for i, (n, h) in enumerate([("Orange light", ORANGE_LIGHT), ("Orange deep", ORANGE_DEEP), ("Pepperoni red", RED), ("Basil green", BASIL), ("Cheese", CHEESE), ("Chart series 1", S1), ("Chart series 2", S2), ("Chart series 3", S3)]):
    ds.append(swatch(40 + i * 170, 320, n, h))
ds += [
    display(40, 540, "Display · Fredoka 700 — Hot, fresh & made your way.", 34), display(40, 590, "Title · Fredoka 600 — Complete your meal?", 24, weight=600),
    text(40, 630, "Body · Nunito 600 — Pepperoni, sausage, mushrooms, green peppers and red onions.", 16, 600), text(40, 660, "LABEL · NUNITO 800 · TRACKED", 12, 800, MUTED, ls=0.6),
    button(40, 700, 300, "Primary button"), button(360, 700, 300, "Dark button", "dark"), button(680, 700, 300, "Outline button", "outline"),
    pills_row(40, 790, ["Hand-Tossed", "Stuffed Crust", "Thin & Crispy"], "Stuffed Crust", subs=[None, "+$3.00", None], max_w=900)[0],
    tag(560, 800, "POPULAR"), tag(640, 800, "NEW", BASIL), tag(700, 800, "SPICY", "#E0592A"),
    cart_bar(3, "$47.46", 880).replace('x="16"', 'x="1000"', 1),
    pizza(1240, 760, 120, ("pepperoni", "basil"), seed=5, name="Pizza illustration"),
]
screens["00-design-system"] = (1440, 940, "00 Design system", svg_doc(1440, 940, "".join(ds), "00 Design system"))


# ── Write files + one board with every screen ────────────────────────────────
for slug, (w, h, name, doc) in screens.items():
    (OUT / f"{slug}.svg").write_text(doc, encoding="utf-8")

phones = [(s, v) for s, v in screens.items() if v[0] == PHONE_W]
desks = [(s, v) for s, v in screens.items() if v[0] == DESK_W and s != "00-design-system"]
gap, cols = 80, 6
board_w = max(cols * (PHONE_W + gap), 2 * (DESK_W + gap)) + gap
rows_phone = math.ceil(len(phones) / cols)
board_h = 200 + rows_phone * (PHONE_H + 140) + math.ceil(len(desks) / 2) * (DESK_H + 140) + 200
board = [display(gap, 120, "Al’s Pizza — all screens", 64)]
for i, (slug, (w, h, name, doc)) in enumerate(phones):
    x, y = gap + (i % cols) * (PHONE_W + gap), 200 + (i // cols) * (PHONE_H + 140)
    inner = doc.split("<g id=", 1)[1].rsplit("</svg>", 1)[0]
    board.append(text(x, y - 16, name, 22, 800, BROWN_SOFT))
    board.append(f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><g id={inner}</svg>')
y0 = 200 + rows_phone * (PHONE_H + 140)
for i, (slug, (w, h, name, doc)) in enumerate(desks):
    x, y = gap + (i % 2) * (DESK_W + gap), y0 + (i // 2) * (DESK_H + 140)
    inner = doc.split("<g id=", 1)[1].rsplit("</svg>", 1)[0]
    board.append(text(x, y - 16, name, 22, 800, BROWN_SOFT))
    board.append(f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><g id={inner}</svg>')
(OUT / "all-screens.svg").write_text(svg_doc(int(board_w), int(board_h), "".join(board), "All screens", "#EFE6D6"), encoding="utf-8")

print(f"wrote {len(screens)} screens + all-screens.svg to {OUT}")
