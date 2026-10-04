#!/usr/bin/env python3
"""Restore source-colored internal seams that were mistaken for green edges.

This is bounded to non-magenta source pixels inside the solid foreground,
beside reference-matched green pigment, that became magenta during keying.
The approved Dozolin sample and real pink/purple artwork are excluded.
"""
import concurrent.futures
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from prepare_expanded_roster_animations import Keyer, manifest, motion_bridge, verify


def repair(record):
    if record['key']=='dozolin-idle':return
    folder=Path(record['folder']);receipt=folder/f"{record['key']}.json"
    if not receipt.exists():return
    previous=json.loads(receipt.read_text())
    if previous.get('pigment_seams_checked'):return
    keyer=Keyer(record['references'])
    if keyer.tree is None:
        previous['pigment_seams_checked']=True;previous['pigment_pixels_restored']=0
        receipt.write_text(json.dumps(previous,indent=2)+'\n');return
    cap=cv2.VideoCapture(record['source']);source=[]
    while True:
        ok,bgr=cap.read()
        if not ok:break
        source.append(cv2.resize(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB),(480,480),interpolation=cv2.INTER_AREA))
    cap.release()
    count=round(previous['duration_ms']*previous['fps']/1000)
    retained=count-previous['seam_frames']
    if previous['seam_frames']:
        source=source[:retained]+motion_bridge(source[retained-1],source[0],previous['seam_frames']+1)
    output=folder/f"{record['key']}.webp"
    im=Image.open(output);frames=[];durations=[];elapsed=0;changed=0
    for i in range(im.n_frames):
        im.seek(i);im.load();out=np.array(im.convert('RGBA'));duration=im.info['duration']
        index=min(len(source)-1,round(elapsed*previous['fps']/1000));elapsed+=duration
        src=source[index].astype('float32');rgb=out[:,:,:3].astype('float32')
        ratio=np.maximum(src[:,:,0],src[:,:,2])/np.maximum(src[:,:,1],1)
        interior=cv2.distanceTransform((ratio>.23).astype('uint8'),cv2.DIST_L2,5)>4
        # Identify only newly introduced magenta, not natural purple markings.
        bad=((rgb[:,:,0]+rgb[:,:,2])*.5-rgb[:,:,1]>25)&((src[:,:,0]+src[:,:,2])*.5-src[:,:,1]<10)&interior
        bad[:20]=False;bad[-20:]=False;bad[:,:20]=False;bad[:,-20:]=False
        if bad.any():
            candidates=(src[:,:,1]-np.maximum(src[:,:,0],src[:,:,2])>7)&(ratio>.25)&(src[:,:,1]<238)
            green=np.zeros((480,480),np.uint8)
            if candidates.any():
                distances,_=keyer.tree.query(src[candidates],workers=1);green[candidates]=(distances<25).astype('uint8')
            if green.any():
                proximity=cv2.distanceTransform(1-green,cv2.DIST_L2,5)
                bad &= proximity<5
                if bad.any():
                    # Include antialiasing from the erroneous internal stroke.
                    mask=cv2.dilate(bad.astype('uint8'),np.ones((3,3),np.uint8))>0
                    mask &= interior & ((src[:,:,0]+src[:,:,2])*.5-src[:,:,1]<15)
                    changed+=int(mask.sum())
                    out[mask,:3]=src[mask].astype('uint8');out[mask,3]=255
        frames.append(Image.fromarray(out));durations.append(duration)
    if changed:
        temp=output.with_suffix('.repaired.webp')
        frames[0].save(temp,format='WEBP',save_all=True,append_images=frames[1:],duration=durations,loop=previous['loop'],quality=82,method=4,allow_mixed=False,minimize_size=True,exact=True)
        temp.replace(output)
        frames[0].save(folder/f"{record['key']}-poster.png",optimize=True)
        if record['kind'] in ('hatch','evolution'):frames[-1].save(folder/f"{record['key']}-last-frame.png",optimize=True)
        report=verify(output,record,previous['fps'],previous['source_frames'],previous['seam_frames'])
        for field in ('edge_effects_contained','full_frame_flash_contained'):
            if field in previous:report[field]=previous[field]
    else:report=previous
    report.update(pigment_seams_checked=True,pigment_pixels_restored=changed)
    receipt.write_text(json.dumps(report,indent=2)+'\n')
    print(record['key'],changed,'interior pixels restored',flush=True)


if __name__=='__main__':
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:list(pool.map(repair,manifest()))
