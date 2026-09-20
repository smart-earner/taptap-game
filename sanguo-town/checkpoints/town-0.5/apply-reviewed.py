"""Apply this fixed reviewed batch only after checking every original and resulting blob hash."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path('sanguo-town')
STAGE = ROOT / 'checkpoints/town-0.5'
ALLOWED = {
    'Sources/SanguoCore/GrowthValidation.swift', 'Sources/SanguoGrowth/GrowthCLI.swift',
    'Sources/SanguoMac/CityGrowthViews.swift', 'Sources/SanguoMac/RealmViews.swift',
    'Sources/SanguoMac/SanguoMacApp.swift', 'Sources/SanguoMac/TownScene.swift',
    'Sources/SanguoPresentation/GrowthTownArt.swift', 'Sources/SanguoPresentation/TownPresentation.swift',
    'scripts/build-macos.sh', 'docs/PRD.md', 'docs/ARCHITECTURE.md', 'docs/IMPLEMENTATION_PLAN.md',
    'docs/CITY_IDENTITY.md', 'spec/city-identity-v0.5.json', 'scripts/validate_identity_spec.py'
}
COPIES = {
    'TownLayout.swift': ('Sources/SanguoPresentation/TownLayout.swift', '8070ee6b605973f114fbe03eb32ea6683af2fc2b'),
    'CityIdentityView.swift': ('Sources/SanguoMac/CityIdentityView.swift', '845d89043485aa5e23584985fcc619ca097ab3d6'),
    'TownLayoutTests.swift': ('Tests/SanguoPresentationTests/TownLayoutTests.swift', '132fa62e864f443302fac1045aed84ca8ef90425')
}
def blob(text):
    data = text.encode('utf-8')
    return hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()

entries = json.loads((STAGE/'runtime-edits.json').read_text()) + json.loads((STAGE/'docs-edits.json').read_text())
assert len(entries) == len(ALLOWED) and {e['path'] for e in entries} == ALLOWED
prepared = {}
for entry in entries:
    path = ROOT / entry['path']
    if 'content' in entry:
        assert not path.exists(), f'Unexpected pre-existing file: {path}'
        result = entry['content']
    else:
        original = path.read_text()
        assert blob(original) == entry['before'], f'Changed source: {path}'
        cursor = 0
        pieces = []
        for offset, length, replacement in entry['edits']:
            assert isinstance(offset,int) and isinstance(length,int)
            assert cursor <= offset <= offset + length <= len(original), f'Invalid span: {path}'
            pieces.extend([original[cursor:offset], replacement])
            cursor = offset + length
        pieces.append(original[cursor:])
        result = ''.join(pieces)
        assert blob(result) == entry['after'], f'Unexpected output: {path}'
    prepared[path] = result
for name, (target, sha) in COPIES.items():
    text = (STAGE/name).read_text()
    assert blob(text) == sha, f'Changed reviewed addition: {name}'
    assert not (ROOT/target).exists()
    prepared[ROOT/target] = text
for path,text in prepared.items():
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,encoding='utf-8')
Path('/tmp/identity-commit-paths.txt').write_text('\n'.join(str(p) for p in sorted(prepared))+'\n')
print(f'Applied {len(prepared)} whitelisted source/test/document files; original and output hashes verified.')
