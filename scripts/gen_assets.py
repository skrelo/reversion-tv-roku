#!/usr/bin/env python3
"""Generate Home-screen raster assets that Roku SceneGraph can't draw at runtime.

Roku Rectangles are always sharp and Posters have no drop-shadow/border-radius,
so legibility scrims, rounded button backgrounds, the nav gradient and the
circular avatar are all baked here. Values mirror the Tizen CSS
(reversion-tv-tizen/src/screens/Home.css + LeftNav.css) so the platforms match.

Run:  python3 scripts/gen_assets.py
"""
import os
from PIL import Image, ImageDraw

NAVY = (15, 25, 35)          # --bg #0F1923
NAVY_NAV = (10, 18, 26)      # nav gradient base (rgba(10,18,26,...))
OUT = os.path.join(os.path.dirname(__file__), "..", "images")


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", os.path.relpath(path))


def rounded_button_9patch():
    """White rounded-rect, 6px radius, as a Roku 9-patch (.9.png).

    A 1px guide frame surrounds a 24x24 white rounded rect. Black pixels on the
    top + left edges mark the stretchable band (the flat middle), so the corners
    keep their radius while Roku scales the center to any button size. Tinted at
    runtime via Poster.blendColor."""
    core = 24
    r = 8  # source radius; scales visually to ~6px on the rendered button
    img = Image.new("RGBA", (core + 2, core + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # White rounded rect in the inner (content) area.
    d.rounded_rectangle([1, 1, core, core], radius=r, fill=(255, 255, 255, 255))
    # 9-patch guides (opaque black) — stretch the flat middle only.
    mid_lo = 1 + r
    mid_hi = core - r
    for x in range(mid_lo, mid_hi):
        img.putpixel((x, 0), (0, 0, 0, 255))            # top: stretchable cols
    for y in range(mid_lo, mid_hi):
        img.putpixel((0, y), (0, 0, 0, 255))            # left: stretchable rows
    # Content guides (right + bottom) — full flat area is content.
    for x in range(mid_lo, mid_hi):
        img.putpixel((x, core + 1), (0, 0, 0, 255))
    for y in range(mid_lo, mid_hi):
        img.putpixel((core + 1, y), (0, 0, 0, 255))
    save(img, "btn_rounded.9.png")


def nav_gradient():
    """Left nav legibility scrim. Mirrors LeftNav.css `.expanded .nav-gradient`:
    rgba(10,18,26,0.98) to 360px, 0.70 at 460px, transparent at 600px."""
    w, h = 600, 1080
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for x in range(w):
        if x <= 360:
            a = 0.98
        elif x <= 460:
            a = 0.98 + (0.70 - 0.98) * ((x - 360) / 100.0)
        elif x <= 600:
            a = 0.70 + (0.0 - 0.70) * ((x - 460) / 140.0)
        else:
            a = 0.0
        alpha = max(0, min(255, int(a * 255)))
        for y in range(h):
            px[x, y] = (NAVY_NAV[0], NAVY_NAV[1], NAVY_NAV[2], alpha)
    save(img, "nav_gradient.png")


def card_gradient():
    """Bottom-up fade behind a card wordmark/overlay title. Mirrors
    Home.css `.card-gradient`: navy 0.92 at bottom, 0.40 at 55%, transparent top."""
    w, h = 300, 110
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = img.load()
    for y in range(h):
        # frac 0 at top, 1 at bottom
        f = y / float(h - 1)
        if f >= 0.45:               # bottom 55%
            t = (f - 0.45) / 0.55   # 0 at 45% line, 1 at bottom
            a = 0.40 + (0.92 - 0.40) * t
        else:
            t = f / 0.45            # 0 at top, 1 at 45% line
            a = 0.0 + 0.40 * t
        alpha = max(0, min(255, int(a * 255)))
        for x in range(w):
            d[x, y] = (NAVY[0], NAVY[1], NAVY[2], alpha)
    save(img, "card_gradient.png")


def hero_fade():
    """Bottom vertical fade to navy. Extends a touch higher than the Tizen
    `.hero-fade` so the carousel content (which sits in the lower-middle on
    Roku) gets a slightly darker base and the gold/white text stops washing out
    on bright backdrops: navy(opaque) at bottom, 0.88 at 18% up, 0.30 at 46% up,
    transparent at 64% up. Stretched to the live hero height at runtime."""
    w, h = 16, 1000
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = img.load()
    for y in range(h):
        up = (h - 1 - y) / float(h - 1)   # 0 at bottom, 1 at top
        if up <= 0.18:
            a = 1.0 + (0.88 - 1.0) * (up / 0.18)
        elif up <= 0.46:
            a = 0.88 + (0.30 - 0.88) * ((up - 0.18) / 0.28)
        elif up <= 0.64:
            a = 0.30 + (0.0 - 0.30) * ((up - 0.46) / 0.18)
        else:
            a = 0.0
        alpha = max(0, min(255, int(a * 255)))
        for x in range(w):
            d[x, y] = (NAVY[0], NAVY[1], NAVY[2], alpha)
    save(img, "hero_fade.png")


def hero_scrim():
    """Bottom-left content scrim so the wordmark + gold text never wash out on a
    bright backdrop (Roku Labels/Posters can't do text-shadow/drop-shadow like
    the Tizen CSS does). Navy, strongest at bottom-left, fading up + right."""
    w, h = 1280, 820
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = img.load()
    max_a = 0.82
    for y in range(h):
        vb = (h - 1 - y) / float(h - 1)        # 1 at bottom, 0 at top
        vb = vb * vb                            # ease — concentrate at bottom
        for x in range(w):
            hl = (w - 1 - x) / float(w - 1)     # 1 at left, 0 at right
            hl = hl * hl
            a = max_a * vb * hl
            d[x, y] = (NAVY[0], NAVY[1], NAVY[2], max(0, min(255, int(a * 255))))
    save(img, "hero_scrim.png")


def avatar_circle():
    """Solid white circle for the nav profile avatar (tinted via blendColor),
    so the initial sits on a round chip instead of a square."""
    s = 128
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, s - 1, s - 1], fill=(255, 255, 255, 255))
    save(img, "avatar_circle.png")


def avatar_mask_nav():
    """Circular crop frame for the nav profile photo: opaque corners in the nav
    gradient base color (NAVY_NAV) with a transparent center circle. Layered ON
    TOP of a square photo so it reads as a circle, with corners that blend into
    the expanded nav gradient. (Settings uses a separate avatar_mask.png whose
    corners match its panel color instead.)"""
    s = 128
    img = Image.new("RGBA", (s, s), (NAVY_NAV[0], NAVY_NAV[1], NAVY_NAV[2], 255))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, s - 1, s - 1], fill=(0, 0, 0, 0))
    save(img, "avatar_mask_nav.png")


def player_glyphs():
    """White 96x96 transport glyphs for the player chrome (tinted at runtime via
    Poster.blendColor like the other ic_*.png icons). Saved into images/icons/."""
    S = 96
    W = (255, 255, 255, 255)
    icons_dir = os.path.join(OUT, "icons")

    def new():
        return Image.new("RGBA", (S, S), (0, 0, 0, 0))

    def put(img, name):
        path = os.path.join(icons_dir, name)
        img.save(path)
        print("wrote", os.path.relpath(path))

    # Pause — two vertical bars.
    img = new(); d = ImageDraw.Draw(img)
    d.rounded_rectangle([26, 22, 40, 74], radius=4, fill=W)
    d.rounded_rectangle([56, 22, 70, 74], radius=4, fill=W)
    put(img, "ic_pause.png")

    # Restart — counter-clockwise circular arrow.
    img = new(); d = ImageDraw.Draw(img)
    d.arc([24, 24, 72, 72], start=70, end=360, fill=W, width=9)
    # Arrowhead at the open top.
    d.polygon([(48, 12), (62, 30), (38, 30)], fill=W)
    put(img, "ic_restart.png")

    # Next — triangle + trailing bar (skip).
    img = new(); d = ImageDraw.Draw(img)
    d.polygon([(26, 22), (26, 74), (58, 48)], fill=W)
    d.rounded_rectangle([60, 22, 72, 74], radius=3, fill=W)
    put(img, "ic_next.png")

    # CC / subtitles — rounded rect with two short lines.
    img = new(); d = ImageDraw.Draw(img)
    d.rounded_rectangle([18, 28, 78, 68], radius=8, outline=W, width=6)
    d.rounded_rectangle([28, 52, 46, 58], radius=3, fill=W)
    d.rounded_rectangle([52, 52, 68, 58], radius=3, fill=W)
    put(img, "ic_cc.png")

    # Add note — page with lines + small plus badge.
    img = new(); d = ImageDraw.Draw(img)
    d.rounded_rectangle([24, 18, 64, 78], radius=6, outline=W, width=6)
    for y in (34, 46, 58):
        d.rounded_rectangle([32, y, 56, y + 4], radius=2, fill=W)
    # plus badge bottom-right
    d.ellipse([56, 50, 84, 78], fill=W)
    d.rectangle([68, 57, 72, 71], fill=(15, 25, 35, 255))
    d.rectangle([63, 62, 77, 66], fill=(15, 25, 35, 255))
    put(img, "ic_note.png")

    # Chapters — list rows with leading bullets.
    img = new(); d = ImageDraw.Draw(img)
    for y in (28, 48, 68):
        d.ellipse([20, y - 4, 30, y + 6], fill=W)
        d.rounded_rectangle([40, y - 3, 78, y + 4], radius=3, fill=W)
    put(img, "ic_chapters.png")

    # Chevrons (hold-to-seek indicator).
    img = new(); d = ImageDraw.Draw(img)
    d.line([(58, 20), (34, 48), (58, 76)], fill=W, width=10, joint="curve")
    put(img, "ic_chevron_left.png")
    img = new(); d = ImageDraw.Draw(img)
    d.line([(38, 20), (62, 48), (38, 76)], fill=W, width=10, joint="curve")
    put(img, "ic_chevron_right.png")
    img = new(); d = ImageDraw.Draw(img)
    d.line([(20, 38), (48, 62), (76, 38)], fill=W, width=10, joint="curve")
    put(img, "ic_chevron_down.png")


if __name__ == "__main__":
    rounded_button_9patch()
    nav_gradient()
    card_gradient()
    hero_fade()
    hero_scrim()
    avatar_circle()
    avatar_mask_nav()
    player_glyphs()
    print("done")
