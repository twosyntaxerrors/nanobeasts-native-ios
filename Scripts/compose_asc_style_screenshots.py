#!/usr/bin/env python3

from pathlib import Path
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "AppStoreScreenshots" / "Outcome-Suite" / "Raw"
CREATURES = ROOT / "AppStoreScreenshots" / "Outcome-Suite" / "Assets"
SUITE = ROOT / "AppStoreScreenshots" / "ASC-Style-Redesign"
BACKGROUNDS = SUITE / "Backgrounds"
OUTPUT = SUITE / "Polished"

CANVAS = (1320, 2868)
DISPLAY_FONT = Path("/System/Library/Fonts/Supplemental/Impact.ttf")

WHITE = (255, 255, 255, 255)

SCREENS = [
    {
        "source": "05-stats.png",
        "background": "green-cyber-jungle.png",
        "output": "01-see-how-far-youve-come.png",
        "lines": [("SEE HOW FAR", WHITE), ("YOU'VE COME.", (27, 239, 190, 255))],
        "accent": (28, 239, 188),
        "phone": (148, 568, 970, -3.2),
        "creature": ("overnode.png", 790, 1950, 565, 2.0, False),
        "effect": "rings",
    },
    {
        "source": "06-insights.png",
        "background": "green-cyber-jungle.png",
        "output": "02-find-your-winning-rhythm.png",
        "lines": [("FIND YOUR", WHITE), ("WINNING RHYTHM.", (22, 232, 199, 255))],
        "accent": (24, 231, 197),
        "phone": (205, 548, 920, 2.8),
        "creature": ("devicore.png", -6, 1860, 475, -4.0, False),
        "effect": "signal",
    },
    {
        "source": "07-dex.png",
        "background": "blue-aquatic-archive.png",
        "output": "03-turn-every-walk-into-a-discovery.png",
        "lines": [
            ("TURN EVERY WALK", WHITE),
            ("INTO A", WHITE),
            ("DISCOVERY.", (22, 205, 255, 255)),
        ],
        "accent": (27, 194, 255),
        "phone": (154, 600, 972, -2.4),
        "creature": ("tutoria.png", 800, 1900, 510, 5.0, False),
        "effect": "water",
    },
    {
        "source": "08-dex-detail.png",
        "background": "purple-psychic-chamber.png",
        "output": "04-become-something-stronger.png",
        "lines": [
            ("BECOME", WHITE),
            ("SOMETHING", WHITE),
            ("STRONGER.", (197, 91, 255, 255)),
        ],
        "accent": (190, 86, 255),
        "phone": (178, 596, 930, 2.6),
        "creature": ("devicore.png", 770, 1845, 520, -2.0, False),
        "effect": "psychic",
    },
]


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.fit(image.convert("RGBA"), size, Image.Resampling.LANCZOS)


def add_vignette(canvas: Image.Image) -> Image.Image:
    width, height = canvas.size
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for y in range(760):
        alpha = int(215 * (1 - y / 760) ** 1.7)
        draw.line((0, y, width, y), fill=(0, 0, 0, alpha))
    edge = Image.new("L", canvas.size, 0)
    edge_draw = ImageDraw.Draw(edge)
    edge_draw.ellipse((-260, -300, width + 260, height + 330), fill=255)
    edge = ImageOps.invert(edge).filter(ImageFilter.GaussianBlur(180))
    dark = Image.new("RGBA", canvas.size, (0, 0, 0, 185))
    dark.putalpha(edge)
    return Image.alpha_composite(Image.alpha_composite(canvas, layer), dark)


def font_for(text: str, max_width: int, start: int = 172) -> ImageFont.FreeTypeFont:
    size = start
    while size > 92:
        font = ImageFont.truetype(str(DISPLAY_FONT), size=size)
        if font.getlength(text) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(DISPLAY_FONT), size=size)


def draw_headline(canvas: Image.Image, lines: list[tuple[str, tuple[int, int, int, int]]]) -> None:
    draw = ImageDraw.Draw(canvas)
    y = 62
    gap = -10 if len(lines) == 2 else -22
    max_width = 1180
    for text, color in lines:
        font = font_for(text, max_width, 176 if len(lines) == 2 else 154)
        bbox = draw.textbbox((0, 0), text, font=font, stroke_width=0)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        x = (CANVAS[0] - tw) // 2
        for offset in range(20, 4, -3):
            draw.text(
                (x + offset, y + offset),
                text,
                font=font,
                fill=(0, 0, 0, 255),
                stroke_width=18,
                stroke_fill=(0, 0, 0, 255),
            )
        draw.text(
            (x, y),
            text,
            font=font,
            fill=color,
            stroke_width=11,
            stroke_fill=(0, 0, 0, 255),
        )
        y += th + gap


def rounded_phone(source: Path, screen_width: int, angle: float) -> Image.Image:
    source_image = Image.open(source).convert("RGBA")
    screen_height = round(source_image.height * (screen_width / source_image.width))
    source_image = source_image.resize((screen_width, screen_height), Image.Resampling.LANCZOS)

    bezel = 24
    phone = Image.new("RGBA", (screen_width + bezel * 2, screen_height + bezel * 2), (0, 0, 0, 0))
    body = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    body_draw = ImageDraw.Draw(body)
    body_draw.rounded_rectangle(
        (0, 0, phone.width - 1, phone.height - 1),
        radius=92,
        fill=(3, 5, 7, 255),
        outline=(174, 188, 195, 255),
        width=6,
    )
    mask = Image.new("L", source_image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, source_image.width - 1, source_image.height - 1),
        radius=72,
        fill=255,
    )
    phone.alpha_composite(body)
    phone.paste(source_image, (bezel, bezel), mask)

    shine = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    shine_draw = ImageDraw.Draw(shine)
    shine_draw.line((54, 70, 54, phone.height - 160), fill=(255, 255, 255, 58), width=4)
    shine_draw.line((phone.width - 48, 180, phone.width - 48, phone.height - 240), fill=(255, 255, 255, 34), width=3)
    phone = Image.alpha_composite(phone, shine)
    return phone.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)


def paste_phone(canvas: Image.Image, source: Path, x: int, y: int, width: int, angle: float) -> Image.Image:
    phone = rounded_phone(source, width, angle)
    alpha = phone.getchannel("A")
    shadow_alpha = alpha.filter(ImageFilter.GaussianBlur(42))
    shadow = Image.new("RGBA", phone.size, (0, 0, 0, 230))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow, (x + 34, y + 50))
    canvas.alpha_composite(phone, (x, y))
    return canvas


def crop_creature(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    return image.crop(bbox) if bbox else image


def paste_grounded_creature(
    canvas: Image.Image,
    filename: str,
    x: int,
    y: int,
    width: int,
    angle: float,
    flip: bool,
    accent: tuple[int, int, int],
) -> Image.Image:
    creature = crop_creature(CREATURES / filename)
    if flip:
        creature = creature.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    height = round(creature.height * width / creature.width)
    creature = creature.resize((width, height), Image.Resampling.LANCZOS)
    creature = creature.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)

    contact = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    contact_draw = ImageDraw.Draw(contact)
    contact_draw.ellipse(
        (x + width * 0.02, y + creature.height * 0.82, x + width * 1.02, y + creature.height * 1.05),
        fill=(*accent, 95),
    )
    contact_draw.ellipse(
        (x + width * 0.12, y + creature.height * 0.86, x + width * 0.92, y + creature.height * 1.03),
        fill=(0, 0, 0, 220),
    )
    contact = contact.filter(ImageFilter.GaussianBlur(35))
    canvas = Image.alpha_composite(canvas, contact)

    alpha = creature.getchannel("A")
    halo = Image.new("RGBA", creature.size, (*accent, 0))
    halo_alpha = alpha.filter(ImageFilter.GaussianBlur(34)).point(lambda value: int(value * 0.42))
    halo.putalpha(halo_alpha)
    canvas.alpha_composite(halo, (x, y))

    shadow = Image.new("RGBA", creature.size, (0, 0, 0, 190))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(18)))
    canvas.alpha_composite(shadow, (x + 22, y + 30))
    canvas.alpha_composite(creature, (x, y))

    rim = Image.new("RGBA", creature.size, (0, 0, 0, 0))
    rim_alpha = alpha.filter(ImageFilter.MaxFilter(11))
    rim_alpha = ImageChops.subtract(rim_alpha, alpha).filter(ImageFilter.GaussianBlur(4))
    rim_alpha = rim_alpha.point(lambda value: int(value * 0.38))
    rim_color = Image.new("RGBA", creature.size, (*accent, 210))
    rim_color.putalpha(rim_alpha)
    canvas.alpha_composite(rim_color, (x, y))
    return canvas


def draw_effects(canvas: Image.Image, style: str, accent: tuple[int, int, int]) -> Image.Image:
    random.seed(style)
    sharp = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    s = ImageDraw.Draw(sharp)

    for _ in range(48):
        x = random.randint(20, CANVAS[0] - 20)
        y = random.randint(1740, CANVAS[1] - 120)
        radius = random.choice((2, 3, 4))
        alpha = random.randint(70, 170)
        s.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*accent, alpha))
    return Image.alpha_composite(canvas, sharp)


def compose(config: dict) -> None:
    canvas = cover(Image.open(BACKGROUNDS / config["background"]), CANVAS)
    canvas = add_vignette(canvas)
    draw_headline(canvas, config["lines"])
    canvas = paste_phone(canvas, RAW / config["source"], *config["phone"])
    canvas = paste_grounded_creature(
        canvas,
        *config["creature"],
        accent=config["accent"],
    )
    canvas = draw_effects(canvas, config["effect"], config["accent"])
    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT / config["output"], "PNG", compress_level=6)


def main() -> None:
    for config in SCREENS:
        compose(config)


if __name__ == "__main__":
    main()
