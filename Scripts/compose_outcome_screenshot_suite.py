#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SUITE_DIR = ROOT / "AppStoreScreenshots" / "Outcome-Suite"
RAW_DIR = SUITE_DIR / "Raw"
ASSET_DIR = SUITE_DIR / "Assets"
OUTPUT_DIR = SUITE_DIR / "Polished"
CANVAS_SIZE = (1320, 2868)

DISPLAY_FONT = Path("/Library/Fonts/SF-Pro-Display-Bold.otf")
TEXT_FONT = Path("/Library/Fonts/SF-Pro-Text-Medium.otf")
MONO_FONT = ROOT / "Nanobeasts" / "Resources" / "Fonts" / "Aldrich_400Regular.ttf"

SCREENS = [
    {
        "source": "05-stats.png",
        "output": "05-see-how-far-youve-come.png",
        "headline": "SEE HOW FAR\nYOU’VE COME",
        "subtitle": "Six months of movement, visible at a glance.",
        "accent": (66, 226, 203),
        "creatures": [
            ("overnode.png", 912, 410, 448, -5, False),
        ],
    },
    {
        "source": "06-insights.png",
        "output": "06-find-your-winning-rhythm.png",
        "headline": "FIND YOUR\nWINNING RHYTHM",
        "subtitle": "See the patterns that make stronger days easier.",
        "accent": (33, 211, 239),
        "creatures": [
            ("devicore.png", 936, 1260, 420, 7, False),
        ],
    },
    {
        "source": "07-dex.png",
        "output": "07-turn-steps-into-a-living-world.png",
        "headline": "TURN STEPS INTO\nA LIVING WORLD",
        "subtitle": "Every walk brings another Nanobeast to life.",
        "accent": (255, 201, 62),
        "creatures": [
            ("tutoria.png", -68, 1160, 360, -8, False),
            ("ampaw.png", 1020, 1430, 350, 8, True),
        ],
    },
    {
        "source": "08-dex-detail.png",
        "output": "08-become-something-stronger.png",
        "headline": "BECOME SOMETHING\nSTRONGER",
        "subtitle": "Each active day moves your next evolution closer.",
        "accent": (157, 103, 255),
        "creatures": [
            ("overnode.png", 854, 392, 520, -4, False),
        ],
    },
]


def background(accent: tuple[int, int, int]) -> Image.Image:
    width, height = CANVAS_SIZE
    image = Image.new("RGB", CANVAS_SIZE)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        progress = y / max(height - 1, 1)
        color = (
            int(4 + accent[0] * 0.05 * (1 - progress)),
            int(8 + accent[1] * 0.13 * (1 - progress)),
            int(12 + accent[2] * 0.10 * (1 - progress)),
        )
        draw.line((0, y, width, y), fill=color)

    glow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((-220, 100, 1540, 1790), fill=(*accent, 45))
    glow = glow.filter(ImageFilter.GaussianBlur(250))
    image = Image.alpha_composite(image.convert("RGBA"), glow)

    grid = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    for x in range(0, width, 94):
        grid_draw.line((x, 0, x, height), fill=(*accent, 13), width=1)
    for y in range(0, height, 94):
        grid_draw.line((0, y, width, y), fill=(*accent, 13), width=1)
    return Image.alpha_composite(image, grid)


def fit_font(lines: str, max_width: int, start_size: int) -> ImageFont.FreeTypeFont:
    size = start_size
    while size > 58:
        font = ImageFont.truetype(str(DISPLAY_FONT), size=size)
        widest = max(font.getlength(line) for line in lines.splitlines())
        if widest <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(DISPLAY_FONT), size=size)


def paste_creature(
    canvas: Image.Image,
    filename: str,
    x: int,
    y: int,
    width: int,
    angle: float,
    flip: bool,
) -> Image.Image:
    creature = Image.open(ASSET_DIR / filename).convert("RGBA")
    if flip:
        creature = creature.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    creature = creature.resize((width, width), Image.Resampling.LANCZOS)
    if angle:
        creature = creature.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)

    alpha = creature.getchannel("A")
    shadow = Image.new("RGBA", creature.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(24)))
    shadow_color = Image.new("RGBA", creature.size, (0, 0, 0, 190))
    shadow_color.putalpha(shadow.getchannel("A"))
    canvas.alpha_composite(shadow_color, (x + 18, y + 28))
    canvas.alpha_composite(creature, (x, y))
    return canvas


def compose(config: dict) -> None:
    accent = config["accent"]
    canvas = background(accent)
    draw = ImageDraw.Draw(canvas)

    eyebrow_font = ImageFont.truetype(str(MONO_FONT), size=30)
    headline_font = fit_font(config["headline"], max_width=1100, start_size=99)
    subtitle_font = ImageFont.truetype(str(TEXT_FONT), size=38)

    draw.text((78, 72), "NANOBEASTS", font=eyebrow_font, fill=(*accent, 255))
    draw.rounded_rectangle((78, 121, 248, 130), radius=5, fill=(*accent, 255))
    draw.multiline_text(
        (78, 164),
        config["headline"],
        font=headline_font,
        fill=(255, 255, 255, 255),
        spacing=-8,
    )
    draw.text((81, 404), config["subtitle"], font=subtitle_font, fill=(194, 207, 214, 255))

    screen = Image.open(RAW_DIR / config["source"]).convert("RGBA")
    screen_width = 1032
    screen_height = round(screen.height * (screen_width / screen.width))
    screen = screen.resize((screen_width, screen_height), Image.Resampling.LANCZOS)

    frame_x = (CANVAS_SIZE[0] - screen_width) // 2
    frame_y = 552
    radius = 96

    shadow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (frame_x - 30, frame_y - 30, frame_x + screen_width + 30, frame_y + screen_height + 30),
        radius=radius + 24,
        fill=(0, 0, 0, 230),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(48))
    canvas = Image.alpha_composite(canvas, shadow)

    frame = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (frame_x - 18, frame_y - 18, frame_x + screen_width + 18, frame_y + screen_height + 18),
        radius=radius + 18,
        fill=(3, 6, 9, 255),
        outline=(*accent, 160),
        width=5,
    )
    canvas = Image.alpha_composite(canvas, frame)

    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_width, screen_height), radius=radius, fill=255)
    canvas.paste(screen, (frame_x, frame_y), mask)

    for creature in config["creatures"]:
        canvas = paste_creature(canvas, *creature)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT_DIR / config["output"], "PNG", optimize=True)


def main() -> None:
    for config in SCREENS:
        compose(config)


if __name__ == "__main__":
    main()
