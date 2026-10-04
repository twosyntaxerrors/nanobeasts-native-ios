#!/usr/bin/env python3
"""Stage approved artwork, build the appended catalog, and record public asset keys."""
import hashlib
import json
import shutil
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROSTER = ROOT / 'Design Assets/Expanded Roster'
DELIVERY = ROSTER / 'R2 Delivery'
PACKAGE = DELIVERY / 'expanded-roster-v1'
PREFIX = 'images/expanded-roster-v1/'
TYPES = {
    1: ['Psychic'], 2: ['Grass'], 3: ['Ground'], 4: ['Rock', 'Psychic'],
    5: ['Steel'], 6: ['Steel'], 7: ['Poison'], 8: ['Psychic', 'Fairy'],
    9: ['Grass'], 10: ['Bug', 'Dark'], 11: ['Dragon', 'Psychic'], 12: ['Dark', 'Ghost'],
}

def main():
    PACKAGE.mkdir(parents=True, exist_ok=True)
    lore = json.loads((ROSTER / 'names-and-lore.json').read_text())
    catalog_path = ROOT / 'Nanobeasts/Resources/creatures-by-family.json'
    catalog = json.loads(catalog_path.read_text())
    reports = json.loads((ROSTER / 'Animation Review/asset-verification.json').read_text())
    assets, image_keys, transitions = [], [], {}

    def stage(source, filename):
        target = PACKAGE / filename
        shutil.copy2(source, target)
        assets.append({'source': str(source.relative_to(ROOT)), 'file': filename,
                       'key': PREFIX + filename, 'bytes': target.stat().st_size,
                       'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})

    additions = []
    for family in lore['families']:
        number = family['number']
        first = family['stages'][0]['name']
        folder = ROSTER / f'Unnamed Nanobeast {number:02}'
        egg_key = f'{first.lower()}-egg-stage-0-modern'
        image_keys.append(egg_key)
        stage(next(folder.glob('*egg*modern.png')), f'{first}-egg-stage-0-modern.png')
        stages = [{'name': first + ' Egg', 'stage': 0, 'image_key': egg_key,
                   'types': TYPES[number], 'description': f'A sealed {first} waits within. Its markings hint at the creature growing inside.'}]
        for form in family['stages']:
            name, level = form['name'], form['stage']
            image_key = f'{name.lower()}-stage-{level}-modern'
            image_keys.append(image_key)
            stage(ROSTER / form['source_asset'], f'{name}-stage-{level}-modern.png')
            types = ['Poison', 'Steel'] if name == 'Miasmorg' else TYPES[number]
            stages.append({'name': name, 'stage': level, 'image_key': image_key,
                           'types': types, 'description': form['description']})
            form['types'] = types
        additions.append({'evolution_family_id': str(uuid.uuid5(uuid.NAMESPACE_URL, f'https://nanobeasts.app/families/{first.lower()}')),
                          'family_name': first + ' Line', 'stages': stages})
    for report in reports:
        stage(ROSTER / report['output'], report['key'] + '.webp')
        if report['kind'] in ('hatch', 'evolution'):
            transitions[report['key']] = report['duration_ms']
    assert len(assets) == 105
    existing_ids = {f['evolution_family_id'] for f in catalog['evolution_families']}
    catalog['evolution_families'].extend(f for f in additions if f['evolution_family_id'] not in existing_ids)
    assert len(catalog['evolution_families']) == 43
    assert sum(s['stage'] > 0 for f in catalog['evolution_families'] for s in f['stages']) == 100
    catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')
    lore['status'] = 'Names, types, and concise lore selected for the 100-creature roster; R2 delivery in progress.'
    (ROSTER / 'names-and-lore.json').write_text(json.dumps(lore, indent=2) + '\n')
    (DELIVERY / 'upload-manifest.json').write_text(json.dumps(assets, indent=2) + '\n')
    (DELIVERY / 'catalog-additions.json').write_text(json.dumps(additions, indent=2) + '\n')
    # This block is appended to the existing Swift manifest source, avoiding project-file churn.
    swift = '\n// Approved expanded roster. Original family IDs and ordering remain unchanged.\n'
    swift += 'enum ExpandedRosterAssets {\n    static let prefix = "images/expanded-roster-v1/"\n'
    swift += '    static let imageKeys: Set<String> = [\n'
    swift += ''.join(f'        "{key}",\n' for key in image_keys)
    swift += '    ]\n\n    static let transitionMilliseconds: [String: Int64] = [\n'
    swift += ''.join(f'        "{key}": {value},\n' for key, value in transitions.items())
    swift += '''    ]

    static func transition(named key: String) -> (url: URL, duration: Duration)? {
        guard let milliseconds = transitionMilliseconds[key] else { return nil }
        return (R2AssetManifest.baseURL.appending(path: prefix + key + ".webp"),
                .milliseconds(milliseconds))
    }
}
'''
    (DELIVERY / 'expanded-manifest.swift.txt').write_text(swift)
    print(f'Staged {len(assets)} files; 43 families, 100 creatures, 27 timed transitions.')

if __name__ == '__main__':
    main()
