#!/usr/bin/env python3
"""Prepare approved expanded-roster videos without changing source files or the app.

The approved Dozolin WebP is copied byte-for-byte. Other assets use its alpha
workflow with reference-palette protection for genuine green body colors.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1]
ROSTER = ROOT / "Design Assets/Expanded Roster"
REVIEW = ROSTER / "Animation Review"
cv2.setNumThreads(1)


def manifest():
    families = json.loads((ROSTER / "names-and-lore.json").read_text())["families"]
    # File assignments were inspected visually; order alone is not a stage ID.
    spec = {
        1: ["Unnamed-01-Egg-Idle", "Unnamed-01-Egg-Hatch", "Unnamed-01-Idle-01", "Unnamed-01-Idle-02", "Unnamed-01-Evo"],
        2: ["Unnamed-02-Egg-Idle", "Unnamed-02-Hatch", "Unnamed-02-Idle-01", "Unnamed-02-Idle-02", "Unnamed-02-Idle-03", "Unnamed-02-Evo-01", "Unnamed-02-Evo-02"],
        3: ["Unnamed-03-Egg-Idle", "Unnamed-03-Hatch", "Unnamed-03-Idle-01", "Unnamed-03-Idle-02", "Unnamed-03-Evo-01"],
        4: ["f349fef7*", "b36807b6*", 6, "e9a47b06*", 4],
        5: [8, 9, 11, 12, 10],
        6: [20, 14, 22, 17, "e3144ef7*", 16, 18],
        7: [3, 7, 4, 5, 6, 12, 11],
        8: [13, 18, 14, 15, 17],
        9: [19, 22, 20, 21, 23],
        10: [24, 27, 25, 26, 28],
        11: [29, 32, 30, 31, 33],
        12: [34, 37, 35, 36, 38],
    }
    records = []
    for fam in families:
        number = fam["number"]
        folder = ROSTER / f"Unnamed Nanobeast {number:02}"
        names = [s["name"].lower() for s in fam["stages"]]
        kinds = [("egg-idle", f"{names[0]}-egg-idle", [0]), ("hatch", f"{names[0]}-hatch", [0, 1])]
        kinds += [("idle", f"{n}-idle", [i+1]) for i, n in enumerate(names)]
        kinds += [("evolution", f"{names[i]}-{names[i+1]}-evolution", [i+1, i+2]) for i in range(len(names)-1)]
        for selector, (kind, key, stages) in zip(spec[number], kinds, strict=True):
            pattern = f"AnimateDiff_{selector:05}-audio" if isinstance(selector, int) else selector
            paths = list((folder / "Animation Inputs").glob(pattern + ".mp4"))
            assert len(paths) == 1, (number, pattern, paths)
            prefix = "Unnamed" if number == 1 else f"Unnamed-{number:02}"
            references = [folder / f"{prefix}-{'egg' if stage == 0 else f'stage-{stage}'}-modern.png" for stage in stages]
            records.append(dict(family=number, kind=kind, key=key, source=str(paths[0]), references=list(map(str, references)), folder=str(folder / "Animation Ready")))
    assert len(records) == 66
    return records


class Keyer:
    def __init__(self, references, key=''):
        self.key = key
        palettes = []
        for p in references:
            a = np.asarray(Image.open(p).convert("RGBA"))
            rgb = a[:, :, :3].astype(float)
            green = (a[:, :, 3] > 250) & (rgb[:, :, 1] > np.maximum(rgb[:, :, 0], rgb[:, :, 2]) + 7)
            colors = rgb[green]
            if len(colors):
                colors = np.unique((colors / 8).round().astype(int), axis=0) * 8
                palettes.append(colors)
        self.palette = np.unique(np.concatenate(palettes), axis=0).astype('float32') if palettes else None
        self.tree = cKDTree(self.palette) if self.palette is not None else None

    def __call__(self, src):
        # Work above the delivery resolution, without paying the full 1024px
        # matting cost for every frame. RGBA is still reduced in premultiplied
        # form to 480px after keying, keeping the outline antialiasing clean.
        if src.shape[0] > 768:
            src = cv2.resize(src,(768,768),interpolation=cv2.INTER_AREA)
        c = src.astype('float32')
        h, w = src.shape[:2]
        scale = h / 480
        border = np.concatenate([c[:8].reshape(-1, 3), c[-8:].reshape(-1, 3), c[:, :8].reshape(-1, 3), c[:, -8:].reshape(-1, 3)])
        # Ignore any artwork or flash crossing the border when estimating screen.
        green_border = border[(border[:, 1] > np.maximum(border[:, 0], border[:, 2]) + 90)]
        bg = np.median(green_border, axis=0) if len(green_border) > 20 else np.array([0, 255, 0], dtype='float32')
        excess = c[:, :, 1] - (c[:, :, 0] + c[:, :, 2]) * .5
        be = max(1, bg[1] - (bg[0] + bg[2]) * .5)
        raw = np.clip((1 - excess / be - .015) / .985, 0, 1)
        ratio = np.maximum(c[:, :, 0], c[:, :, 2]) / np.maximum(c[:, :, 1], 1)
        purity = np.clip((ratio - .09) / .07, 0, 1)
        alpha = raw * purity * purity * (3-2*purity)
        green = np.zeros((h, w), bool)
        if self.tree is not None:
            candidate = (excess > 8) & (ratio > .25) & (c[:, :, 1] < 238)
            if candidate.any():
                distances, _ = self.tree.query(c[candidate], workers=1)
                green[candidate] = distances < 25

        # Retain separate sparks, leaves and smoke, not only the largest object.
        core = ((ratio > .65) | green).astype('uint8')
        count, labels, stats, _ = cv2.connectedComponentsWithStats(core, 8)
        keep = np.flatnonzero(stats[:, cv2.CC_STAT_AREA] >= max(3, int(3*scale*scale)))
        keep = keep[keep != 0]
        core = np.isin(labels, keep).astype('uint8')
        distance = cv2.distanceTransform(1-core, cv2.DIST_L2, 5)
        alpha *= np.clip((30*scale-distance)/(8*scale), 0, 1)
        alpha = np.clip(alpha/.9, 0, 1)
        rgb = np.clip((c - (1-raw[:, :, None])*bg) / np.maximum(raw[:, :, None], .001), 0, 255)
        rgb[raw > .9] = c[raw > .9]
        translucent = raw < .9
        rgb[:, :, 1] = np.where(translucent, np.minimum(rgb[:, :, 1], (rgb[:, :, 0]+rgb[:, :, 2])*.5), rgb[:, :, 1])

        if green.any():
            # Protected pigment remains opaque and ungraded. Recover its mixed
            # boundary with the nearest genuine foreground color, not magenta.
            gd, indices = distance_transform_edt(~green, return_indices=True)
            # Only unmix the external silhouette. Cream veins or metallic
            # seams beside green pigment are solid artwork, not keyed edges.
            bd=cv2.distanceTransform((ratio>.23).astype('uint8'),cv2.DIST_L2,5)
            edge = (gd > 0) & (gd <= 3.5*scale) & (bd <= 3.5*scale)
            if edge.any():
                nearest = c[indices[0][edge], indices[1][edge]]
                ray = nearest-bg
                edge_alpha = np.clip(np.sum((c[edge]-bg)*ray, axis=1)/np.maximum(np.sum(ray*ray, axis=1), 1), 0, 1)
                alpha[edge] = edge_alpha
                rgb[edge] = np.clip((c[edge]-(1-edge_alpha[:, None])*bg)/np.maximum(edge_alpha[:, None], .02), 0, 255)
            alpha[green] = 1
            rgb[green] = c[green]
        alpha = cv2.GaussianBlur(alpha, (0, 0), .4)
        rgb[alpha == 0] = 0
        im = Image.fromarray(np.dstack([rgb, alpha*255]).round().clip(0,255).astype('uint8')).resize((480,480), Image.Resampling.LANCZOS)
        arr = np.asarray(im).copy()
        aa = arr[:, :, 3].astype(float)
        aa[aa > 240] = 255
        aa[aa < 5] = 0
        aa = (aa/255*31).round()/31*255
        arr[:, :, 3] = aa.astype('uint8')
        arr[aa == 0, :3] = 0
        if self.key == 'dozolin-egg-idle':
            # Remove the unwanted detached neutral ground shadow, keeping the
            # colored psychic rings. Restrict by color, location and shape.
            rgb8 = arr[:,:,:3].astype(int)
            dark = (rgb8.max(2)<105) & (rgb8.max(2)-rgb8.min(2)<35) & (arr[:,:,3]>20)
            dark[:375] = False
            count, labels, stats, _ = cv2.connectedComponentsWithStats(dark.astype('uint8'),8)
            for label in range(1,count):
                x,y,ww,hh,area = stats[label]
                if ww>60 and ww/max(hh,1)>2.5 and area>200:
                    mask=cv2.dilate((labels==label).astype('uint8'),np.ones((5,5),np.uint8))>0
                    mask &= (rgb8.max(2)-rgb8.min(2)<60)
                    arr[mask]=0
        return Image.fromarray(arr)


def motion_bridge(a, b, count):
    flow = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    flow.setFinestScale(0)
    ga = cv2.cvtColor(a, cv2.COLOR_RGB2GRAY)
    gb = cv2.cvtColor(b, cv2.COLOR_RGB2GRAY)
    f = flow.calc(ga,gb,None)
    back = flow.calc(gb,ga,None)
    y,x = np.mgrid[:480,:480].astype('float32')
    grid = np.dstack([x,y])
    frames = []
    for j in range(1,count):
        t = j/count
        aa = cv2.remap(a,grid-t*f,None,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
        bb = cv2.remap(b,grid-(1-t)*back,None,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
        frames.append(((1-t)*aa.astype(float)+t*bb.astype(float)).clip(0,255).astype('uint8'))
    return frames


def verify(output, record, fps, source_count, seam_frames):
    im = Image.open(output)
    total = 0
    samples = []
    steps = []
    previous = None
    corner_max = 0
    sample_ids = np.linspace(0, im.n_frames-1, 6).round().astype(int)
    for i in range(im.n_frames):
        im.seek(i);im.load()
        total += im.info['duration']
        a = np.array(im.convert('RGBA'))
        corner_max = max(corner_max, int(max(a[:3,:3,3].max(), a[-3:,:3,3].max(), a[:3,-3:,3].max(), a[-3:,-3:,3].max())))
        composited = a[:,:,:3].astype(float)*(a[:,:,3:4]/255)+(1-a[:,:,3:4]/255)*12
        if previous is not None:
            steps.append(float(np.mean(abs(composited-previous))))
        else:
            first = composited.copy()
        previous = composited
        if i in sample_ids:
            samples.append(im.convert('RGBA').copy())
    seam = float(np.mean(abs(previous-first)))
    assert im.size == (480,480) and im.n_frames > 1 and total > 0
    sheet = Image.new('RGB',(1440,510),(210,210,215))
    for i,frame in enumerate(samples):
        for row,color in enumerate([(12,12,18,255),(244,244,244,255)]):
            base = Image.new('RGBA',(480,480),color);base.alpha_composite(frame);base.thumbnail((240,240))
            sheet.paste(base,(i*240,row*255+15))
    ImageDraw.Draw(sheet).text((5,2),record['key'],fill='black')
    (REVIEW/'Frames').mkdir(parents=True,exist_ok=True)
    sheet.save(REVIEW/'Frames'/f"{record['key']}.jpg",quality=90)
    return dict(family=record['family'],key=record['key'],kind=record['kind'],source=str(Path(record['source']).relative_to(ROSTER)),source_sha256=hashlib.sha256(Path(record['source']).read_bytes()).hexdigest(),output=str(output.relative_to(ROSTER)),width=480,height=480,fps=fps,source_frames=source_count,frames=im.n_frames,duration_ms=total,loop=im.info.get('loop'),bytes=output.stat().st_size,seam_frames=seam_frames,seam_delta=round(seam,3),median_step_delta=round(float(np.median(steps)),3),corner_alpha_max=corner_max)


def process(record):
    out = Path(record['folder']);out.mkdir(exist_ok=True)
    output = out/f"{record['key']}.webp"
    receipt = out/f"{record['key']}.json"
    if record['key'] == 'dozolin-idle':
        approved = ROSTER/'Unnamed Nanobeast 01/Animation Sample/dozolin-idle-sample.webp'
        shutil.copy2(approved,output)
        shutil.copy2(approved.with_name('dozolin-idle-poster.png'),out/'dozolin-idle-poster.png')
        report = verify(output,record,30,152,9)
        report['approved_sample_reused'] = True
    else:
        keyer = Keyer(record['references'],record['key'])
        cap = cv2.VideoCapture(record['source'])
        fps = cap.get(cv2.CAP_PROP_FPS)
        source_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        frames = [];small = []
        while True:
            ok,bgr = cap.read()
            if not ok: break
            rgb = cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
            frames.append(keyer(rgb))
            small.append(cv2.resize(rgb,(480,480),interpolation=cv2.INTER_AREA))
        cap.release()
        assert len(frames) == source_count,record['key']
        seam_frames = 0
        idle = record['kind'] in ('idle','egg-idle')
        if idle:
            # Remove codec-duplicate end holds only; retain authored motion.
            while len(frames)>source_count-5 and np.mean(abs(small[-1].astype(float)-small[-2].astype(float))) < .4:
                frames.pop();small.pop()
            fg = np.asarray(frames[0])[:,:,3] > 32
            fg |= np.asarray(frames[-1])[:,:,3] > 32
            mismatch = np.mean(abs(small[-1].astype(float)-small[0].astype(float))[fg])
            if mismatch > 5:
                bridge = motion_bridge(small[-1],small[0],max(6,round(fps/3)))
                frames.extend(keyer(x) for x in bridge)
                seam_frames = len(bridge)
            elif mismatch < 1 and len(frames)>2:
                frames.pop()
        durations = [round((i+1)*1000/fps)-round(i*1000/fps) for i in range(len(frames))]
        temp = output.with_suffix('.tmp.webp')
        frames[0].save(temp,format='WEBP',save_all=True,append_images=frames[1:],duration=durations,loop=0 if idle else 1,quality=80,method=4,allow_mixed=False,minimize_size=True,exact=True)
        temp.replace(output)
        frames[0].save(out/f"{record['key']}-poster.png",optimize=True)
        if not idle: frames[-1].save(out/f"{record['key']}-last-frame.png",optimize=True)
        del frames,small
        report = verify(output,record,fps,source_count,seam_frames)
    receipt.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report),flush=True)
    return report


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--only',nargs='*')
    parser.add_argument('--workers',type=int,default=2)
    parser.add_argument('--resume',action='store_true')
    args=parser.parse_args()
    REVIEW.mkdir(exist_ok=True)
    records=manifest()
    (REVIEW/'source-manifest.json').write_text(json.dumps(records,indent=2)+'\n')
    if args.only: records=[r for r in records if r['key'] in args.only]
    if args.resume: records=[r for r in records if not (Path(r['folder'])/f"{r['key']}.json").exists()]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(process,records))
    reports=[]
    for r in manifest():
        receipt=Path(r['folder'])/f"{r['key']}.json"
        if receipt.exists():reports.append(json.loads(receipt.read_text()))
    (REVIEW/'asset-verification.json').write_text(json.dumps(reports,indent=2)+'\n')


if __name__=='__main__':main()
