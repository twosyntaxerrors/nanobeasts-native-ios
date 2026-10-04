#!/usr/bin/env python3

"""Create a review copy of the current iPhone App Store screenshots with shorter headlines."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "AppStoreScreenshots" / "Current-ASC-2026-09-08" / "iPhone"
OUTPUT_DIR = ROOT / "AppStoreScreenshots" / "Headline-Revision-2026-09-11"

CANVAS_SIZE = (1290, 2796)
HEADLINE_FONT = Path("/Library/Fonts/SF-Pro-Rounded-Black.otf")

SCREENS = [
    ("01-home-bloomwraith-v1.png", "COLLECT CREATURES\nWITH REAL STEPS"),
    ("02-evolution-devicore-v3.png", "SEE YOUR CREATURES\nEVOLVE"),
    ("03-insights-flarva-v1.png", "WATCH YOUR\nCOLLECTION GROW"),
    ("04-dex-ampaw-v1.png", "DISCOVER NEW\nCREATURES"),
    ("05-badges-emberspout-hit-goals.png", "EARN BADGES\nAS YOU WALK"),
    ("06-eggs-tutoria-v2.png", "CHOOSE YOUR\nNEXT EGG"),
    ("07-stats-ampact-v4.png", "TRACK YOUR\nDAILY STEPS"),
    ("08-profile-overnode-v3.png", "LEARN ABOUT\nEACH CREATURE"),
    ("09-completed-outdoor-walk.png", "TRACK YOUR\nWALKS"),
]


HEADLINE_BANDS = {
    "01-home-bloomwraith-v1.png": (58, 700, 780),
    "02-evolution-devicore-v3.png": (58, 620, 700),
    "03-insights-flarva-v1.png": (58, 740, 790),
    "04-dex-ampaw-v1.png": (58, 700, 780),
    "05-badges-emberspout-hit-goals.png": (58, 620, 700),
    "06-eggs-tutoria-v2.png": (58, 650, 730),
    "07-stats-ampact-v4.png": (58, 650, 730),
    "08-profile-overnode-v3.png": (58, 650, 730),
    "09-completed-outdoor-walk.png": (58, 660, 740),
}


def clean_headline_area(image: Image.Image, source_name: str) -> Image.Image:
    """Replace the old raster headline with a scene-tinted title band.

    The source screenshots have the original headline baked into the pixels, so
    a normal blur/inpaint pass leaves letter-shaped ghosts behind. This darkened,
    scene-tinted band is intentional: it gives the replacement copy a clean
    canvas without cutting through the creature or phone artwork.
    """
    source = np.asarray(image.convert("RGB"))
    cover_start, cover_end, fade_end = HEADLINE_BANDS[source_name]

    # Build a smooth, scene-tinted gradient from clean outer-margin colors.
    # Unlike stretching a textured crop, this keeps the title area calm and
    # avoids introducing artificial bands or repeating background details.
    edge_width = 90
    edge_pixels = np.concatenate(
        [source[:fade_end, :edge_width], source[:fade_end, -edge_width:]], axis=1
    ).astype(np.float32)
    top_color = np.median(edge_pixels[:cover_start], axis=(0, 1))
    bottom_color = np.median(edge_pixels[max(0, cover_end - 90) : cover_end], axis=(0, 1))
    panel = np.zeros((fade_end, source.shape[1], 3), dtype=np.float32)
    for y in range(fade_end):
        progress = max(0.0, min(1.0, (y - cover_start) / max(1, fade_end - cover_start)))
        color = top_color * (1.0 - progress) + bottom_color * progress
        panel[y] = color

    alpha = np.zeros((source.shape[0], 1, 1), dtype=np.float32)
    ramp_end = cover_start + 25
    for y in range(cover_start, fade_end):
        if y < ramp_end:
            alpha[y, 0, 0] = (y - cover_start) / (ramp_end - cover_start)
        elif y < cover_end:
            alpha[y, 0, 0] = 1.0
        else:
            alpha[y, 0, 0] = 1.0 - (y - cover_end) / (fade_end - cover_end)

    result = source.astype(np.float32)
    result[:fade_end] = np.clip(
        panel * alpha[:fade_end] + source[:fade_end].astype(np.float32) * (1.0 - alpha[:fade_end]),
        0,
        255,
    )
    return Image.fromarray(result.astype(np.uint8), mode="RGB")


def fit_font(draw: ImageDraw.ImageDraw, lines: list[str]) -> ImageFont.FreeTypeFont:
    for size in range(145, 70, -2):
        font = ImageFont.truetype(str(HEADLINE_FONT), size=size)
        widths = [draw.textbbox((0, 0), line, font=font, stroke_width=0)[2] for line in lines]
        if max(widths) <= 1160:
            return font
    return ImageFont.truetype(str(HEADLINE_FONT), size=70)


def draw_headline(image: Image.Image, headline: str) -> Image.Image:
    canvas = image.convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    lines = headline.splitlines()
    font = fit_font(draw, lines)
    line_boxes = [draw.textbbox((0, 0), line, font=font, stroke_width=0) for line in lines]
    line_heights = [box[3] - box[1] for box in line_boxes]
    total_height = sum(line_heights) + 18 * (len(lines) - 1)
    y = max(72, min(125, 365 - total_height // 2))

    for line, box, height in zip(lines, line_boxes, line_heights):
        width = box[2] - box[0]
        x = (CANVAS_SIZE[0] - width) // 2
        draw.text(
            (x + 8, y + 14),
            line,
            font=font,
            fill=(0, 0, 0, 110),
            stroke_width=13,
            stroke_fill=(0, 0, 0, 110),
        )
        draw.text(
            (x, y),
            line,
            font=font,
            fill=(255, 252, 242, 255),
            stroke_width=10,
            stroke_fill=(14, 20, 28, 255),
        )
        y += height + 18
    return canvas.convert("RGB")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = []
    for source_name, headline in SCREENS:
        source_path = SOURCE_DIR / source_name
        destination = OUTPUT_DIR / source_name
        image = Image.open(source_path).resize(CANVAS_SIZE, Image.Resampling.LANCZOS)
        image = draw_headline(clean_headline_area(image, source_name), headline)
        image.save(destination, "PNG", compress_level=6)
        manifest.append(f"{source_name}\t{headline.replace(chr(10), ' / ')}")
        print(destination)
    (OUTPUT_DIR / "headlines.txt").write_text("\n".join(manifest) + "\n")


if __name__ == "__main__":
    main()
