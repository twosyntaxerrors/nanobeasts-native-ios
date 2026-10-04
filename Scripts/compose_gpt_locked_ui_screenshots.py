#!/usr/bin/env python3

"""Compose GPT-generated scene art around locked, untouched app UI captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / "AppStoreScreenshots" / "GPT-Image-Redesign"
GENERATED = SUITE / "Generated"
FINAL = SUITE / "Final"
RAW = ROOT / "AppStoreScreenshots" / "Peggy-Finch-Redesign" / "Raw"

CANVAS = (1320, 2868)
DISPLAY_FONT = Path("/Library/Fonts/SF-Pro-Display-Bold.otf")
TEXT_FONT = Path("/Library/Fonts/SF-Pro-Text-Medium.otf")
MONO_FONT = ROOT / "Nanobeasts" / "Resources" / "Fonts" / "Aldrich_400Regular.ttf"


def cover(image: Image.Image, size: tuple[int, int], top_bias: float = 0.0) -> Image.Image:
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = max(0, (resized.width - size[0]) // 2)
    overflow = max(0, resized.height - size[1])
    top = round(overflow * top_bias)
    return resized.crop((left, top, left + size[0], top + size[1]))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size[0], size[1]), radius=radius, fill=255
    )
    return mask


def paste_phone(
    canvas: Image.Image,
    source: Path,
    x: int,
    y: int,
    width: int,
    border: tuple[int, int, int],
) -> None:
    screen = Image.open(source).convert("RGBA")
    height = round(screen.height * width / screen.width)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)
    radius = round(width * 0.085)

    shadow_layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.rounded_rectangle(
        (x - 20, y - 20, x + width + 20, y + height + 20),
        radius=radius + 20,
        fill=(0, 0, 0, 215),
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(42))
    canvas.alpha_composite(shadow_layer)

    frame = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (x - 16, y - 16, x + width + 16, y + height + 16),
        radius=radius + 16,
        fill=(4, 7, 10, 255),
        outline=(*border, 255),
        width=5,
    )
    canvas.alpha_composite(frame)
    canvas.paste(screen, (x, y), rounded_mask(screen.size, radius))


def paste_generated_character(
    canvas: Image.Image,
    source: Path,
    x: int,
    y: int,
    width: int,
) -> None:
    character = Image.open(source).convert("RGBA")
    bounds = character.getchannel("A").getbbox()
    if bounds:
        character = character.crop(bounds)
    height = round(character.height * width / character.width)
    character = character.resize((width, height), Image.Resampling.LANCZOS)

    alpha = character.getchannel("A")
    shadow_alpha = alpha.filter(ImageFilter.GaussianBlur(18)).point(
        lambda value: round(value * 0.58)
    )
    shadow = Image.new("RGBA", character.size, (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow, (x + 18, y + 30))
    canvas.alpha_composite(character, (x, y))


def draw_header(canvas: Image.Image, dark_ink: bool = False) -> None:
    draw = ImageDraw.Draw(canvas)
    mono = ImageFont.truetype(str(MONO_FONT), 29)
    headline = ImageFont.truetype(str(DISPLAY_FONT), 102)
    subtitle = ImageFont.truetype(str(TEXT_FONT), 36)
    headline_color = (20, 48, 70, 255) if dark_ink else (255, 255, 255, 255)
    subtitle_color = (28, 67, 87, 235) if dark_ink else (229, 235, 247, 255)
    brand_color = (21, 88, 102, 255) if dark_ink else (102, 235, 218, 255)

    draw.text((72, 70), "NANOBEASTS", font=mono, fill=brand_color)
    draw.rounded_rectangle((72, 119, 248, 128), radius=5, fill=brand_color)
    draw.multiline_text(
        (68, 164),
        "EVERY STEP BRINGS\nTHEM TO LIFE",
        font=headline,
        fill=headline_color,
        spacing=-10,
        stroke_width=0 if dark_ink else 2,
        stroke_fill=(22, 25, 57, 120),
    )
    draw.text(
        (72, 400),
        "A pedometer that turns walking into evolution.",
        font=subtitle,
        fill=subtitle_color,
    )


def compose_hero(background_name: str, output_name: str, bright: bool) -> None:
    background = Image.open(GENERATED / background_name).convert("RGBA")
    canvas = cover(background, CANVAS, top_bias=0.0)

    top_scrim = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    scrim_draw = ImageDraw.Draw(top_scrim)
    for y in range(0, 620):
        alpha = round((70 if bright else 118) * (1 - y / 620))
        color = (255, 255, 255, alpha) if bright else (8, 11, 35, alpha)
        scrim_draw.line((0, y, CANVAS[0], y), fill=color)
    canvas = Image.alpha_composite(canvas, top_scrim)

    draw_header(canvas, dark_ink=bright)
    paste_phone(canvas, RAW / "01-home.png", 145, 680, 1030, (91, 225, 208))
    paste_generated_character(
        canvas,
        GENERATED / "01-bloomwraith-hanging-alpha-v3.png",
        800,
        410,
        520,
    )

    FINAL.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(
        FINAL / output_name,
        "PNG",
        compress_level=5,
    )


if __name__ == "__main__":
    compose_hero(
        "01-bloomwraith-biome.png",
        "01-every-step-brings-them-to-life-gpt-locked-ui-twilight.png",
        bright=False,
    )
    compose_hero(
        "01-bloomwraith-biome-bright.png",
        "01-every-step-brings-them-to-life-gpt-locked-ui-bright.png",
        bright=True,
    )
