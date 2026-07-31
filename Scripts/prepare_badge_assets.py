#!/usr/bin/env python3
"""Extract approved badge art from white review canvases.

The generated concepts contain white highlights inside closed black keylines.
A global white chroma key would erase those highlights, so this script removes
only white/near-white pixels connected to the outside border, then normalizes
every badge to the same visual scale on a transparent square canvas.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def border_color(rgb: np.ndarray) -> np.ndarray:
    band = max(2, min(rgb.shape[0], rgb.shape[1]) // 256)
    samples = np.concatenate(
        (
            rgb[:band, :, :].reshape(-1, 3),
            rgb[-band:, :, :].reshape(-1, 3),
            rgb[:, :band, :].reshape(-1, 3),
            rgb[:, -band:, :].reshape(-1, 3),
        ),
        axis=0,
    )
    return np.median(samples, axis=0)


def extract_badge(source: Path, destination: Path, size: int) -> None:
    image = Image.open(source).convert("RGBA")
    pixels = np.asarray(image).copy()
    rgb = pixels[:, :, :3].astype(np.int16)

    key = border_color(rgb)
    distance = np.max(np.abs(rgb - key), axis=2)

    # The black illustrated keyline closes around the badge. Propagating only
    # through near-background pixels protects enclosed white enamel highlights.
    candidate = distance <= 105
    seeds = np.zeros(candidate.shape, dtype=bool)
    seeds[0, :] = candidate[0, :]
    seeds[-1, :] = candidate[-1, :]
    seeds[:, 0] = candidate[:, 0]
    seeds[:, -1] = candidate[:, -1]
    background = ndimage.binary_propagation(
        seeds,
        structure=ndimage.generate_binary_structure(2, 1),
        mask=candidate,
    )

    alpha = pixels[:, :, 3]
    alpha[background] = 0

    # Preserve the illustrated outline while lightly antialiasing the first
    # non-background pixel ring.
    edge = ndimage.binary_dilation(background, iterations=1) & ~background
    edge_alpha = np.clip((distance.astype(np.float32) - 60.0) / 80.0, 0, 1)
    alpha[edge] = np.minimum(
        alpha[edge],
        np.rint(edge_alpha[edge] * 255).astype(np.uint8),
    )
    pixels[:, :, 3] = alpha
    image = Image.fromarray(pixels, mode="RGBA")

    alpha_image = image.getchannel("A")
    bounds = alpha_image.getbbox()
    if bounds is None:
        raise ValueError(f"No foreground remained after extraction: {source}")

    cropped = image.crop(bounds)
    content_side = max(cropped.size)
    padding = max(8, round(content_side * 0.075))
    canvas_side = content_side + padding * 2
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    origin = (
        (canvas_side - cropped.width) // 2,
        (canvas_side - cropped.height) // 2,
    )
    canvas.alpha_composite(cropped, origin)
    canvas = canvas.resize((size, size), Image.Resampling.LANCZOS)

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--size", type=int, default=1024)
    args = parser.parse_args()

    root = args.manifest.resolve().parents[2]
    sources: dict[str, str] = json.loads(args.manifest.read_text())
    for badge_id, relative_source in sources.items():
        source = root / relative_source
        destination = args.output / f"{badge_id}.png"
        extract_badge(source, destination, args.size)
        print(f"{badge_id}: {destination}")


if __name__ == "__main__":
    main()
