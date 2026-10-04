#!/usr/bin/env python3
"""Key the approved green-screen professor loops and prepare remote app assets."""

import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Design/Professor-Onboarding-2026-09-08/R2"
OUTPUT = ROOT / "Design/Professor-Animation-2026-09-10"
POSES = ("welcome", "walking", "research")


def run(*args):
    subprocess.run(args, check=True)


def main():
    (OUTPUT / "Upload").mkdir(parents=True, exist_ok=True)
    records = []
    for index, pose in enumerate(POSES, start=1):
        work = OUTPUT / "Work" / pose
        work.mkdir(parents=True, exist_ok=True)
        alpha_movie = OUTPUT / "Work" / f"{pose}-alpha.mkv"
        source = SOURCE / f"Professor_Onboarding_{index}.mp4"
        # A repeated source supplies actual neighbouring frames at the loop seam.
        # Motion compensation inserts in-between frames; it does not slow the clip.
        if not alpha_movie.exists():
            run("ffmpeg", "-v", "error", "-threads", "2", "-stream_loop", "1",
                "-i", str(source), "-vf",
                "scale=640:640:flags=lanczos,"
                "minterpolate=fps=32:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:"
                "vsbmc=1:mb_size=8:search_param=16,"
                "chromakey=0x00EC03:0.13:0.07,format=rgba,despill=green",
                "-t", "5.0625", "-c:v", "ffv1", "-pix_fmt", "bgra", "-y", str(alpha_movie))

        # 80 authored intervals, 160 output frames. Exclude the duplicate end pose.
        run("ffmpeg", "-v", "error", "-i", str(alpha_movie), "-frames:v", "160",
            "-vf", "crop=528:640:56:0", "-y", str(work / "frame-%03d.png"))
        paths = sorted(work.glob("frame-*.png"))[:160]
        frames = [Image.open(path).convert("RGBA") for path in paths]
        assert len(frames) == 160
        # WebP stores integer milliseconds. Round cumulative times, not each frame.
        durations = [round((i + 1) * 1000 / 32) - round(i * 1000 / 32) for i in range(160)]
        output = OUTPUT / "Upload" / f"professor-nano-{pose}-idle-v1.webp"
        frames[0].save(output, format="WEBP", save_all=True, append_images=frames[1:],
                       duration=durations, loop=0, quality=90, method=4,
                       minimize_size=False, allow_mixed=True, exact=True)
        poster = OUTPUT / "Upload" / f"professor-nano-{pose}-idle-poster-v1.png"
        frames[0].save(poster, optimize=True)

        dark_frames = []
        for i in (0, 40, 80, 120, 159):
            dark = Image.new("RGBA", frames[i].size, (6, 12, 14, 255))
            dark.alpha_composite(frames[i])
            dark.thumbnail((264, 320))
            dark_frames.append(dark)
        sheet = Image.new("RGB", (264 * 5, 320), (6, 12, 14))
        for i, dark in enumerate(dark_frames):
            sheet.paste(dark, (264 * i, 0))
        sheet.save(OUTPUT / "Review" / f"{pose}-dark.png")

        with Image.open(output) as decoded:
            total = 0
            for i in range(decoded.n_frames):
                decoded.seek(i)
                decoded.load()
                total += decoded.info["duration"]
                rgba = np.asarray(decoded.convert("RGBA"))
                assert rgba[0, 0, 3] == 0, (pose, i, "nontransparent corner")
                assert rgba[:, :, 3].max() == 255, (pose, i, "lost opaque subject")
            records.append(dict(pose=pose, file=output.name, width=decoded.width,
                                height=decoded.height, frames=decoded.n_frames,
                                duration_ms=total, loop=decoded.info.get("loop"),
                                bytes=output.stat().st_size,
                                sha256=hashlib.sha256(output.read_bytes()).hexdigest()))
        for frame in frames:
            frame.close()
        print(json.dumps(records[-1]), flush=True)
    (OUTPUT / "asset-verification.json").write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    main()
