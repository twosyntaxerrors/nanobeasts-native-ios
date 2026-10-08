from pathlib import Path
from PIL import Image
import json, shutil
p=Path(__file__).parent
for name in ['glitchlet-idle','evolution']:
 im=Image.open(p/'assets'/f'{name}.webp'); size=384
 sheet=Image.new('RGBA',(size*9,size*9))
 for n in range(im.n_frames):
  im.seek(n);frame=im.convert('RGBA').resize((size,size),Image.Resampling.LANCZOS)
  sheet.paste(frame,((n%9)*size,(n//9)*size))
 sheet.save(p/'assets'/f'{name}-sheet.png',optimize=True)
# Catalog assets and approved art are frozen locally only for rendering.
(p/'.hyperframes'/'asset-provenance.json').write_text(json.dumps({
 'source':'https://assets.nanobeasts.app',
 'creatures':'Nanobeasts/Resources/catalog.json and R2AssetManifest',
 'evolution':'images/evolution-animations-optimized/glitchlet-devicore-evolution-onboarding-v1.webp',
 'route':'Design/RouteReplayVideo-2026-09-08/Route-Replay-2x.mp4, existing in-app export using illustrative demo data',
 'badge':'Design/BadgeAssets/approved/streak-5.png',
 'screens':'Motion reconstruction of current Nanobeasts Home and Field Dex, with illustrative demo progress.',
 'art_changes':'None. Sprites arranged into seekable sheets, preserving their alpha.',
},indent=2))
