#!/usr/bin/env python3
"""Verify the published bytes and MIME type for every approved roster asset."""
import concurrent.futures
import hashlib
import json
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DELIVERY = ROOT / 'Design Assets/Expanded Roster/R2 Delivery'

def verify(asset):
    url = 'https://assets.nanobeasts.app/' + asset['key']
    error = None
    for attempt in range(3):
        try:
            with tempfile.TemporaryDirectory(prefix='r2-asset-check-') as temp:
                target = Path(temp) / asset['file']
                response = subprocess.run(['curl', '--silent', '--show-error', '--fail',
                    '--max-time', '60', '--output', str(target), '--write-out', '%{http_code} %{content_type}', url],
                    capture_output=True, text=True, check=True)
                status_text, mime = response.stdout.strip().split(' ', 1)
                status = int(status_text)
                data = target.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            assert status == 200
            assert digest == asset['sha256'], 'Public bytes differ from approved file'
            assert len(data) == asset['bytes']
            assert mime == ('image/png' if asset['file'].endswith('.png') else 'image/webp'), mime
            print('VERIFIED', asset['file'], flush=True)
            return {'url': url, 'status': status, 'mime': mime, 'bytes': len(data), 'sha256': digest, 'matches_local': True}
        except Exception as exc:
            error = str(exc)
            if attempt < 2: time.sleep(2)
    print('FAILED', asset['file'], error, flush=True)
    return {'url': url, 'matches_local': False, 'error': error}

if __name__ == '__main__':
    assets = json.loads((DELIVERY / 'upload-manifest.json').read_text())
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(verify, assets))
    (DELIVERY / 'r2-public-verification.json').write_text(json.dumps(results, indent=2) + '\n')
    failures = [r for r in results if not r['matches_local']]
    print(f'{len(results)-len(failures)}/{len(results)} public assets verified.')
    raise SystemExit(bool(failures))
