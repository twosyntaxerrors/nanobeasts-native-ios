#!/usr/bin/env python3

"""Compose generated Nanobeast scenes around locked, untouched app UI captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / "AppStoreScreenshots" / "Outcome-Creature-Suite"
GENERATED = SUITE / "Generated"
FINAL = SUITE / "Final-Centered-Interactive"
RAW = ROOT / "AppStoreScreenshots" / "Peggy-Finch-Redesign" / "Raw"

CANVAS = (1320, 2868)
SCENE_TOP = 420
PHONE_Y = 620
PHONE_WIDTH = 1020
PHONE_X = (CANVAS[0] - PHONE_WIDTH) // 2
HEADLINE_FONT = Path("/Library/Fonts/SF-Pro-Rounded-Black.otf")


SCREENS = [
    {
        "scene": "02-bloomwraith-progress-scene.png",
        "raw": "01-home.png",
        "output": "01-make-every-step-feel-rewarding.png",
        "lines": ["MAKE EVERY STEP", "FEEL", "REWARDING"],
        "accent_line": 2,
        "accent": (255, 105, 73, 255),
        "scene_shift": 150,
    },
    {
        "scene": "02-overnode-evolution-scene.png",
        "raw": "02-evolution.png",
        "output": "02-watch-your-progress-come-alive.png",
        "lines": ["WATCH YOUR", "PROGRESS", "COME ALIVE"],
        "accent_line": 2,
        "accent": (121, 224, 178, 255),
        "scene_shift": 150,
        "interaction": "overnode-hand.png",
    },
    {
        "scene": "01-flarva-rewarding-scene.png",
        "raw": "05-insights.png",
        "output": "03-see-your-healthy-habits-add-up.png",
        "lines": ["SEE YOUR HEALTHY", "HABITS", "ADD UP"],
        "accent_line": 2,
        "accent": (255, 205, 58, 255),
        "scene_shift": -150,
    },
    {
        "scene": "03-ampaw-insights-scene.png",
        "raw": "03-dex.png",
        "output": "04-discover-more-the-more-you-move.png",
        "lines": ["DISCOVER MORE", "THE MORE", "YOU MOVE"],
        "accent_line": 0,
        "accent": (255, 120, 88, 255),
        "scene_shift": -150,
        "interaction": "ampaw-arm.png",
    },
    {
        "scene": "05-tutoria-consistency-scene.png",
        "raw": "06-badges.png",
        "output": "05-celebrate-every-win-along-the-way.png",
        "lines": ["CELEBRATE", "EVERY WIN", "ALONG THE WAY"],
        "accent_line": 1,
        "accent": (255, 203, 70, 255),
        "scene_shift": -150,
        "interaction": "tutoria-paw.png",
    },
    {
        "scene": "04-emberspout-discovery-scene.png",
        "raw": "07-eggs.png",
        "output": "06-your-next-discovery-is-waiting.png",
        "lines": ["YOUR NEXT", "DISCOVERY", "IS WAITING"],
        "accent_line": 1,
        "accent": (174, 226, 74, 255),
        "scene_shift": 150,
        "interaction": "emberspout-paw.png",
    },
]


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255
    )
    return mask


def make_background(scene: Image.Image, shift: int) -> Image.Image:
    scene = scene.convert("RGBA")
    scale = CANVAS[0] / scene.width
    scene = scene.resize(
        (CANVAS[0], round(scene.height * scale)), Image.Resampling.LANCZOS
    )

    sample_y = min(110, scene.height - 1)
    sample_box = scene.crop((CANVAS[0] // 2 - 40, sample_y, CANVAS[0] // 2 + 40, sample_y + 80))
    swatch = sample_box.resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
    top = tuple(min(255, round(channel * 1.03 + 3)) for channel in swatch[:3])

    canvas = Image.new("RGBA", CANVAS, (*top, 255))
    draw = ImageDraw.Draw(canvas)
    for y in range(SCENE_TOP):
        t = y / max(1, SCENE_TOP - 1)
        lift = round(14 * (1 - t))
        color = tuple(min(255, channel + lift) for channel in top)
        draw.line((0, y, CANVAS[0], y), fill=(*color, 255))

    fade = Image.new("L", scene.size, 255)
    fade_draw = ImageDraw.Draw(fade)
    fade_height = 160
    for y in range(fade_height):
        fade_draw.line((0, y, scene.width, y), fill=round(255 * y / fade_height))
    scene.putalpha(fade)
    pad = abs(shift) + 4
    extended = Image.new("RGBA", (scene.width + pad * 2, scene.height))
    extended.alpha_composite(scene, (pad, 0))
    left_edge = scene.crop((0, 0, pad, scene.height)).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    right_edge = scene.crop((scene.width - pad, 0, scene.width, scene.height)).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    extended.alpha_composite(left_edge, (0, 0))
    extended.alpha_composite(right_edge, (pad + scene.width, 0))
    crop_left = pad - shift
    shifted_scene = extended.crop((crop_left, 0, crop_left + CANVAS[0], scene.height))
    canvas.alpha_composite(shifted_scene, (0, SCENE_TOP))
    return canvas


def fit_font(text: str, max_width: int, max_size: int = 154) -> ImageFont.FreeTypeFont:
    for size in range(max_size, 80, -2):
        font = ImageFont.truetype(str(HEADLINE_FONT), size)
        box = font.getbbox(text, stroke_width=0)
        if box[2] - box[0] <= max_width:
            return font
    return ImageFont.truetype(str(HEADLINE_FONT), 80)


def draw_headline(
    canvas: Image.Image,
    lines: list[str],
    accent_line: int,
    accent: tuple[int, int, int, int],
) -> None:
    draw = ImageDraw.Draw(canvas)
    y = 68
    max_width = CANVAS[0] - 104
    for index, line in enumerate(lines):
        font = fit_font(line, max_width)
        box = draw.textbbox((0, 0), line, font=font, stroke_width=10)
        width = box[2] - box[0]
        height = box[3] - box[1]
        x = (CANVAS[0] - width) // 2
        fill = accent if index == accent_line else (255, 252, 242, 255)
        draw.text(
            (x + 9, y + 14),
            line,
            font=font,
            fill=(0, 0, 0, 95),
            stroke_width=12,
            stroke_fill=(0, 0, 0, 95),
        )
        draw.text(
            (x, y),
            line,
            font=font,
            fill=fill,
            stroke_width=10,
            stroke_fill=(14, 20, 28, 255),
        )
        y += height + 18


def paste_phone(canvas: Image.Image, source: Path) -> None:
    screen = Image.open(source).convert("RGBA")
    height = round(screen.height * PHONE_WIDTH / screen.width)
    screen = screen.resize((PHONE_WIDTH, height), Image.Resampling.LANCZOS)
    radius = round(PHONE_WIDTH * 0.084)

    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (PHONE_X - 30, PHONE_Y - 26, PHONE_X + PHONE_WIDTH + 30, PHONE_Y + height + 34),
        radius=radius + 28,
        fill=(0, 0, 0, 205),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(38))
    canvas.alpha_composite(shadow)

    frame = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (PHONE_X - 16, PHONE_Y - 16, PHONE_X + PHONE_WIDTH + 16, PHONE_Y + height + 16),
        radius=radius + 16,
        fill=(5, 7, 9, 255),
        outline=(55, 61, 67, 255),
        width=5,
    )
    canvas.alpha_composite(frame)
    canvas.paste(screen, (PHONE_X, PHONE_Y), rounded_mask(screen.size, radius))


def paste_interaction(canvas: Image.Image, source: Path, shift: int) -> None:
    interaction = Image.open(source).convert("RGBA")
    scale = CANVAS[0] / interaction.width
    interaction = interaction.resize(
        (CANVAS[0], round(interaction.height * scale)), Image.Resampling.LANCZOS
    )
    canvas.alpha_composite(interaction, (shift, SCENE_TOP))


def compose(screen: dict) -> Path:
    canvas = make_background(
        Image.open(GENERATED / screen["scene"]), screen["scene_shift"]
    )
    draw_headline(canvas, screen["lines"], screen["accent_line"], screen["accent"])
    paste_phone(canvas, RAW / screen["raw"])
    if screen.get("interaction"):
        paste_interaction(
            canvas,
            SUITE / "Character-Layers" / screen["interaction"],
            screen["scene_shift"],
        )
    FINAL.mkdir(parents=True, exist_ok=True)
    destination = FINAL / screen["output"]
    canvas.convert("RGB").save(destination, "PNG", compress_level=5)
    return destination


if __name__ == "__main__":
    for item in SCREENS:
        print(compose(item))
