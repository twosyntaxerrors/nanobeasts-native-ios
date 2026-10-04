#!/usr/bin/env python3
"""Preserve the approved Gemini illustrations while extracting transparent PNGs.

Ink contours bound the opaque character, including the white coat and notebook.
No illustration pixels are generated. Originals remain untouched.
"""
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Design/Onboarding-Artwork-2026-09-08/Gemini'
OUTPUT = ROOT / 'Design/Professor-Onboarding-2026-09-08/R2'
SOURCES = {
    'welcome': 'Professor-Nano-Concept-01.jpg',
    'walking': 'Professor-Nano-Walking-02.jpg',
    'research': 'Professor-Nano-Research-03.jpg',
}
OUTPUT.mkdir(parents=True, exist_ok=True)
report = []
previews = []
for pose, filename in SOURCES.items():
    rgb = np.array(Image.open(SOURCE / filename).convert('RGB'))
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    ink = (gray < 175).astype(np.uint8) * 255
    ink = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, np.ones((3, 3),np.uint8))
    contours, _ = cv2.findContours(ink, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    matte = np.zeros(gray.shape, np.uint8)
    body = max(contours, key=cv2.contourArea)
    cv2.drawContours(matte, [body], -1, 255, cv2.FILLED)
    if pose == 'walking':
        # Preserve the disconnected cyan footprints and their curved trail.
        cyan = ((rgb[:,:,1].astype(int)-rgb[:,:,0]) > 20) & ((rgb[:,:,2].astype(int)-rgb[:,:,0]) > 15)
        cyan = cyan.astype(np.uint8)*255
        cyan = cv2.morphologyEx(cyan, cv2.MORPH_CLOSE, np.ones((3,3), np.uint8))
        parts,_=cv2.findContours(cyan,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
        for contour in parts:
            if cv2.contourArea(contour)>25:
                cv2.drawContours(matte,[contour],-1,255,cv2.FILLED)
    # A subpixel edge softens the contour without a white fringe.
    alpha=cv2.GaussianBlur(matte,(0,0),0.55)
    alpha[alpha<12]=0
    alpha[alpha>243]=255
    ys,xs=np.where(alpha>0)
    margin=24
    bounds=(max(0,int(xs.min())-margin),max(0,int(ys.min())-margin),
            min(rgb.shape[1],int(xs.max())+margin+1),min(rgb.shape[0],int(ys.max())+margin+1))
    rgba=np.dstack((rgb,alpha))
    rgba[alpha==0,:3]=0
    image=Image.fromarray(rgba).crop(bounds)
    path=OUTPUT / f'professor-nano-{pose}-v1.png'
    image.save(path,optimize=True)
    proof=Image.new('RGBA',image.size,(8,12,15,255))
    proof.alpha_composite(image)
    proof.convert('RGB').save(OUTPUT/f'{pose}-dark-preview.jpg',quality=95)
    thumb=proof.convert('RGB')
    thumb.thumbnail((380,650),Image.Resampling.LANCZOS)
    panel=Image.new('RGB',(420,720),(8,12,15))
    panel.paste(thumb,((420-thumb.width)//2,45))
    ImageDraw.Draw(panel).text((24,16),pose.upper(),fill=(82,224,208))
    previews.append(panel)
    report.append({'pose':pose,'source':filename,'output':path.name,'size':image.size,'mode':image.mode,'alpha_extrema':image.getchannel('A').getextrema(),'bytes':path.stat().st_size,'crop':bounds})
proof=Image.new('RGB',(1260,720),(8,12,15))
for i,panel in enumerate(previews):proof.paste(panel,(420*i,0))
proof.save(OUTPUT/'cutout-review.jpg',quality=95)
(OUTPUT/'asset-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
