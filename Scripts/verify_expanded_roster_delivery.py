#!/usr/bin/env python3
"""Exercise production Swift catalog decoding and all expanded-roster asset routes."""
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DELIVERY = ROOT / 'Design Assets/Expanded Roster/R2 Delivery'
before = json.loads((DELIVERY / 'catalog-before-import.json').read_text())
after = json.loads((ROOT / 'Nanobeasts/Resources/creatures-by-family.json').read_text())
assert after['evolution_families'][:31] == before['evolution_families'], 'Existing progression IDs/order/data changed'
assets = json.loads((DELIVERY / 'upload-manifest.json').read_text())
assert len({a['key'] for a in assets}) == 105
model = (ROOT / 'Nanobeasts/Models/CreatureModels.swift').read_text()
art = (ROOT / 'Nanobeasts/Services/RemoteArtwork.swift').read_text()
manifest = art[art.index('enum R2AssetManifest {'):art.index('actor R2ArtworkCache {')]
expanded = art[art.index('enum ExpandedRosterAssets {'):]
harness = r'''
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let catalog = try JSONDecoder().decode(CreatureCatalog.self, from: Data(contentsOf: root.appending(path: "Nanobeasts/Resources/creatures-by-family.json")))
precondition(catalog.families.count == 43 && catalog.creatureStages.count == 100)
precondition(Set(catalog.families.map(\.id)).count == 43)
precondition(Set(catalog.families.flatMap(\.stages).map(\.id)).count == 143)
var checked = Set<String>()
func check(_ url: URL) {
    precondition(url.host == "assets.nanobeasts.app")
    let prefix = "/images/expanded-roster-v1/"
    precondition(url.path.hasPrefix(prefix))
    let file = String(url.path.dropFirst(prefix.count))
    let path = root.appending(path: "Design Assets/Expanded Roster/R2 Delivery/expanded-roster-v1/" + file)
    precondition(FileManager.default.fileExists(atPath: path.path), "Missing file: \(file)")
    checked.insert(file)
}
for family in catalog.families.suffix(12) {
    precondition(family.stages.map(\.stage) == Array(0..<family.stages.count))
    for stage in family.stages {
        check(R2AssetManifest.url(for: stage.imageKey))
        check(R2AnimationManifest.url(for: stage))
    }
    let forms = family.stages.filter { !$0.isEgg }
    let hatch = ExpandedRosterAssets.transition(named: forms[0].name.lowercased() + "-hatch")!
    check(hatch.url)
    precondition(hatch.duration >= .seconds(5))
    for (from, to) in zip(forms, forms.dropFirst()) {
        let clip = ExpandedRosterAssets.transition(named: from.name.lowercased() + "-" + to.name.lowercased() + "-evolution")!
        check(clip.url)
        precondition(clip.duration >= .seconds(5))
    }
}
precondition(checked.count == 105)
precondition(ExpandedRosterAssets.transition(named: "glitchlet-devicore-evolution") == nil)
precondition(R2AssetManifest.url(for: "ampaw-egg-stage-0-modern").path == "/images/hatchstep-eggs/Ampaw-egg-nobg.png")
print("PASS: 100 creatures, 43 families, 143 stable stage IDs, all 105 asset routes, and full transition durations.")
'''
with tempfile.TemporaryDirectory(prefix='roster-delivery-check-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(model + '\n' + manifest + '\n' + expanded + '\n' + harness)
    subprocess.run(['swift', '-module-cache-path', temp + '/ModuleCache', str(path), str(ROOT)], check=True)
