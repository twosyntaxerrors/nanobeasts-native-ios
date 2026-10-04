#!/usr/bin/env python3
"""Feather cropped transition effects and contain full-frame white flashes."""
import concurrent.futures
import json
from pathlib import Path
import numpy as np
from PIL import Image
from prepare_expanded_roster_animations import manifest, verify


def contain(record):
    folder=Path(record['folder']);receipt=folder/f"{record['key']}.json"
    if not receipt.exists():return
    previous=json.loads(receipt.read_text())
    if previous.get('edge_effects_contained') or not previous['corner_alpha_max']:return
    output=folder/f"{record['key']}.webp"
    image=Image.open(output);frames=[];durations=[];strengths=[]
    yy,xx=np.mgrid[:480,:480].astype(float)
    distance=np.minimum.reduce([xx,yy,479-xx,479-yy])
    band=distance<16
    edge=np.clip(distance/10,0,1);edge=edge*edge*(3-2*edge)
    radius=np.sqrt(((xx-239.5)/238)**2+((yy-239.5)/238)**2)
    radial=np.clip((1-radius)/.4,0,1);radial=radial*radial*(3-2*radial)
    for i in range(image.n_frames):
        image.seek(i);image.load();a=np.array(image.convert('RGBA'));frames.append(a);durations.append(image.info['duration'])
        white=np.clip((a[:,:,:3].min(2).astype(float)-120)/100,0,1)
        coverage=np.mean(white[band]*a[:,:,3][band]/255)
        strengths.append(float(np.clip(coverage/.25,0,1)))
    # Spread attenuation over adjacent frames, never reduce the peak correction.
    strengths=np.array(strengths)
    padded=np.pad(strengths,1,mode='edge')
    strengths=np.maximum(strengths,.5*np.maximum(padded[:-2],padded[2:]))
    for i,a in enumerate(frames):
        alpha=a[:,:,3].astype(float)*edge*(1-strengths[i]*(1-radial))
        a[:,:,3]=alpha.round().astype('uint8');a[alpha<1,:3]=0
        frames[i]=Image.fromarray(a)
    temp=output.with_suffix('.contained.webp')
    frames[0].save(temp,format='WEBP',save_all=True,append_images=frames[1:],duration=durations,loop=1,quality=82,method=4,allow_mixed=False,minimize_size=True,exact=True)
    temp.replace(output)
    frames[0].save(folder/f"{record['key']}-poster.png",optimize=True)
    frames[-1].save(folder/f"{record['key']}-last-frame.png",optimize=True)
    report=verify(output,record,previous['fps'],previous['source_frames'],0)
    for key in ('pigment_seams_checked', 'pigment_pixels_restored'):
        if key in previous: report[key]=previous[key]
    report.update(edge_effects_contained=True,full_frame_flash_contained=bool(strengths.max()>.8))
    receipt.write_text(json.dumps(report,indent=2)+'\n')
    print(record['key'],'contained',flush=True)


if __name__=='__main__':
    records=[r for r in manifest() if r['kind'] in ('hatch','evolution')]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(contain,records))
