#!/usr/bin/env python3
"""One-shot development checkout integration; never reads or writes player saves."""
from pathlib import Path
import argparse
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
p = argparse.ArgumentParser()
p.add_argument('--manifest', default='integration.json')
args = p.parse_args()
assert Path(args.manifest).name == args.manifest
manifest = HERE / args.manifest
raw = manifest.read_text()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    # Exactly identified transport escape omission in the CLI's Swift interpolation.
    # Target hashes below still have to equal the locally compiled source byte for byte.
    assert args.manifest == 'integration.json'
    broken = re.compile(r'(?<!\\)\\\(')
    assert len(broken.findall(raw)) == 5
    raw = broken.sub(lambda _: chr(92) * 2 + '(', raw)
    data = json.loads(raw)

def digest(b):
    return hashlib.sha256(b).hexdigest()

def target(name):
    assert '..' not in Path(name).parts
    assert name.startswith(('sanguo-town/Sources/', 'sanguo-town/Tests/')) or name == 'sanguo-town/Package.swift'
    return ROOT / name

pending = {}
for change in data['changes']:
    out = target(change['path'])
    assert out not in pending
    old = out.read_bytes()
    assert digest(old) == change['before'], str(out) + ': unexpected base, refusing overwrite'
    lines = old.decode().splitlines(keepends=True)
    for edit in reversed(change['edits']):
        assert 0 <= edit['from'] <= edit['to'] <= len(lines)
        lines[edit['from']:edit['to']] = edit['text'].splitlines(keepends=True)
    result = ''.join(lines).encode()
    assert digest(result) == change['after'], str(out) + ': patch differs from tested source'
    pending[out] = result
for item in data['copies']:
    assert Path(item['source']).name == item['source']
    out = target(item['target'])
    assert not out.exists() and out not in pending
    result = (HERE / item['source']).read_bytes()
    assert digest(result) == item['sha256'], item['source'] + ': upload differs from tested source'
    pending[out] = result
for out, result in pending.items():
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(result)
manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print('Integrated', len(pending), 'exact source/test files; player data untouched.')
