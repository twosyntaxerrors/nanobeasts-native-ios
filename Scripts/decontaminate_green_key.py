#!/usr/bin/env python3
"""Remove green-screen contamination from partially transparent keyed edges."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def decontaminate(source: Path, destination: Path) -> None:
    rgba = np.asarray(Image.open(source).convert("RGBA"), dtype=np.float32)
    rgb = rgba[..., :3]
    alpha = rgba[..., 3:4] / 255.0

    transparent = Image.fromarray(
        np.where(alpha[..., 0] < 0.08, 255, 0).astype(np.uint8),
        mode="L",
    )
    near_transparent = np.asarray(
        transparent.filter(ImageFilter.MaxFilter(7)),
        dtype=np.uint8,
    )[..., None] > 0

    # The video encoder can leave a one-pixel opaque green rim that the
    # chroma-distance alpha does not catch. Only suppress strongly green pixels
    # touching transparency, so genuine green details inside a creature remain.
    green_dominance = rgb[..., 1:2] - np.maximum(rgb[..., 0:1], rgb[..., 2:3])
    rim_strength = np.clip((green_dominance - 18.0) / 170.0, 0.0, 1.0)
    alpha = np.where(near_transparent, alpha * (1.0 - rim_strength), alpha)

    safe_alpha = np.maximum(alpha, 0.035)
    background = np.array([0.0, 255.0, 0.0], dtype=np.float32)
    recovered = (rgb - ((1.0 - alpha) * background)) / safe_alpha

    # Fully opaque pixels are copied verbatim. This is important for yellow
    # creatures: a global green despill turns their intended yellow into orange.
    edge = (alpha > 0.015) & (alpha < 0.995)
    cleaned = np.where(edge, recovered, rgb)
    cleaned = np.clip(cleaned, 0.0, 255.0)
    cleaned = np.where(alpha > 0.015, cleaned, 0.0)

    output = np.concatenate((cleaned, rgba[..., 3:4]), axis=2).astype(np.uint8)
    destination.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(output, mode="RGBA").save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    frames = sorted(args.input_dir.glob("frame-*.png"))
    if not frames:
        raise SystemExit(f"No frame-*.png files found in {args.input_dir}")

    for frame in frames:
        decontaminate(frame, args.output_dir / frame.name)

    print(f"Processed {len(frames)} keyed frames into {args.output_dir}")


if __name__ == "__main__":
    main()
