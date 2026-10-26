#!/usr/bin/env python3
"""Builds Minidisc Gold, the original classic-format skin bundled for Winamp mode.

Every pixel is drawn here from scratch (gold on near-black), at the sizes of the Winamp 2 skin
format, so the skin can be rebuilt and changed without any third-party artwork.

    python3 Scripts/Winamp/make_minidisc_gold.py [--preview contact-sheet.png]

Writes Minidisc/Resources/Winamp/MinidiscGold.wsz. Needs Pillow. The archive is reproducible:
entries are sorted and carry a fixed timestamp. BMPs are deflated, text files stored.
"""

import argparse
import io
import os
import random
import zipfile

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.join(ROOT, "Minidisc", "Resources", "Winamp", "MinidiscGold.wsz")

# Palette ---------------------------------------------------------------------------------------

INK = (14, 12, 9)            # window body
INK_DEEP = (7, 6, 4)         # shadows, grooves
PANEL = (28, 23, 15)         # raised faces
PANEL_DOWN = (18, 15, 10)    # pressed faces
BEVEL_HI = (92, 74, 38)      # top-left bevel
BEVEL_LO = (4, 3, 2)         # bottom-right bevel
LCD = (9, 8, 5)              # display background
LCD_GHOST = (36, 29, 14)     # unlit LCD segments
GOLD = (217, 169, 58)        # main gold
GOLD_HI = (248, 216, 128)    # highlight gold
GOLD_DIM = (140, 104, 30)    # labels, inactive
GOLD_DEEP = (84, 61, 18)     # rules, borders


def new(width, height, color=INK):
    return Image.new("RGB", (width, height), color)


def fill(img, x, y, w, h, color):
    if w > 0 and h > 0:
        ImageDraw.Draw(img).rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def bevel(img, x, y, w, h, face=PANEL, light=BEVEL_HI, dark=BEVEL_LO, sunken=False):
    """A 1-pixel bevelled box. Sunken boxes swap the light and dark edges."""
    if sunken:
        light, dark = dark, light
    fill(img, x, y, w, h, face)
    fill(img, x, y, w, 1, light)
    fill(img, x, y, 1, h, light)
    fill(img, x, y + h - 1, w, 1, dark)
    fill(img, x + w - 1, y, 1, h, dark)


def outline(img, x, y, w, h, color):
    fill(img, x, y, w, 1, color)
    fill(img, x, y + h - 1, w, 1, color)
    fill(img, x, y, 1, h, color)
    fill(img, x + w - 1, y, 1, h, color)


def pattern(img, x, y, rows, color):
    for dy, row in enumerate(rows):
        for dx, cell in enumerate(row):
            if cell == "#":
                img.putpixel((x + dx, y + dy), color)


# A 4×5 pixel font drawn for this skin. Each glyph sits in the top-left of a 5×6 text cell.
FONT = {
    "A": [".##.", "#..#", "####", "#..#", "#..#"],
    "B": ["###.", "#..#", "###.", "#..#", "###."],
    "C": [".###", "#...", "#...", "#...", ".###"],
    "D": ["###.", "#..#", "#..#", "#..#", "###."],
    "E": ["####", "#...", "###.", "#...", "####"],
    "F": ["####", "#...", "###.", "#...", "#..."],
    "G": [".###", "#...", "#.##", "#..#", ".###"],
    "H": ["#..#", "#..#", "####", "#..#", "#..#"],
    "I": ["###.", ".#..", ".#..", ".#..", "###."],
    "J": ["...#", "...#", "...#", "#..#", ".##."],
    "K": ["#..#", "#.#.", "##..", "#.#.", "#..#"],
    "L": ["#...", "#...", "#...", "#...", "####"],
    "M": ["#..#", "####", "####", "#..#", "#..#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "O": [".##.", "#..#", "#..#", "#..#", ".##."],
    "P": ["###.", "#..#", "###.", "#...", "#..."],
    "Q": [".##.", "#..#", "#..#", "#.#.", ".#.#"],
    "R": ["###.", "#..#", "###.", "#.#.", "#..#"],
    "S": [".###", "#...", ".##.", "...#", "###."],
    "T": ["###.", ".#..", ".#..", ".#..", ".#.."],
    "U": ["#..#", "#..#", "#..#", "#..#", ".##."],
    "V": ["#.#.", "#.#.", "#.#.", "#.#.", ".#.."],
    "W": ["#..#", "#..#", "####", "####", "#..#"],
    "X": ["#..#", "#..#", ".##.", "#..#", "#..#"],
    "Y": ["#.#.", "#.#.", ".#..", ".#..", ".#.."],
    "Z": ["####", "..#.", ".#..", "#...", "####"],
    "0": [".##.", "#.##", "##.#", "#..#", ".##."],
    "1": [".#..", "##..", ".#..", ".#..", "###."],
    "2": ["###.", "...#", ".##.", "#...", "####"],
    "3": ["###.", "...#", ".##.", "...#", "###."],
    "4": ["#..#", "#..#", "####", "...#", "...#"],
    "5": ["####", "#...", "###.", "...#", "###."],
    "6": [".##.", "#...", "###.", "#..#", ".##."],
    "7": ["####", "...#", "..#.", ".#..", ".#.."],
    "8": [".##.", "#..#", ".##.", "#..#", ".##."],
    "9": [".##.", "#..#", ".###", "...#", ".##."],
    '"': ["#.#.", "#.#.", "....", "....", "...."],
    "@": [".##.", "#.##", "#.##", "#...", ".##."],
    " ": ["....", "....", "....", "....", "...."],
    "…": ["....", "....", "....", "....", "#.#."],
    ".": ["....", "....", "....", "....", ".#.."],
    ":": ["....", ".#..", "....", ".#..", "...."],
    "(": ["..#.", ".#..", ".#..", ".#..", "..#."],
    ")": [".#..", "..#.", "..#.", "..#.", ".#.."],
    "-": ["....", "....", "###.", "....", "...."],
    "'": [".#..", ".#..", "....", "....", "...."],
    "!": [".#..", ".#..", ".#..", "....", ".#.."],
    "_": ["....", "....", "....", "....", "####"],
    "+": ["....", ".#..", "###.", ".#..", "...."],
    "\\": ["#...", "#...", ".#..", "..#.", "..#."],
    "/": ["..#.", "..#.", ".#..", "#...", "#..."],
    "[": ["##..", "#...", "#...", "#...", "##.."],
    "]": ["##..", ".#..", ".#..", ".#..", "##.."],
    "^": [".#..", "#.#.", "....", "....", "...."],
    "&": [".#..", "#.#.", ".#..", "#.#.", ".#.#"],
    "%": ["#..#", "..#.", ".#..", "#...", "#..#"],
    ",": ["....", "....", "....", ".#..", "#..."],
    "=": ["....", "###.", "....", "###.", "...."],
    "$": [".###", "##..", ".##.", "..##", "###."],
    "#": ["#.#.", "####", "#.#.", "####", "#.#."],
    "Å": [".##.", ".##.", "#..#", "####", "#..#"],
    "Ö": ["#..#", ".##.", "#..#", "#..#", ".##."],
    "Ä": ["#..#", ".##.", "#..#", "####", "#..#"],
    "?": ["###.", "...#", ".##.", "....", ".#.."],
    "*": ["....", "#.#.", ".#..", "#.#.", "...."],
}

# The text.bmp grid: row, then characters by column (positions match the classic format).
TEXT_ROWS = [
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ\"@   ",
    "0123456789….:()-'!_+\\/[]^&%,=$#",
    "ÅÖÄ?*                          ",
]


def text(img, x, y, string, color, spacing=5):
    for index, char in enumerate(string.upper()):
        pattern(img, x + index * spacing, y, FONT.get(char, FONT[" "]), color)


def text_width(string, spacing=5):
    return len(string) * spacing - 1


def text_centered(img, x, y, w, string, color):
    text(img, x + (w - text_width(string)) // 2, y, string, color)


def triangle_right(img, x, y, height, color):
    half = height // 2
    for row in range(height):
        width = half + 1 - abs(row - half)
        fill(img, x, y + row, width, 1, color)


def triangle_left(img, x, y, height, color):
    half = height // 2
    for row in range(height):
        width = half + 1 - abs(row - half)
        fill(img, x + half + 1 - width, y + row, width, 1, color)


def triangle_up(img, x, y, width, color):
    rows = (width + 1) // 2
    for row in range(rows):
        fill(img, x + rows - 1 - row, y + row, 2 * row + 1, 1, color)


def brushed(img, x, y, w, h, base, seed):
    """A faint horizontal grain so large panels aren't flat."""
    rng = random.Random(seed)
    for row in range(h):
        shade = rng.randint(-2, 2)
        color = tuple(max(0, min(255, c + shade)) for c in base)
        fill(img, x, y + row, w, 1, color)


# main.bmp --------------------------------------------------------------------------------------

def disc_logo(img, x, y, color, hub):
    """A small MiniDisc cartridge: rounded square, shutter and hub."""
    size = 18
    fill(img, x + 1, y, size - 2, 1, color)
    fill(img, x + 1, y + size - 1, size - 2, 1, color)
    fill(img, x, y + 1, 1, size - 2, color)
    fill(img, x + size - 1, y + 1, 1, size - 2, color)
    fill(img, x + 1, y + 1, size - 2, size - 2, INK_DEEP)
    outline(img, x + 3, y + 3, 7, 12, GOLD_DEEP)     # shutter
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if 5 <= dx * dx + dy * dy <= 12:
                img.putpixel((x + 12 + dx, y + 9 + dy), color)
    fill(img, x + 12, y + 9, 1, 1, hub)


def make_main():
    img = new(275, 116)
    brushed(img, 0, 0, 275, 116, INK, seed=1)
    outline(img, 0, 0, 275, 116, GOLD_DEEP)
    fill(img, 1, 1, 273, 1, BEVEL_HI)
    fill(img, 1, 114, 273, 1, BEVEL_LO)
    # Title bar strip, normally covered by titlebar.bmp.
    fill(img, 1, 1, 273, 13, PANEL)

    # Time and visualiser display.
    bevel(img, 9, 20, 97, 46, face=LCD, sunken=True)
    outline(img, 10, 21, 95, 44, GOLD_DEEP)
    for gx in range(24, 100, 4):          # faint dot grid under the visualiser
        for gy in range(44, 59, 4):
            img.putpixel((gx, gy), LCD_GHOST)
    # The time colon belongs to the background; the digits are drawn either side of it.
    fill(img, 72, 29, 2, 2, GOLD)
    fill(img, 72, 34, 2, 2, GOLD)

    # Title, bitrate and sample-rate boxes.
    bevel(img, 109, 24, 157, 12, face=LCD, sunken=True)
    bevel(img, 109, 41, 18, 10, face=LCD, sunken=True)
    text(img, 130, 43, "KBPS", GOLD_DIM)
    bevel(img, 154, 41, 14, 10, face=LCD, sunken=True)
    text(img, 171, 43, "KHZ", GOLD_DIM)

    # Seek bar well and the transport plate.
    bevel(img, 15, 71, 250, 12, face=INK_DEEP, sunken=True)
    fill(img, 9, 85, 257, 1, GOLD_DEEP)
    bevel(img, 14, 86, 147, 22, face=INK_DEEP, sunken=True)
    bevel(img, 162, 87, 79, 19, face=INK_DEEP, sunken=True)

    disc_logo(img, 247, 88, GOLD, GOLD_HI)
    text(img, 9, 109, "MINIDISC GOLD", GOLD_DEEP)
    return img


# titlebar.bmp ----------------------------------------------------------------------------------

def title_strip(img, x, y, active, label="MINIDISC", width=275, height=14):
    face = PANEL if active else PANEL_DOWN
    rule = GOLD if active else GOLD_DEEP
    ink = GOLD_HI if active else GOLD_DIM
    fill(img, x, y, width, height, face)
    fill(img, x, y, width, 1, BEVEL_HI if active else GOLD_DEEP)
    fill(img, x, y + height - 1, width, 1, BEVEL_LO)
    label_width = text_width(label) + 8
    label_x = x + (width - label_width) // 2
    # Double gold rules either side of the label, clear of the corner buttons.
    for rule_y in (y + 5, y + 8):
        fill(img, x + 18, rule_y, label_x - x - 22, 1, rule)
        fill(img, label_x + label_width + 4, rule_y, x + width - 36 - (label_x + label_width + 4), 1, rule)
    text(img, label_x + 4, y + 4, label, ink)


def small_button(img, x, y, glyph, pressed):
    bevel(img, x, y, 9, 9, face=PANEL_DOWN if pressed else PANEL, sunken=pressed)
    pattern(img, x + 2 + (1 if pressed else 0), y + 2 + (1 if pressed else 0), glyph, GOLD_HI if pressed else GOLD)


GLYPH_OPTIONS = ["#####", ".....", "#####", ".....", "....."]
GLYPH_MINIMIZE = [".....", ".....", ".....", ".....", "#####"]
GLYPH_CLOSE = ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"]
GLYPH_SHADE = ["#####", "#...#", "#####", ".....", "....."]
GLYPH_UNSHADE = ["#####", "#...#", "#...#", "#...#", "#####"]


SHADE_ICONS = [
    (169, ["#..#", "#.##", "####", "#.##", "#..#"]),        # previous
    (178, ["#...", "##..", "###.", "##..", "#..."]),        # play
    (188, ["##.##", "##.##", "##.##", "##.##", "##.##"]),   # pause
    (198, ["####", "####", "####", "####", "...."]),        # stop
    (207, ["#..#", "##.#", "####", "##.#", "#..#"]),        # next
    (216, ["..#..", ".###.", "#####", ".....", "#####"]),   # eject
]


def shade_bar(img, x, y, active):
    face = PANEL if active else PANEL_DOWN
    fill(img, x, y, 275, 14, face)
    fill(img, x, y, 275, 1, BEVEL_HI if active else GOLD_DEEP)
    fill(img, x, y + 13, 275, 1, BEVEL_LO)
    rule = GOLD if active else GOLD_DEEP
    for rule_y in (y + 5, y + 8):
        fill(img, x + 18, rule_y, 55, 1, rule)
    text(img, x + 80, y + 4, "MD", GOLD_HI if active else GOLD_DIM)
    bevel(img, x + 122, y + 2, 36, 10, face=LCD, sunken=True)
    for icon_x, glyph in SHADE_ICONS:
        pattern(img, x + icon_x + 1, y + 4, glyph, GOLD if active else GOLD_DIM)
    bevel(img, x + 225, y + 3, 19, 9, face=INK_DEEP, sunken=True)


def make_titlebar():
    img = new(344, 87, INK_DEEP)
    for col, glyph in enumerate([GLYPH_OPTIONS, GLYPH_MINIMIZE, GLYPH_CLOSE]):
        small_button(img, col * 9, 0, glyph, pressed=False)
        small_button(img, col * 9, 9, glyph, pressed=True)
    small_button(img, 0, 18, GLYPH_SHADE, pressed=False)
    small_button(img, 9, 18, GLYPH_SHADE, pressed=True)
    small_button(img, 0, 27, GLYPH_UNSHADE, pressed=False)
    small_button(img, 9, 27, GLYPH_UNSHADE, pressed=True)

    title_strip(img, 27, 0, active=True)
    title_strip(img, 27, 15, active=False)
    # Windowshade bars carry their own small display: the time at x 125, the small transport's
    # icons at 169-224 and the position slot at 226-243 (positions in the 275-wide bar).
    for y, active in ((29, True), (42, False)):
        shade_bar(img, 27, y, active)
    title_strip(img, 27, 57, active=True, label="MINIDISC GOLD")
    title_strip(img, 27, 72, active=False, label="MINIDISC GOLD")

    # Shade-mode position bar: background and three thumb states.
    bevel(img, 0, 36, 17, 7, face=INK_DEEP, sunken=True)
    fill(img, 17, 36, 3, 7, GOLD_DIM)
    fill(img, 20, 36, 3, 7, GOLD)
    fill(img, 23, 36, 3, 7, GOLD_DIM)

    # Clutter bar, enabled and disabled: O A I D V letters stacked down a narrow strip.
    for x, ink in ((304, GOLD_DIM), (312, GOLD_DEEP)):
        bevel(img, x, 0, 8, 43, face=PANEL)
        for index, letter in enumerate("OAIDV"):
            pattern(img, x + 2, 3 + index * 8, FONT[letter], ink)

    # Each letter lit, for while it is pressed or its option is on: the bar's rows for that
    # letter, sunken, with the letter in highlight gold. (row in the bar, height, sprite x, sprite y)
    lit = {PANEL: PANEL_DOWN, GOLD_DIM: GOLD_HI, BEVEL_HI: BEVEL_LO, BEVEL_LO: BEVEL_HI}
    for top, height, sx, sy in ((3, 8, 304, 47), (11, 7, 312, 55), (18, 7, 320, 62),
                                (25, 8, 328, 69), (33, 7, 336, 77)):
        for dy in range(height):
            for dx in range(8):
                color = img.getpixel((304 + dx, top + dy))
                img.putpixel((sx + dx, sy + dy), lit.get(color, color))
    return img


# cbuttons.bmp ----------------------------------------------------------------------------------

def transport_button(img, x, y, w, h, icon, pressed):
    bevel(img, x, y, w, h, face=PANEL_DOWN if pressed else PANEL, sunken=pressed)
    offset = 1 if pressed else 0
    icon(img, x + offset, y + offset, GOLD_HI if pressed else GOLD)


def icon_previous(img, x, y, color):
    fill(img, x + 6, y + 6, 2, 7, color)
    triangle_left(img, x + 8, y + 6, 7, color)
    triangle_left(img, x + 12, y + 6, 7, color)


def icon_play(img, x, y, color):
    triangle_right(img, x + 9, y + 5, 9, color)


def icon_pause(img, x, y, color):
    fill(img, x + 8, y + 6, 3, 7, color)
    fill(img, x + 13, y + 6, 3, 7, color)


def icon_stop(img, x, y, color):
    fill(img, x + 8, y + 6, 7, 7, color)


def icon_next(img, x, y, color):
    triangle_right(img, x + 6, y + 6, 7, color)
    triangle_right(img, x + 10, y + 6, 7, color)
    fill(img, x + 14, y + 6, 2, 7, color)


def icon_eject(img, x, y, color):
    triangle_up(img, x + 6, y + 4, 9, color)
    fill(img, x + 6, y + 10, 9, 2, color)


def make_cbuttons():
    img = new(136, 36, INK_DEEP)
    buttons = [(0, 23, 18, icon_previous), (23, 23, 18, icon_play), (46, 23, 18, icon_pause),
               (69, 23, 18, icon_stop), (92, 22, 18, icon_next), (114, 22, 16, icon_eject)]
    for x, w, h, icon in buttons:
        transport_button(img, x, 0, w, h, icon, pressed=False)
        transport_button(img, x, h, w, h, icon, pressed=True)
    return img


# posbar.bmp ------------------------------------------------------------------------------------

def seek_thumb(img, x, pressed):
    face = GOLD_HI if pressed else GOLD
    bevel(img, x, 0, 29, 10, face=face, light=GOLD_HI, dark=GOLD_DEEP)
    for gx in (11, 14, 17):
        fill(img, x + gx, 3, 1, 4, GOLD_DEEP)


def make_posbar():
    img = new(307, 10, INK_DEEP)
    bevel(img, 0, 0, 248, 10, face=INK_DEEP, sunken=True)
    fill(img, 2, 4, 244, 2, LCD_GHOST)
    for tick in range(2, 247, 31):
        fill(img, tick, 3, 1, 4, GOLD_DEEP)
    seek_thumb(img, 248, pressed=False)
    seek_thumb(img, 278, pressed=True)
    return img


# volume.bmp and balance.bmp --------------------------------------------------------------------

def blend(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def slider_thumb(img, x, y, pressed):
    face = GOLD_HI if pressed else GOLD
    bevel(img, x, y, 14, 11, face=face, light=GOLD_HI, dark=GOLD_DEEP)
    fill(img, x + 6, y + 3, 2, 5, GOLD_DEEP)


def make_volume():
    img = new(68, 433, INK_DEEP)
    for frame in range(28):
        y = frame * 15
        t = frame / 27
        bevel(img, 0, y, 68, 13, face=INK_DEEP, sunken=True)
        fill(img, 2, y + 5, 64, 3, LCD_GHOST)
        fill(img, 2, y + 5, 1 + int(round(63 * t)), 3, blend(GOLD_DEEP, GOLD_HI, t))
    slider_thumb(img, 15, 422, pressed=False)
    slider_thumb(img, 0, 422, pressed=True)
    return img


def make_balance():
    img = new(47, 433, INK_DEEP)
    for frame in range(28):
        y = frame * 15
        t = frame / 27
        bevel(img, 9, y, 38, 13, face=INK_DEEP, sunken=True)
        fill(img, 11, y + 5, 34, 3, LCD_GHOST)
        reach = int(round(16 * t))
        color = blend(GOLD_DIM, GOLD_HI, t)
        fill(img, 28 - reach, y + 5, reach * 2 + 1, 3, color)
        fill(img, 28, y + 4, 1, 5, GOLD)            # centre mark
    slider_thumb(img, 15, 422, pressed=False)
    slider_thumb(img, 0, 422, pressed=True)
    return img


# numbers.bmp and nums_ex.bmp -------------------------------------------------------------------

# Seven-segment digits in a 9×13 cell: a top, b upper right, c lower right, d bottom,
# e lower left, f upper left, g middle. Rows 0–1, 5–6 and 10–11 hold the bars; row 12 is blank.
SEGMENTS = {
    "a": (2, 0, 5, 2), "b": (7, 2, 2, 3), "c": (7, 7, 2, 3), "d": (2, 10, 5, 2),
    "e": (0, 7, 2, 3), "f": (0, 2, 2, 3), "g": (2, 5, 5, 2),
}
DIGIT_SEGMENTS = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg"]


def seven_segment(img, x, lit):
    for name, (sx, sy, w, h) in SEGMENTS.items():
        color = GOLD if name in lit else LCD_GHOST
        fill(img, x + sx, sy, w, h, color)
        if name in lit and h == 2:
            fill(img, x + sx, sy, w, 1, GOLD_HI)    # bright top edge on lit bars


def make_numbers(extended):
    width = 108 if extended else 99
    img = new(width, 13, LCD)
    for digit, lit in enumerate(DIGIT_SEGMENTS):
        seven_segment(img, digit * 9, lit)
    seven_segment(img, 90, "")                       # blank
    if extended:
        seven_segment(img, 99, "g")                  # minus
    return img


# text.bmp --------------------------------------------------------------------------------------

def make_text():
    img = new(155, 18, LCD)
    for row, chars in enumerate(TEXT_ROWS):
        for col, char in enumerate(chars):
            pattern(img, col * 5, row * 6, FONT.get(char, FONT[" "]), GOLD_HI)
    return img


# playpaus.bmp ----------------------------------------------------------------------------------

def make_playpaus():
    img = new(42, 9, LCD)
    triangle_right(img, 2, 1, 7, GOLD_HI)
    fill(img, 11, 1, 2, 7, GOLD)
    fill(img, 14, 1, 2, 7, GOLD)
    fill(img, 20, 2, 5, 5, GOLD_DIM)
    fill(img, 37, 1, 1, 7, LCD_GHOST)                # not working
    fill(img, 40, 1, 1, 7, GOLD_HI)                  # working
    return img


# monoster.bmp ----------------------------------------------------------------------------------

def make_monoster():
    img = new(58, 24, INK)
    for y, ink in ((0, GOLD_HI), (12, LCD_GHOST)):
        bevel(img, 0, y, 29, 12, face=LCD, sunken=True)
        text_centered(img, 0, y + 3, 29, "STEREO", ink)
        bevel(img, 29, y, 27, 12, face=LCD, sunken=True)
        text_centered(img, 29, y + 3, 27, "MONO", ink)
    return img


# shufrep.bmp -----------------------------------------------------------------------------------

def toggle_button(img, x, y, w, h, label, on, pressed):
    bevel(img, x, y, w, h, face=PANEL_DOWN if pressed else PANEL, sunken=pressed)
    offset = 1 if pressed else 0
    led = GOLD_HI if on else LCD_GHOST
    fill(img, x + 3 + offset, y + h // 2 - 1 + offset, 3, 3, led)
    ink = GOLD_HI if on else GOLD_DIM
    text(img, x + 8 + offset, y + (h - 5) // 2 + offset, label, ink)


def make_shufrep():
    img = new(92, 85, INK_DEEP)
    for row, (on, pressed) in enumerate(((False, False), (False, True), (True, False), (True, True))):
        toggle_button(img, 0, row * 15, 28, 15, "REP", on, pressed)
        toggle_button(img, 28, row * 15, 47, 15, "SHUFFLE", on, pressed)
    for y, on in ((61, False), (73, True)):
        toggle_button(img, 0, y, 23, 12, "EQ", on, pressed=False)
        toggle_button(img, 23, y, 23, 12, "PL", on, pressed=False)
        toggle_button(img, 46, y, 23, 12, "EQ", on, pressed=True)
        toggle_button(img, 69, y, 23, 12, "PL", on, pressed=True)
    return img


# eqmain.bmp ------------------------------------------------------------------------------------

EQ_SLIDERS = [21] + [78 + band * 18 for band in range(10)]
# Minidisc's equaliser bands: each Winamp slider drives the engine band in the same position.
EQ_LABELS = ["PRE", "32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]


def eq_slider_fill(img, x, y, frame):
    """A 14×63 slider well. Frame 0 is −12 dB and frame 27 is +12 dB; the bar grows from 0 dB."""
    bevel(img, x, y, 14, 63, face=INK_DEEP, sunken=True)
    fill(img, x + 6, y + 2, 2, 59, LCD_GHOST)
    centre = y + 31
    level = int(round((frame - 13.5) / 13.5 * 29))
    color = blend(GOLD_DEEP, GOLD_HI, frame / 27)
    if level >= 0:
        fill(img, x + 6, centre - level, 2, level + 1, color)
    else:
        fill(img, x + 6, centre, 2, -level + 1, color)
    fill(img, x + 3, centre, 8, 1, GOLD_DEEP)


def make_eqmain():
    img = new(275, 315, INK_DEEP)
    body = new(275, 116)
    brushed(body, 0, 0, 275, 116, INK, seed=2)
    outline(body, 0, 0, 275, 116, GOLD_DEEP)
    fill(body, 1, 1, 273, 13, PANEL)
    for x in EQ_SLIDERS:
        bevel(body, x - 1, 37, 16, 65, face=INK_DEEP, sunken=True)
    for x, label in zip(EQ_SLIDERS, EQ_LABELS):
        text_centered(body, x - 3, 105, 20, label, GOLD_DIM)
    text(body, 44, 38, "+12", GOLD_DIM)
    text(body, 49, 67, "0", GOLD_DIM)
    text(body, 44, 96, "-12", GOLD_DIM)
    fill(body, 62, 70, 12, 1, GOLD_DEEP)
    bevel(body, 85, 16, 115, 21, face=LCD, sunken=True)
    img.paste(body, (0, 0))

    small_button(img, 0, 116, GLYPH_CLOSE, pressed=False)
    small_button(img, 0, 125, GLYPH_CLOSE, pressed=True)
    for x, label, on, pressed in ((10, "ON", False, False), (128, "ON", False, True),
                                  (69, "ON", True, False), (187, "ON", True, True)):
        toggle_button(img, x, 119, 26, 12, label, on, pressed)
    for x, label, on, pressed in ((36, "AUTO", False, False), (154, "AUTO", False, True),
                                  (95, "AUTO", True, False), (213, "AUTO", True, True)):
        toggle_button(img, x, 119, 32, 12, label, on, pressed)

    for y, active in ((134, True), (149, False)):
        title_strip(img, 0, y, active=active, label="EQUALIZER")
        small_button(img, 254, y + 3, GLYPH_SHADE, pressed=False)
        small_button(img, 264, y + 3, GLYPH_CLOSE, pressed=False)

    for frame in range(28):
        eq_slider_fill(img, 13 + (frame % 14) * 15, 164 + (frame // 14) * 65, frame)
    for y, pressed in ((164, False), (176, True)):
        face = GOLD_HI if pressed else GOLD
        bevel(img, 0, y, 11, 11, face=face, light=GOLD_HI, dark=GOLD_DEEP)
        fill(img, 2, y + 5, 7, 1, GOLD_DEEP)
    for y, pressed in ((164, False), (176, True)):
        bevel(img, 224, y, 44, 12, face=PANEL_DOWN if pressed else PANEL, sunken=pressed)
        text_centered(img, 224 + (1 if pressed else 0), y + 4, 44, "PRESETS", GOLD_HI if pressed else GOLD)

    bevel(img, 0, 294, 113, 19, face=LCD, sunken=True)
    fill(img, 1, 303, 111, 1, LCD_GHOST)
    for row in range(19):
        img.putpixel((115, 294 + row), blend(GOLD_HI, GOLD_DEEP, row / 18))
    fill(img, 0, 314, 113, 1, GOLD_DIM)
    return img


def make_eq_ex():
    """The equaliser's windowshade bar, active and inactive, and its pressed buttons."""
    img = new(275, 56, INK_DEEP)
    for y, active in ((0, True), (15, False)):
        title_strip(img, 0, y, active=active, label="EQUALIZER")
        small_button(img, 254, y + 3, GLYPH_UNSHADE, pressed=False)
        small_button(img, 264, y + 3, GLYPH_CLOSE, pressed=False)
    for x in (1, 4, 7, 11, 14, 17):
        fill(img, x, 30, 3, 7, GOLD)
    small_button(img, 1, 38, GLYPH_UNSHADE, pressed=True)   # unshade, pressed (shade bar)
    small_button(img, 1, 47, GLYPH_SHADE, pressed=True)     # shade, pressed (full window)
    small_button(img, 11, 38, GLYPH_CLOSE, pressed=False)
    small_button(img, 11, 47, GLYPH_CLOSE, pressed=True)
    return img


# pledit.bmp ------------------------------------------------------------------------------------

def playlist_top(img, x, y, w, active, label=None):
    face = PANEL if active else PANEL_DOWN
    rule = GOLD if active else GOLD_DEEP
    fill(img, x, y, w, 20, face)
    fill(img, x, y, w, 1, BEVEL_HI if active else GOLD_DEEP)
    fill(img, x, y + 19, w, 1, BEVEL_LO)
    if label:
        text_centered(img, x, y + 8, w, label, GOLD_HI if active else GOLD_DIM)
    else:
        fill(img, x, y + 8, w, 1, rule)
        fill(img, x, y + 11, w, 1, rule)


def playlist_button(img, x, y, label, pressed):
    bevel(img, x, y, 22, 18, face=PANEL_DOWN if pressed else PANEL, sunken=pressed)
    offset = 1 if pressed else 0
    text_centered(img, x + offset, y + 7 + offset, 22, label, GOLD_HI if pressed else GOLD)


def make_pledit():
    img = new(280, 186, INK_DEEP)
    for y, active in ((0, True), (21, False)):
        playlist_top(img, 0, y, 25, active)
        playlist_top(img, 26, y, 100, active, label="PLAYLIST")
        playlist_top(img, 127, y, 25, active)
        playlist_top(img, 153, y, 25, active)
        small_button(img, 153 + 3, y + 5, GLYPH_SHADE, pressed=False)
        small_button(img, 153 + 13, y + 5, GLYPH_CLOSE, pressed=False)
    playlist_top(img, 179, 0, 25, True)              # bottom tile sits over this column below
    small_button(img, 52, 42, GLYPH_CLOSE, pressed=True)
    small_button(img, 62, 42, GLYPH_SHADE, pressed=True)

    # Side tiles.
    fill(img, 0, 42, 12, 29, PANEL)
    fill(img, 0, 42, 1, 29, BEVEL_HI)
    fill(img, 10, 42, 1, 29, GOLD_DEEP)
    fill(img, 31, 42, 20, 29, PANEL)
    fill(img, 31, 42, 1, 29, GOLD_DEEP)
    fill(img, 50, 42, 1, 29, BEVEL_LO)
    bevel(img, 36, 42, 10, 29, face=INK_DEEP, sunken=True)
    for x, pressed in ((52, False), (61, True)):
        face = GOLD_HI if pressed else GOLD
        bevel(img, x, 53, 8, 18, face=face, light=GOLD_HI, dark=GOLD_DEEP)
        for gy in (60, 62, 64):
            fill(img, x + 2, gy, 4, 1, GOLD_DEEP)

    # Shade-mode pieces: the left end at (72, 42), a tile at (72, 57), and the right end with
    # the unshade and close buttons, active at (99, 42) and inactive at (99, 57).
    for y, piece_w in ((42, 25), (57, 25)):
        fill(img, 72, y, piece_w, 14, PANEL)
        fill(img, 72, y, piece_w, 1, BEVEL_HI)
        fill(img, 72, y + 13, piece_w, 1, BEVEL_LO)
    fill(img, 72, 42, 1, 14, BEVEL_HI)
    for y, active in ((42, True), (57, False)):
        face = PANEL if active else PANEL_DOWN
        fill(img, 99, y, 50, 14, face)
        fill(img, 99, y, 50, 1, BEVEL_HI if active else GOLD_DEEP)
        fill(img, 99, y + 13, 50, 1, BEVEL_LO)
        bevel(img, 99 + 2, y + 2, 28, 10, face=LCD, sunken=True)
        small_button(img, 99 + 29, y + 3, GLYPH_UNSHADE, pressed=False)
        small_button(img, 99 + 39, y + 3, GLYPH_CLOSE, pressed=False)
    small_button(img, 150, 42, GLYPH_UNSHADE, pressed=True)

    # Bottom bar: buttons on the left, time and LIST on the right.
    bottom_left = new(125, 38, PANEL)
    fill(bottom_left, 0, 0, 125, 1, GOLD_DEEP)
    for index, label in enumerate(["ADD", "REM", "SEL", "MISC"]):
        bevel(bottom_left, 11 + index * 29, 10, 25, 18, face=PANEL, light=BEVEL_HI, dark=BEVEL_LO)
        text_centered(bottom_left, 11 + index * 29, 17, 25, label, GOLD)
    img.paste(bottom_left, (0, 72))

    bottom_right = new(150, 38, PANEL)
    fill(bottom_right, 0, 0, 150, 1, GOLD_DEEP)
    bevel(bottom_right, 7, 6, 90, 12, face=LCD, sunken=True)
    for index, icon in enumerate(["#.#", "##.", "#.#", "###", "..#", "###"]):
        fill(bottom_right, 8 + index * 9, 23, 6, 6, PANEL_DOWN)
        fill(bottom_right, 10 + index * 9, 25, 2, 2, GOLD_DIM)
    bevel(bottom_right, 103, 10, 25, 18, face=PANEL)
    text_centered(bottom_right, 103, 17, 25, "LIST", GOLD)
    for step in range(4):                            # resize grip
        fill(bottom_right, 146 - step * 3, 34, 1, 1, GOLD_DIM)
        fill(bottom_right, 146, 34 - step * 3, 1, 1, GOLD_DIM)
    img.paste(bottom_right, (126, 72))

    bottom_tile = new(25, 38, PANEL)
    fill(bottom_tile, 0, 0, 25, 1, GOLD_DEEP)
    img.paste(bottom_tile, (179, 0))
    vis = new(75, 38, PANEL)
    bevel(vis, 3, 6, 69, 22, face=LCD, sunken=True)
    img.paste(vis, (205, 0))

    menus = [(0, ["URL", "DIR", "FILE"], 48), (54, ["ALL", "CROP", "SEL", "MISC"], 100),
             (104, ["INV", "NONE", "ALL"], 150), (154, ["SORT", "INFO", "OPTS"], 200),
             (204, ["NEW", "SAVE", "LOAD"], 250)]
    for x, labels, bar_x in menus:
        for index, label in enumerate(labels):
            playlist_button(img, x, 111 + index * 19, label, pressed=False)
            playlist_button(img, x + 23, 111 + index * 19, label, pressed=True)
        fill(img, bar_x, 111, 3, len(labels) * 18, GOLD_DIM)
        fill(img, bar_x + 1, 111, 1, len(labels) * 18, GOLD)
    return img


# Text files ------------------------------------------------------------------------------------

def hexcolor(color):
    return "#%02X%02X%02X" % color


PLEDIT_TXT = "\r\n".join([
    "[Text]",
    "Normal=" + hexcolor((217, 176, 76)),
    "Current=" + hexcolor((255, 241, 194)),
    "NormalBG=" + hexcolor((14, 12, 9)),
    "SelectedBG=" + hexcolor((74, 55, 16)),
    "Font=Helvetica",
    "",
])


def viscolors():
    colors = [(8, 7, 5), (42, 34, 18)]
    for step in range(16):
        t = step / 15
        colors.append((int(255 - 70 * t), int(226 - 130 * t), int(130 - 115 * t)))
    for step in range(5):
        t = step / 4
        colors.append((int(120 + 135 * t), int(84 + 130 * t), int(20 + 100 * t)))
    colors.append((255, 244, 214))
    return colors


VISCOLOR_TXT = "\r\n".join(
    ["%d,%d,%d, // %s" % (c + (name,)) for c, name in zip(viscolors(), (
        ["background", "dots"] + ["spectrum %d" % i for i in range(1, 17)]
        + ["oscilloscope %d" % i for i in range(1, 6)] + ["peaks"]))] + [""])

README_TXT = "\r\n".join([
    "Minidisc Gold",
    "",
    "The default skin for Minidisc's Winamp mode: original pixel art, gold on near-black,",
    "in the classic Winamp 2 skin format. Generated by Scripts/Winamp/make_minidisc_gold.py.",
    "Licensed with Minidisc under the Mozilla Public License 2.0.",
    "",
])


# Packaging -------------------------------------------------------------------------------------

def sheets():
    return {
        "main.bmp": make_main(),
        "cbuttons.bmp": make_cbuttons(),
        "titlebar.bmp": make_titlebar(),
        "posbar.bmp": make_posbar(),
        "volume.bmp": make_volume(),
        "balance.bmp": make_balance(),
        "numbers.bmp": make_numbers(extended=False),
        "nums_ex.bmp": make_numbers(extended=True),
        "text.bmp": make_text(),
        "playpaus.bmp": make_playpaus(),
        "monoster.bmp": make_monoster(),
        "shufrep.bmp": make_shufrep(),
        "eqmain.bmp": make_eqmain(),
        "pledit.bmp": make_pledit(),
        "eq_ex.bmp": make_eq_ex(),
    }


def bmp_bytes(img):
    buffer = io.BytesIO()
    img.convert("RGB").save(buffer, format="BMP")
    return buffer.getvalue()


def write_wsz(path, images):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    files = {name: bmp_bytes(img) for name, img in images.items()}
    files["pledit.txt"] = PLEDIT_TXT.encode("ascii")
    files["viscolor.txt"] = VISCOLOR_TXT.encode("ascii")
    files["readme.txt"] = README_TXT.encode("ascii")
    with zipfile.ZipFile(path, "w") as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED if name.endswith(".bmp") else zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            archive.writestr(info, files[name])


# Preview ---------------------------------------------------------------------------------------

def assembled_main(images):
    """The main window as Winamp mode would draw it, from the sprites alone."""
    window = images["main.bmp"].copy()

    def blit(sheet, sx, sy, w, h, dx, dy):
        window.paste(images[sheet].crop((sx, sy, sx + w, sy + h)), (dx, dy))

    blit("titlebar.bmp", 27, 0, 275, 14, 0, 0)
    blit("titlebar.bmp", 0, 0, 9, 9, 6, 3)
    blit("titlebar.bmp", 9, 0, 9, 9, 244, 3)
    blit("titlebar.bmp", 0, 18, 9, 9, 254, 3)
    blit("titlebar.bmp", 18, 0, 9, 9, 264, 3)
    blit("titlebar.bmp", 304, 0, 8, 43, 10, 22)
    blit("playpaus.bmp", 0, 0, 9, 9, 26, 28)
    blit("playpaus.bmp", 39, 0, 3, 9, 24, 28)
    for x, digit in zip((48, 60, 78, 90), (0, 1, 2, 3)):
        blit("nums_ex.bmp", digit * 9, 0, 9, 13, x, 26)
    title = "MINIDISC GOLD - WINAMP MODE"
    for index, char in enumerate(title):
        for row, chars in enumerate(TEXT_ROWS):
            if char in chars:
                blit("text.bmp", chars.index(char) * 5, row * 6, 5, 6, 111 + index * 5, 27)
                break
    for index, char in enumerate("320"):
        blit("text.bmp", TEXT_ROWS[1].index(char) * 5, 6, 5, 6, 111 + index * 5, 43)
    for index, char in enumerate("44"):
        blit("text.bmp", TEXT_ROWS[1].index(char) * 5, 6, 5, 6, 156 + index * 5, 43)
    rng = random.Random(7)
    vis = viscolors()
    for bar in range(19):
        height = rng.randint(2, 16)
        for row in range(height):
            window.putpixel((24 + bar * 4, 58 - row), vis[2 + 15 - min(15, row)])
            window.putpixel((25 + bar * 4, 58 - row), vis[2 + 15 - min(15, row)])
    blit("monoster.bmp", 29, 12, 27, 12, 212, 41)
    blit("monoster.bmp", 0, 0, 29, 12, 239, 41)
    blit("volume.bmp", 0, 20 * 15, 68, 13, 107, 57)
    blit("volume.bmp", 15, 422, 14, 11, 107 + 40, 58)
    blit("balance.bmp", 9, 0, 38, 13, 177, 57)
    blit("balance.bmp", 15, 422, 14, 11, 177 + 12, 58)
    blit("shufrep.bmp", 0, 73, 23, 12, 219, 58)
    blit("shufrep.bmp", 23, 61, 23, 12, 242, 58)
    blit("posbar.bmp", 0, 0, 248, 10, 16, 72)
    blit("posbar.bmp", 248, 0, 29, 10, 16 + 70, 72)
    for x, (sx, w, h) in zip((16, 39, 62, 85, 108, 136),
                             ((0, 23, 18), (23, 23, 18), (46, 23, 18), (69, 23, 18), (92, 22, 18), (114, 22, 16))):
        blit("cbuttons.bmp", sx, 0, w, h, x, 88 if sx != 114 else 89)
    blit("shufrep.bmp", 28, 30, 47, 15, 164, 89)
    blit("shufrep.bmp", 0, 0, 28, 15, 210, 89)
    return window


def assembled_equalizer(images):
    window = images["eqmain.bmp"].crop((0, 0, 275, 116))

    def blit(sx, sy, w, h, dx, dy):
        window.paste(images["eqmain.bmp"].crop((sx, sy, sx + w, sy + h)), (dx, dy))

    blit(0, 134, 275, 14, 0, 0)
    blit(0, 116, 9, 9, 264, 3)
    blit(69, 119, 26, 12, 14, 18)
    blit(36, 119, 32, 12, 40, 18)
    blit(224, 164, 44, 12, 217, 18)
    blit(0, 294, 113, 19, 86, 17)
    for index, x in enumerate([21] + [78 + band * 18 for band in range(10)]):
        frame = [14, 20, 22, 18, 15, 13, 11, 12, 16, 19, 21][index]
        blit(13 + (frame % 14) * 15, 164 + (frame // 14) * 65, 14, 63, x, 38)
        thumb_y = 38 + int(round((27 - frame) / 27 * 51))
        blit(0, 164, 11, 11, x + 1, thumb_y)
    return window


def assembled_playlist(images, rows=6):
    sheet = images["pledit.bmp"]
    width, height = 275, 20 + rows * 29 // 2 + 38
    height = 20 + 2 * 29 + 38
    window = new(width, height, (14, 12, 9))

    def blit(sx, sy, w, h, dx, dy):
        window.paste(sheet.crop((sx, sy, sx + w, sy + h)), (dx, dy))

    blit(0, 0, 25, 20, 0, 0)
    for x in range(25, 250, 25):
        blit(127, 0, 25, 20, x, 0)
    blit(26, 0, 100, 20, (width - 100) // 2, 0)
    blit(153, 0, 25, 20, width - 25, 0)
    for y in (20, 49):
        blit(0, 42, 12, 29, 0, y)
        blit(31, 42, 20, 29, width - 20, y)
    blit(52, 53, 8, 18, width - 15, 22)
    blit(0, 72, 125, 38, 0, height - 38)
    blit(179, 0, 25, 38, 125, height - 38)
    blit(126, 72, 150, 38, width - 150, height - 38)
    tracks = ["1. MINIDISC - OPENING", "2. GOLD ON BLACK", "3. GAPLESS FOREVER", "4. CROSSFADE"]
    for index, title in enumerate(tracks):
        y = 23 + index * 9
        if index == 1:
            fill(window, 12, y - 1, width - 32, 8, (74, 55, 16))
        color = (255, 241, 194) if index == 0 else (217, 176, 76)
        text(window, 15, y, title, color)
    return window


def contact_sheet(images, path):
    from PIL import ImageFont

    scale = 2
    font = ImageFont.load_default()
    pieces = [("main window (assembled)", assembled_main(images)),
              ("equalizer (assembled)", assembled_equalizer(images)),
              ("playlist (assembled)", assembled_playlist(images))]
    pieces += [(name, img) for name, img in images.items()]
    columns = 3
    cell_w = max(img.width for _, img in pieces) * scale + 24
    rows = []
    for start in range(0, len(pieces), columns):
        rows.append(pieces[start:start + columns])
    row_heights = [max(img.height for _, img in row) * scale + 30 for row in rows]
    sheet = Image.new("RGB", (cell_w * columns + 24, sum(row_heights) + 24), (40, 36, 30))
    draw = ImageDraw.Draw(sheet)
    y = 12
    for row, row_height in zip(rows, row_heights):
        for col, (name, img) in enumerate(row):
            x = 12 + col * cell_w
            draw.text((x, y), "%s  %d×%d" % (name, img.width, img.height), fill=(230, 210, 160), font=font)
            sheet.paste(img.resize((img.width * scale, img.height * scale), Image.NEAREST), (x, y + 16))
        y += row_height
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output", default=OUTPUT, help="where to write the .wsz")
    parser.add_argument("--preview", help="also write a contact-sheet PNG here")
    args = parser.parse_args()
    images = sheets()
    write_wsz(args.output, images)
    print("wrote", args.output)
    if args.preview:
        contact_sheet(images, args.preview)
        print("wrote", args.preview)


if __name__ == "__main__":
    main()
