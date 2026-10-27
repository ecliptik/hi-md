#!/usr/bin/env python3
"""Generates the `minidisc` and `minidisc.fill` SF Symbols custom-symbol templates.

A line-art MiniDisc after the 💽 emoji: a rounded cartridge outline, the disc as a closed ring
with a hub dot, and the shutter as a solid tab reaching in from the right edge beside the disc.
`minidisc.fill` is the solid cartridge with the disc, hub and shutter knocked out.

`--variant top-shutter` draws the alternative under consideration instead: the shutter as a bar
reaching down from the top edge, where a real MiniDisc's metal shutter sits, with the disc centred
below it. Write it somewhere other than the asset catalog to compare it; the shipped symbol is
the default `side-shutter` variant.

Every weight is built from the same centerlines with the same number of path commands, so SF Symbols
(and actool) can interpolate the Ultralight, Regular and Black sources into all nine weights.
Units are template units at 100 pt, small scale: y up from the baseline while building, flipped to
SVG's y-down when written.

Usage (from the repository root):
    python3 Scripts/Symbols/make_minidisc_symbol.py Minidisc/Assets.xcassets
    python3 Scripts/Symbols/make_minidisc_symbol.py --variant top-shutter /tmp/TopShutter.xcassets
Check the result with Scripts/Symbols/symbol_sheet.swift.
"""
import argparse
import json
import math
import os

CAP = 70.459            # cap height at 100 pt (Capline-S - Baseline-S)
CY = CAP / 2            # symbols are centred on the cap height's midline
SIDEBEARING = 9.5       # square/square.stack keep ~10 units each side at the small scale

# Per-weight parameters. t is the stroke; SF's square is 2.25 / 7.0 / 14.25 at the small scale.
# ring: the disc's centerline radius; ringx: its centre; hub: the hub dot's radius; tableft and
# tabhalf: the shutter's outer left edge and half its outer height.
WEIGHTS = {
    "Ultralight": dict(t=2.25, ring=14.5, ringx=27.5, hub=2.2, tableft=47.5, tabhalf=13.0),
    "Regular":    dict(t=7.0,  ring=13.5, ringx=28.0, hub=3.8, tableft=50.0, tabhalf=12.5),
    "Black":      dict(t=13.0, ring=11.5, ringx=29.5, hub=3.2, tableft=50.5, tabhalf=12.5),
}

# The top-shutter variant. barbottom: the shutter's outer bottom edge; barhalf: half its outer
# width. The disc is centred across the cartridge and between the shutter and the bottom edge.
TOP_SHUTTER_WEIGHTS = {
    "Ultralight": dict(t=2.25, ring=17.0, hub=2.2, barbottom=53.5, barhalf=16.5),
    "Regular":    dict(t=7.0,  ring=14.5, hub=3.8, barbottom=52.5, barhalf=16.5),
    "Black":      dict(t=13.0, ring=11.5, hub=3.2, barbottom=50.5, barhalf=17.5),
}
VARIANTS = ("side-shutter", "top-shutter")

# Cartridge centerline (independent of weight; strokes grow both ways like SF's): a plain rounded
# rectangle, slightly taller than wide like a real MiniDisc, with one corner radius all round.
X0, X1 = 3.5, 66.5
Y0, Y1 = CY - 34.5, CY + 34.5
R_CORNER = 10.5


def v_add(a, b): return (a[0] + b[0], a[1] + b[1])
def v_sub(a, b): return (a[0] - b[0], a[1] - b[1])
def v_mul(a, k): return (a[0] * k, a[1] * k)
def v_len(a): return math.hypot(a[0], a[1])
def v_unit(a):
    n = v_len(a)
    return (a[0] / n, a[1] / n)
def polar(c, r, ang): return (c[0] + r * math.cos(ang), c[1] + r * math.sin(ang))


class Path:
    def __init__(self):
        self.cmds = []

    def move(self, p): self.cmds.append(("M", p))
    def line(self, p): self.cmds.append(("L", p))
    def close(self): self.cmds.append(("Z",))

    def arc(self, c, r, a0, a1, segments):
        """Circular arc from a0 to a1 (radians, y-up; a1 > a0 is counter-clockwise) as cubics."""
        step = (a1 - a0) / segments
        k = 4.0 / 3.0 * math.tan(step / 4.0)
        for i in range(segments):
            s, e = a0 + i * step, a0 + (i + 1) * step
            p0, p3 = polar(c, r, s), polar(c, r, e)
            t0 = (-math.sin(s), math.cos(s))
            t1 = (-math.sin(e), math.cos(e))
            p1 = v_add(p0, v_mul(t0, k * r))
            p2 = v_sub(p3, v_mul(t1, k * r))
            self.cmds.append(("C", p1, p2, p3))


def rounded_polygon_circles(vertices, radii):
    """Corner circles (centre, radius) of a convex polygon (counter-clockwise, y-up) with rounded corners."""
    n = len(vertices)
    out = []
    for i, v in enumerate(vertices):
        a, b = vertices[i - 1], vertices[(i + 1) % n]
        u1, u2 = v_unit(v_sub(a, v)), v_unit(v_sub(b, v))
        bis = v_unit(v_add(u1, u2))
        half = math.acos(max(-1, min(1, u1[0] * u2[0] + u1[1] * u2[1]))) / 2
        out.append((v_add(v, v_mul(bis, radii[i] / math.sin(half))), radii[i]))
    return out


def hull_of_circles(path, circles, offset, reverse=False):
    """Outline of the convex hull of `circles` grown by `offset`, counter-clockwise unless `reverse`."""
    cs = [(c, r + offset) for c, r in circles]
    if reverse:
        cs = cs[::-1]
    n = len(cs)
    tangents = []  # (point on circle i, point on circle i+1)
    for i in range(n):
        (ca, ra), (cb, rb) = cs[i], cs[(i + 1) % n]
        d = v_sub(cb, ca)
        dist = v_len(d)
        u = v_mul(d, 1 / dist)
        right = (u[1], -u[0]) if not reverse else (-u[1], u[0])
        k = (ra - rb) / dist
        nrm = v_add(v_mul(u, k), v_mul(right, math.sqrt(max(0.0, 1 - k * k))))
        tangents.append((v_add(ca, v_mul(nrm, ra)), v_add(cb, v_mul(nrm, rb)), nrm))
    for i in range(n):
        c, r = cs[i]
        _, p_in, n_in = tangents[i - 1]
        p_out, _, n_out = tangents[i]
        a0 = math.atan2(n_in[1], n_in[0])
        a1 = math.atan2(n_out[1], n_out[0])
        if not reverse:
            while a1 < a0: a1 += 2 * math.pi
        else:
            while a1 > a0: a1 -= 2 * math.pi
        if i == 0:
            path.move(p_in)
        else:
            path.line(p_in)
        path.arc(c, r, a0, a1, 1)
    path.close()


def circle(path, c, r, reverse=False):
    a0 = math.pi / 2
    path.move(polar(c, r, a0))
    path.arc(c, r, a0, a0 + (-2 if reverse else 2) * math.pi, 4)
    path.close()


def cartridge_circles():
    return rounded_polygon_circles([(X0, Y0), (X1, Y0), (X1, Y1), (X0, Y1)], [R_CORNER] * 4)


def rounded_rect_circles(x0, x1, half, r_left, r_right):
    """Corner circles of a rectangle (outer edges given), centred on the cap height's midline."""
    return [((x0 + r_left, CY - half + r_left), r_left), ((x1 - r_right, CY - half + r_right), r_right),
            ((x1 - r_right, CY + half - r_right), r_right), ((x0 + r_left, CY + half - r_left), r_left)]


def rect_circles(x0, x1, y0, y1, r_bottom, r_top):
    """Corner circles of a rectangle (outer edges given), counter-clockwise from the bottom left."""
    return [((x0 + r_bottom, y0 + r_bottom), r_bottom), ((x1 - r_bottom, y0 + r_bottom), r_bottom),
            ((x1 - r_top, y1 - r_top), r_top), ((x0 + r_top, y1 - r_top), r_top)]


def build_top_shutter(weight, filled):
    """Outline: cartridge, a solid shutter reaching down from the top edge, and the closed disc
    ring and hub dot centred below it. Fill: the solid cartridge with all three knocked out."""
    p = TOP_SHUTTER_WEIGHTS[weight]
    t = p["t"]
    cx = (X0 + X1) / 2
    inner_bottom = Y0 + t / 2
    c = (cx, (inner_bottom + p["barbottom"]) / 2)
    outer = p["ring"] + t / 2
    assert c[1] + outer < p["barbottom"], "the disc must clear the shutter"
    assert c[1] - outer > inner_bottom, "the disc must clear the cartridge"
    assert cx - outer > X0 + t / 2, "the disc must fit across the cartridge"
    assert p["ring"] - t / 2 > p["hub"], "the hub must sit inside the ring"
    bx0, bx1 = cx - p["barhalf"], cx + p["barhalf"]
    path = Path()
    cart = cartridge_circles()
    hull_of_circles(path, cart, t / 2)
    if not filled:
        hull_of_circles(path, cart, -t / 2, reverse=True)
        # The shutter runs into the cartridge's top edge, so it ends inside that stroke.
        hull_of_circles(path, rect_circles(bx0, bx1, p["barbottom"], Y1, 2.5, 1.0), 0)
        circle(path, c, outer)
        circle(path, c, p["ring"] - t / 2, reverse=True)
        circle(path, c, p["hub"])
    else:
        # Cut out of the solid cartridge, leaving a rim along the top as wide as the outline's stroke.
        hull_of_circles(path, rect_circles(bx0, bx1, p["barbottom"], Y1 - t / 2, 2.5, 2.5), 0, reverse=True)
        circle(path, c, outer, reverse=True)
        circle(path, c, p["ring"] - t / 2)
        circle(path, c, p["hub"], reverse=True)
    return path


def build(weight, filled, variant="side-shutter"):
    """Outline: cartridge, closed disc ring, hub dot, solid shutter reaching in from the right edge.
    Fill: the solid cartridge with the ring, hub and shutter knocked out."""
    if variant == "top-shutter":
        return build_top_shutter(weight, filled)
    p = WEIGHTS[weight]
    t = p["t"]
    c = (p["ringx"], CY)
    assert c[0] + p["ring"] + t / 2 < p["tableft"], "the shutter must clear the disc"
    assert c[0] - p["ring"] - t / 2 > X0 + t / 2, "the disc must clear the cartridge"
    path = Path()
    cart = cartridge_circles()
    hull_of_circles(path, cart, t / 2)
    if not filled:
        hull_of_circles(path, cart, -t / 2, reverse=True)
        circle(path, c, p["ring"] + t / 2)
        circle(path, c, p["ring"] - t / 2, reverse=True)
        circle(path, c, p["hub"])
        # The shutter runs into the cartridge's right edge, so it ends inside that stroke.
        hull_of_circles(path, rounded_rect_circles(p["tableft"], X1, p["tabhalf"], 2.5, 1.0), 0)
    else:
        circle(path, c, p["ring"] + t / 2, reverse=True)
        circle(path, c, p["ring"] - t / 2)
        circle(path, c, p["hub"], reverse=True)
        # Cut out of the solid cartridge, leaving a rim on the right as wide as the outline's stroke.
        hull_of_circles(path, rounded_rect_circles(p["tableft"], X1 - t / 2, p["tabhalf"], 2.5, 2.5), 0,
                        reverse=True)
    return path


def bbox(path):
    xs, ys = [], []
    for cmd in path.cmds:
        for pt in cmd[1:]:
            xs.append(pt[0]); ys.append(pt[1])
    return min(xs), max(xs), min(ys), max(ys)


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def to_svg_d(path, dx):
    """SVG path data relative to (left margin, baseline): x shifted by dx, y flipped."""
    out = []
    for cmd in path.cmds:
        if cmd[0] == "Z":
            out.append("Z")
            continue
        pts = " ".join(f"{fmt(x + dx)} {fmt(-y)}" for x, y in cmd[1:])
        out.append(f"{cmd[0]}{pts}")
    return "".join(out)


COLUMNS = {"Ultralight": 559.711, "Regular": 1449.84, "Black": 2933.4}
ROWS = {"S": 696, "M": 1126, "L": 1556}


def template(name, filled, variant="side-shutter"):
    groups, margins = [], []
    counts = set()
    for weight in ("Black", "Regular", "Ultralight"):
        path = build(weight, filled, variant)
        counts.add(tuple(c[0] for c in path.cmds))
        x0, x1, _, _ = bbox(path)
        width = (x1 - x0) + 2 * SIDEBEARING
        left = COLUMNS[weight] - width / 2
        d = to_svg_d(path, SIDEBEARING - x0)
        groups.append(
            f'  <g id="{weight}-S" transform="matrix(1 0 0 1 {fmt(left)} {ROWS["S"]})">\n'
            f'   <path class="monochrome-0 multicolor-0:tintColor hierarchical-0:primary SFSymbolsPreviewWireframe" d="{d}"/>\n'
            f'  </g>')
        line = 'style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;"'
        margins.append(f'  <line id="right-margin-{weight}-S" {line} x1="{fmt(left + width)}" x2="{fmt(left + width)}" y1="600.785" y2="720.121"/>')
        margins.append(f'  <line id="left-margin-{weight}-S" {line} x1="{fmt(left)}" x2="{fmt(left)}" y1="600.785" y2="720.121"/>')
    assert len(counts) == 1, "weights must share one path structure to interpolate"

    guide = 'style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;"'
    guides = []
    for scale, base in ROWS.items():
        guides.append(f'  <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 {base})">\n'
                      f'   <path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.2315-26.7285L12.4385-26.7285ZM55.1196 0L57.7637 0L30.6382-70.459L29.4326-70.459L29.4326-67.1323Z"/>\n'
                      f'  </g>')
        guides.append(f'  <line id="Baseline-{scale}" {guide} x1="263" x2="3036" y1="{base}" y2="{base}"/>')
        guides.append(f'  <line id="Capline-{scale}" {guide} x1="263" x2="3036" y1="{fmt(base - CAP)}" y2="{fmt(base - CAP)}"/>')

    text = 'style="stroke:none;fill:black;font-family:sans-serif;font-size:13;'
    notes = [
        '  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>',
        '  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="292" y2="292"/>',
        f'  <text {text}font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>',
    ]
    for label, x in [("Ultralight", 559.711), ("Thin", 856.422), ("Light", 1153.13), ("Regular", 1449.84), ("Medium", 1746.56),
                     ("Semibold", 2043.27), ("Bold", 2339.98), ("Heavy", 2636.69), ("Black", 2933.4)]:
        notes.append(f'  <text {text}text-anchor:middle;" transform="matrix(1 0 0 1 {x} 322)">{label}</text>')
    notes += [
        f'  <text {text}" transform="matrix(1 0 0 1 263 726)">Small</text>',
        f'  <text {text}" transform="matrix(1 0 0 1 263 1156)">Medium</text>',
        f'  <text {text}" transform="matrix(1 0 0 1 263 1586)">Large</text>',
        '  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1903" y2="1903"/>',
        f'  <text {text}font-weight:bold;" transform="matrix(1 0 0 1 263 1953)">Design Variations</text>',
        f'  <text {text}" transform="matrix(1 0 0 1 263 1971)">Symbols are supported in up to nine weights and three scales.</text>',
        f'  <text {text}" transform="matrix(1 0 0 1 263 1989)">For optimal layout with text and other symbols, vertically align</text>',
        f'  <text {text}" transform="matrix(1 0 0 1 263 2007)">symbols with the adjacent text.</text>',
        f'  <text id="template-version" {text}text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>',
        f'  <text {text}text-anchor:end;" transform="matrix(1 0 0 1 3036 1951)">Requires Xcode 13 or greater</text>',
        f'  <text id="descriptive-name" {text}text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Generated from {name}</text>',
        f'  <text {text}text-anchor:end;" transform="matrix(1 0 0 1 3036 1987)">Typeset at 100 points</text>',
    ]

    return "\n".join([
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">',
        '<!-- Hi-MD custom symbol. Generated by Scripts/Symbols/make_minidisc_symbol.py; edit the script, not this file. -->',
        '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">',
        ' <style>',
        '.SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}',
        ' </style>',
        ' <g id="Notes">', *notes, ' </g>',
        ' <g id="Guides">', *guides, *margins, ' </g>',
        ' <g id="Symbols">', *groups, ' </g>',
        '</svg>',
        '',
    ])


def write_symbolset(out_dir, name, filled, variant="side-shutter"):
    folder = os.path.join(out_dir, f"{name}.symbolset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{name}.svg"), "w") as f:
        f.write(template(name, filled, variant))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        f.write('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n  "symbols" : [\n    {\n'
                f'      "filename" : "{name}.svg",\n      "idiom" : "universal"\n    }}\n  ]\n}}\n')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Writes the minidisc and minidisc.fill symbol sets.")
    parser.add_argument("out_dir", help="the asset catalog (.xcassets) to write the .symbolset folders into")
    parser.add_argument("--variant", choices=VARIANTS, default="side-shutter",
                        help="side-shutter (shipped) or top-shutter (the alternative being compared)")
    args = parser.parse_args()
    # A new scratch catalog needs its own Contents.json before actool will compile it.
    catalog_info = os.path.join(args.out_dir, "Contents.json")
    if args.out_dir.rstrip("/").endswith(".xcassets") and not os.path.exists(catalog_info):
        os.makedirs(args.out_dir, exist_ok=True)
        with open(catalog_info, "w") as f:
            json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
            f.write("\n")
    write_symbolset(args.out_dir, "minidisc", filled=False, variant=args.variant)
    write_symbolset(args.out_dir, "minidisc.fill", filled=True, variant=args.variant)
