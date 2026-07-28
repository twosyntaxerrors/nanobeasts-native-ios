#!/usr/bin/env python3

"""Assemble an ordered directory of transparent PNG frames into animated WebP."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("frames_directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frame-duration-ms", type=int, default=33)
    parser.add_argument("--quality", type=int, default=88)
    parser.add_argument("--method", type=int, default=3)
    args = parser.parse_args()

    frame_paths = sorted(args.frames_directory.glob("frame-*.png"))
    if not frame_paths:
        raise SystemExit(f"No frame-*.png files found in {args.frames_directory}")

    frames = [Image.open(path).convert("RGBA") for path in frame_paths]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        args.output,
        format="WEBP",
        save_all=True,
        append_images=frames[1:],
        duration=args.frame_duration_ms,
        loop=0,
        quality=args.quality,
        method=args.method,
        minimize_size=False,
        allow_mixed=True,
        exact=True,
    )

    for frame in frames:
        frame.close()


if __name__ == "__main__":
    main()
