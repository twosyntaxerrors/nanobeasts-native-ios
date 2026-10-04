#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "AppStoreScreenshots" / "AI-Evolution-Alternates"
OUTPUT_DIR = SOURCE_DIR / "Polished"
CANVAS_SIZE = (1320, 2868)

DISPLAY_FONT = Path("/Library/Fonts/SF-Pro-Display-Bold.otf")
TEXT_FONT = Path("/Library/Fonts/SF-Pro-Text-Medium.otf")
MONO_FONT = ROOT / "Nanobeasts" / "Resources" / "Fonts" / "Aldrich_400Regular.ttf"

SCREENS = [
    (
        "01-all-badges-unlocked.png",
        "01-earn-every-badge.png",
        "EARN EVERY BADGE",
        "64 achievements. One step at a time.",
        (106, 82, 255),
    ),
    (
        "02-evolution-in-progress.png",
        "02-watch-your-steps-evolve.png",
        "WATCH YOUR STEPS EVOLVE",
        "Every walk powers a cinematic transformation.",
        (45, 231, 214),
    ),
    (
        "03-devicore-evolution-complete.png",
        "03-meet-your-next-form.png",
        "MEET YOUR NEXT FORM",
        "Move more. Evolve stronger. Unlock the Dex.",
        (44, 220, 235),
    ),
    (
        "04-overnode-evolution-complete.png",
        "04-reach-your-final-form.png",
        "REACH YOUR FINAL FORM",
        "Complete a full Nanobeast evolution line.",
        (131, 93, 255),
    ),
]


def background(accent: tuple[int, int, int]) -> Image.Image:
    width, height = CANVAS_SIZE
    image = Image.new("RGB", CANVAS_SIZE)
    gradient_draw = ImageDraw.Draw(image)
    for y in range(height):
        progress = y / max(height - 1, 1)
        teal_weight = max(0, 1 - progress * 1.15)
        color = (
            int(4 + accent[0] * 0.035 * teal_weight),
            int(8 + accent[1] * 0.095 * teal_weight),
            int(11 + accent[2] * 0.075 * teal_weight),
        )
        gradient_draw.line((0, y, width, y), fill=color)

    glow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        (-180, 160, 1500, 1940),
        fill=(*accent, 38),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(230))
    image = Image.alpha_composite(image.convert("RGBA"), glow)

    grid = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    for x in range(0, width, 94):
        grid_draw.line((x, 0, x, height), fill=(90, 236, 222, 12), width=1)
    for y in range(0, height, 94):
        grid_draw.line((0, y, width, y), fill=(90, 236, 222, 12), width=1)
    return Image.alpha_composite(image, grid)


def fit_font(text: str, max_width: int, start_size: int) -> ImageFont.FreeTypeFont:
    size = start_size
    while size > 56:
        font = ImageFont.truetype(str(DISPLAY_FONT), size=size)
        bounds = font.getbbox(text)
        if bounds[2] - bounds[0] <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(DISPLAY_FONT), size=size)


def compose(
    source_name: str,
    output_name: str,
    headline: str,
    subtitle: str,
    accent: tuple[int, int, int],
) -> None:
    canvas = background(accent)
    draw = ImageDraw.Draw(canvas)

    eyebrow_font = ImageFont.truetype(str(MONO_FONT), size=31)
    subtitle_font = ImageFont.truetype(str(TEXT_FONT), size=39)
    headline_font = fit_font(headline, max_width=1156, start_size=100)

    draw.text((82, 92), "NANOBEASTS", font=eyebrow_font, fill=(*accent, 255))
    draw.rounded_rectangle((82, 144, 252, 153), radius=5, fill=(*accent, 255))
    draw.text((82, 184), headline, font=headline_font, fill=(255, 255, 255, 255))
    draw.text((84, 306), subtitle, font=subtitle_font, fill=(190, 203, 211, 255))

    screen = Image.open(SOURCE_DIR / source_name).convert("RGBA")
    screen_width = 1018
    screen_height = round(screen.height * (screen_width / screen.width))
    screen = screen.resize((screen_width, screen_height), Image.Resampling.LANCZOS)

    frame_x = (CANVAS_SIZE[0] - screen_width) // 2
    frame_y = 470
    radius = 96

    shadow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (frame_x - 28, frame_y - 28, frame_x + screen_width + 28, frame_y + screen_height + 28),
        radius=radius + 24,
        fill=(0, 0, 0, 225),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(46))
    canvas = Image.alpha_composite(canvas, shadow)

    border = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle(
        (frame_x - 18, frame_y - 18, frame_x + screen_width + 18, frame_y + screen_height + 18),
        radius=radius + 18,
        fill=(4, 7, 9, 255),
        outline=(*accent, 120),
        width=5,
    )
    canvas = Image.alpha_composite(canvas, border)

    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_width, screen_height), radius=radius, fill=255)
    canvas.paste(screen, (frame_x, frame_y), mask)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT_DIR / output_name, "PNG", optimize=True)


def main() -> None:
    for screen in SCREENS:
        compose(*screen)


if __name__ == "__main__":
    main()
