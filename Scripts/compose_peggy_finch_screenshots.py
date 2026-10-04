#!/usr/bin/env python3

"""Compose a clean, creature-led App Store screenshot set.

The native UI and Nanobeast artwork stay untouched. Only the marketing frame,
typography, device treatment, and decorative geometry are composited here.
"""

from __future__ import annotations

import gc
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / "AppStoreScreenshots" / "Peggy-Finch-Redesign"
RAW = SUITE / "Raw"
ASSETS = SUITE / "Assets"
OUTPUT = SUITE / "Polished"
BADGES = ROOT / "Design" / "BadgeAssets" / "approved"

CANVAS = (1320, 2868)
DISPLAY_FONT = Path("/Library/Fonts/SF-Pro-Display-Bold.otf")
TEXT_FONT = Path("/Library/Fonts/SF-Pro-Text-Medium.otf")
MONO_FONT = ROOT / "Nanobeasts" / "Resources" / "Fonts" / "Aldrich_400Regular.ttf"


def hex_color(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def clean_gradient(top: str, bottom: str) -> Image.Image:
    top_rgb = hex_color(top)
    bottom_rgb = hex_color(bottom)
    image = Image.new("RGB", CANVAS)
    draw = ImageDraw.Draw(image)
    for y in range(CANVAS[1]):
        progress = y / (CANVAS[1] - 1)
        color = tuple(
            round(top_rgb[channel] * (1 - progress) + bottom_rgb[channel] * progress)
            for channel in range(3)
        )
        draw.line((0, y, CANVAS[0], y), fill=color)
    return image.convert("RGBA")


def add_blob(
    canvas: Image.Image,
    bounds: tuple[int, int, int, int],
    color: str,
    alpha: int = 255,
) -> None:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(bounds, fill=(*hex_color(color), alpha))
    canvas.alpha_composite(layer)


def add_squiggle(
    canvas: Image.Image,
    points: Iterable[tuple[int, int]],
    color: str,
    width: int = 18,
    alpha: int = 180,
) -> None:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(layer).line(
        list(points), fill=(*hex_color(color), alpha), width=width, joint="curve"
    )
    canvas.alpha_composite(layer)


def fit_font(lines: str, max_width: int, start_size: int = 108) -> ImageFont.FreeTypeFont:
    size = start_size
    while size >= 68:
        font = ImageFont.truetype(str(DISPLAY_FONT), size)
        if max(font.getlength(line) for line in lines.splitlines()) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(DISPLAY_FONT), size)


def draw_header(
    canvas: Image.Image,
    headline: str,
    subtitle: str,
    ink: str,
    pill_fill: str,
    pill_ink: str,
) -> None:
    draw = ImageDraw.Draw(canvas)
    mono = ImageFont.truetype(str(MONO_FONT), 26)
    subtitle_font = ImageFont.truetype(str(TEXT_FONT), 35)
    headline_font = fit_font(headline, 1170)

    draw.rounded_rectangle((72, 62, 585, 118), radius=28, fill=hex_color(pill_fill))
    draw.text((98, 75), "NANOBEASTS  •  WALK TO EVOLVE", font=mono, fill=hex_color(pill_ink))
    draw.multiline_text(
        (70, 153),
        headline,
        font=headline_font,
        fill=hex_color(ink),
        spacing=-10,
    )
    headline_box = draw.multiline_textbbox(
        (70, 153), headline, font=headline_font, spacing=-10
    )
    draw.text(
        (74, headline_box[3] + 26),
        subtitle,
        font=subtitle_font,
        fill=(*hex_color(ink), 205),
    )


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def paste_phone(
    canvas: Image.Image,
    source: Path,
    x: int,
    y: int,
    width: int,
    border: str,
    angle: float = 0,
) -> tuple[int, int]:
    screen = Image.open(source).convert("RGBA")
    height = round(screen.height * width / screen.width)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)
    radius = max(64, round(width * 0.085))

    card = Image.new("RGBA", (width + 44, height + 44), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle(
        (2, 2, width + 41, height + 41),
        radius=radius + 20,
        fill=(4, 6, 9, 255),
        outline=hex_color(border),
        width=6,
    )
    card.paste(screen, (22, 22), rounded_mask((width, height), radius))

    shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow.putalpha(card.getchannel("A").filter(ImageFilter.GaussianBlur(26)))
    black = Image.new("RGBA", card.size, (0, 0, 0, 150))
    black.putalpha(shadow.getchannel("A"))

    if angle:
        card = card.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
        black = black.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    canvas.alpha_composite(black, (x + 14, y + 26))
    canvas.alpha_composite(card, (x, y))
    return card.size


def paste_creature(
    canvas: Image.Image,
    filename: str,
    x: int,
    y: int,
    width: int,
    angle: float = 0,
    flip: bool = False,
    glow: str | None = None,
) -> None:
    creature = Image.open(ASSETS / filename).convert("RGBA")
    alpha_box = creature.getchannel("A").getbbox()
    if alpha_box:
        creature = creature.crop(alpha_box)
    if flip:
        creature = creature.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    height = round(creature.height * width / creature.width)
    creature = creature.resize((width, height), Image.Resampling.LANCZOS)
    if angle:
        creature = creature.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)

    alpha = creature.getchannel("A")
    shadow_alpha = alpha.filter(ImageFilter.GaussianBlur(18))
    if glow:
        glow_layer = Image.new("RGBA", creature.size, (*hex_color(glow), 0))
        glow_layer.putalpha(shadow_alpha.point(lambda value: round(value * 0.55)))
        canvas.alpha_composite(glow_layer, (x, y + 8))
    shadow = Image.new("RGBA", creature.size, (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha.point(lambda value: round(value * 0.62)))
    canvas.alpha_composite(shadow, (x + 14, y + 26))
    canvas.alpha_composite(creature, (x, y))


def paste_badge(
    canvas: Image.Image,
    filename: str,
    x: int,
    y: int,
    size: int,
    disc: str,
) -> None:
    icon = Image.open(BADGES / filename).convert("RGBA")
    alpha_box = icon.getchannel("A").getbbox()
    if alpha_box:
        icon = icon.crop(alpha_box)
    icon.thumbnail((round(size * 0.78), round(size * 0.78)), Image.Resampling.LANCZOS)
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(tile).ellipse((0, 0, size, size), fill=hex_color(disc))
    tile.alpha_composite(icon, ((size - icon.width) // 2, (size - icon.height) // 2))
    shadow = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    shadow.putalpha(tile.getchannel("A").filter(ImageFilter.GaussianBlur(16)))
    canvas.alpha_composite(shadow, (x + 8, y + 18))
    canvas.alpha_composite(tile, (x, y))


def paste_real_ui_card(
    canvas: Image.Image,
    source: Path,
    crop: tuple[int, int, int, int],
    x: int,
    y: int,
    width: int,
    border: str,
    angle: float = 0,
) -> None:
    image = Image.open(source).convert("RGBA").crop(crop)
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    radius = 44
    card = Image.new("RGBA", (width + 30, height + 30), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle(
        (2, 2, width + 27, height + 27),
        radius=radius + 14,
        fill=(5, 8, 11, 255),
        outline=hex_color(border),
        width=5,
    )
    card.paste(image, (15, 15), rounded_mask((width, height), radius))
    shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow.putalpha(card.getchannel("A").filter(ImageFilter.GaussianBlur(24)))
    if angle:
        card = card.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
        shadow = shadow.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    canvas.alpha_composite(shadow, (x + 12, y + 22))
    canvas.alpha_composite(card, (x, y))


def panel_home() -> Image.Image:
    canvas = clean_gradient("#2F5BEE", "#163493")
    add_blob(canvas, (-280, 1730, 920, 2920), "#72E7D4", 255)
    add_blob(canvas, (820, 480, 1500, 1160), "#BCEB72", 240)
    add_squiggle(canvas, [(0, 590), (190, 540), (350, 610), (560, 550)], "#83E6FF", 15)
    draw_header(
        canvas,
        "EVERY STEP BRINGS\nTHEM TO LIFE",
        "A pedometer that turns walking into evolution.",
        "#FFFFFF",
        "#FFFFFF",
        "#163493",
    )
    paste_phone(canvas, RAW / "01-home.png", 136, 720, 1004, "#BCEB72")
    paste_creature(canvas, "bloomwraith.png", 866, 470, 500, -6, False, "#BCEB72")
    return canvas


def panel_evolution() -> Image.Image:
    canvas = clean_gradient("#5138C9", "#231B72")
    add_blob(canvas, (-420, 1740, 900, 3060), "#2FD9E7", 210)
    add_blob(canvas, (780, 680, 1580, 1480), "#A6F05D", 210)
    add_squiggle(
        canvas,
        [(80, 770), (260, 650), (470, 760), (690, 630), (930, 760), (1210, 650)],
        "#F7E36B",
        17,
    )
    draw_header(
        canvas,
        "WALK. HATCH.\nEVOLVE.",
        "Progress fills. Creatures transform. Your Dex grows.",
        "#FFFFFF",
        "#F7E36B",
        "#2A216D",
    )
    paste_phone(canvas, RAW / "02-evolution.png", 150, 760, 1020, "#52E1D0")
    paste_creature(canvas, "glitchlet.png", -70, 660, 360, -9, False, "#A6F05D")
    paste_creature(canvas, "devicore.png", 1010, 650, 360, 8, False, "#52E1D0")
    return canvas


def panel_dex() -> Image.Image:
    canvas = clean_gradient("#A8EAFF", "#6FC6EA")
    add_blob(canvas, (-390, 1630, 950, 3020), "#72D17B", 255)
    add_blob(canvas, (780, 1460, 1570, 2320), "#F6D66A", 245)
    add_blob(canvas, (820, 330, 1440, 950), "#FFFFFF", 120)
    draw_header(
        canvas,
        "BUILD YOUR\nLIVING DEX",
        "Discover new species and open their field entries.",
        "#083B55",
        "#083B55",
        "#FFFFFF",
    )
    paste_phone(canvas, RAW / "03-dex.png", 118, 700, 1005, "#083B55")
    paste_real_ui_card(
        canvas,
        RAW / "04-dex-detail.png",
        (35, 435, 1170, 1710),
        670,
        1570,
        600,
        "#5CE0D0",
        4,
    )
    paste_creature(canvas, "tutoria.png", -82, 1040, 340, -8, False, "#FFFFFF")
    paste_creature(canvas, "ampaw.png", 1030, 990, 320, 7, True, "#F6D66A")
    return canvas


def panel_stats() -> Image.Image:
    canvas = clean_gradient("#DDF7E8", "#A9E1D6")
    add_blob(canvas, (-280, 1600, 730, 2750), "#5FE0D1", 230)
    add_blob(canvas, (770, 330, 1530, 1100), "#FFD85B", 240)
    add_squiggle(canvas, [(0, 650), (220, 610), (430, 690), (680, 590)], "#153C50", 12, 110)
    draw_header(
        canvas,
        "SEE WHAT\nMOVES YOU",
        "Weekly, monthly, and yearly step insights.",
        "#153C50",
        "#153C50",
        "#FFFFFF",
    )
    paste_phone(canvas, RAW / "05-stats.png", 120, 720, 1005, "#153C50")
    paste_real_ui_card(
        canvas,
        RAW / "05-insights.png",
        (48, 145, 1162, 1585),
        610,
        1570,
        660,
        "#5CE0D0",
        3,
    )
    paste_creature(canvas, "ampaw.png", 900, 425, 420, 5, True, "#FFD85B")
    return canvas


def panel_badges() -> Image.Image:
    canvas = clean_gradient("#FFD875", "#F0A451")
    add_blob(canvas, (-310, 1600, 820, 2790), "#FFF1B5", 235)
    add_blob(canvas, (830, 410, 1530, 1110), "#6B4DE6", 235)
    draw_header(
        canvas,
        "EARN EVERY\nMILESTONE",
        "Streaks, distance, goals, and collection badges.",
        "#30234F",
        "#30234F",
        "#FFFFFF",
    )
    paste_badge(canvas, "collection-25.png", 1010, 560, 250, "#FFFFFF")
    paste_phone(canvas, RAW / "06-badges.png", 140, 740, 1000, "#6B4DE6")
    paste_badge(canvas, "streak-30.png", -48, 1190, 250, "#FFF8DB")
    paste_badge(canvas, "goal-30.png", 1085, 1610, 230, "#FFF8DB")
    paste_creature(canvas, "tutoria.png", 855, 440, 390, -4, False, "#FFFFFF")
    return canvas


def panel_eggs() -> Image.Image:
    canvas = clean_gradient("#DCCBFF", "#A9A0F4")
    add_blob(canvas, (-280, 1640, 850, 2860), "#83E3D4", 245)
    add_blob(canvas, (780, 430, 1500, 1160), "#F5E86E", 220)
    add_squiggle(canvas, [(0, 680), (210, 620), (410, 700), (620, 610)], "#5B3FA7", 14, 130)
    draw_header(
        canvas,
        "CHOOSE WHAT\nHATCHES NEXT",
        "Finish one journey. Pick the egg that starts the next.",
        "#30235F",
        "#30235F",
        "#FFFFFF",
    )
    paste_phone(canvas, RAW / "07-eggs.png", 132, 760, 1005, "#5B3FA7")
    paste_creature(canvas, "glitchlet.png", 910, 465, 360, 4, False, "#F5E86E")
    paste_creature(canvas, "egg-glitchlet.png", 982, 690, 250, 3, False, "#F5E86E")
    paste_creature(canvas, "egg-tutoria.png", -65, 1030, 300, -8, False, "#FFFFFF")
    paste_creature(canvas, "egg-ampaw.png", 1060, 1560, 260, 8, False, "#FFFFFF")
    return canvas


PANELS = [
    ("01-every-step-brings-them-to-life.png", panel_home),
    ("02-walk-hatch-evolve.png", panel_evolution),
    ("03-build-your-living-dex.png", panel_dex),
    ("04-see-what-moves-you.png", panel_stats),
    ("05-earn-every-milestone.png", panel_badges),
    ("06-choose-what-hatches-next.png", panel_eggs),
]


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for filename, renderer in PANELS:
        panel = renderer()
        rgb = panel.convert("RGB")
        rgb.save(OUTPUT / filename, "PNG", compress_level=5)
        rgb.close()
        panel.close()
        gc.collect()


if __name__ == "__main__":
    main()
