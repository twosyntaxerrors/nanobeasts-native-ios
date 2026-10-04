#!/usr/bin/env python3
"""Decode every exported frame and verify the staged delivery and source hashes."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from prepare_expanded_roster_animations import ROSTER, REVIEW, manifest

reports=[]
for record in manifest():
    folder=Path(record['folder'])
    path=folder/f"{record['key']}.webp"
    if not path.exists():continue
    receipt=folder/f"{record['key']}.json"
    if not receipt.exists():continue
    report=json.loads(receipt.read_text())
    assert report['source_sha256']==hashlib.sha256(Path(record['source']).read_bytes()).hexdigest()
    assert (folder/f"{record['key']}-poster.png").exists()
    if record['kind'] in ('hatch','evolution'):
        assert (folder/f"{record['key']}-last-frame.png").exists()
    im=Image.open(path)
    assert im.size==(480,480)
    assert im.info['loop']==(0 if record['kind'] in ('idle','egg-idle') else 1)
    total=0;residue=0;worst=0;transparent_frames=0
    for i in range(im.n_frames):
        im.seek(i);im.load();total+=im.info['duration']
        a=np.asarray(im.convert('RGBA'))
        # Screen-like chroma, not the muted or yellow greens of the creatures.
        n=int(np.count_nonzero((a[:,:,1]>225)&(a[:,:,0]<35)&(a[:,:,2]<35)&(a[:,:,3]>64)))
        residue+=n;worst=max(worst,n)
        transparent_frames+=int(np.count_nonzero(a[:,:,3]==0)>100)
    assert total==report['duration_ms']
    assert im.n_frames==report['frames']
    report.update(screen_like_pixels=residue,max_screen_like_pixels_per_frame=worst,frames_with_transparency=transparent_frames,source_unchanged=True)
    receipt.write_text(json.dumps(report,indent=2)+'\n')
    reports.append(report)
    print(record['key'],im.n_frames,total,'screen-like pixels',residue,flush=True)
(REVIEW/'asset-verification.json').write_text(json.dumps(reports,indent=2)+'\n')
print('TOTAL',len(reports),'assets;',sum(r['frames'] for r in reports),'frames;',round(sum(r['bytes'] for r in reports)/1048576,1),'MiB')
