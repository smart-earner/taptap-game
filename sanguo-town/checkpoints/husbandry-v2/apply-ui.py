#!/usr/bin/env python3
"""Transport helper for one reviewed source patch; does not touch game saves."""
from pathlib import Path
import base64
import hashlib
import json
import zlib

here = Path(__file__).resolve().parent
root = here.parents[2]
def sha(data):
    return hashlib.sha256(data).hexdigest()
encoded = (here / 'ui.patch.b64').read_text().strip()
expected = '2a38676e401081c7362919a6c75fa33a45e7de6b056eb117296ee4bc434429e1'
if sha(encoded.encode()) != expected:
    # Known literal transcription differences. Original whole-payload and every file
    # hash must still match; this is not a permissive patch or a runtime fallback.
    for wrong, right in [('NHMi5LRrJrJ/GD', 'NHMi5LRrJ/GD'),
                         ('TVKoYGgJk1H8', 'TVKoYGjJk1H8'),
                         ('QBBmuIQWVE1sm', 'QBBmuIQWWE1sm')]:
        assert encoded.count(wrong) == 1, wrong
        encoded = encoded.replace(wrong, right)
assert sha(encoded.encode()) == expected, 'Transport differs from locally verified patch'
raw = zlib.decompress(base64.b64decode(encoded, validate=True))
assert sha(raw) == 'e140b7d1b484bd0cf6011b5528cc7164eeb9279c53d9052962404d11f1e34a86'
data = json.loads(raw)

def target(name):
    assert '..' not in Path(name).parts
    assert name.startswith(('sanguo-town/Sources/', 'sanguo-town/Tests/')) or name == 'sanguo-town/Package.swift'
    return root / name

pending = {}
for change in data['changes']:
    path = target(change['path'])
    before = path.read_bytes()
    assert sha(before) == change['before'], str(path) + ': base changed'
    lines = before.decode().splitlines(keepends=True)
    for edit in reversed(change['edits']):
        assert 0 <= edit['from'] <= edit['to'] <= len(lines)
        lines[edit['from']:edit['to']] = base64.b64decode(edit['text_b64'], validate=True).decode().splitlines(keepends=True)
    after = ''.join(lines).encode()
    assert sha(after) == change['after'], str(path) + ': differs from tested result'
    pending[path] = after
for item in data['copies']:
    assert Path(item['source']).name == item['source']
    path = target(item['target'])
    assert not path.exists() and path not in pending
    after = (here / item['source']).read_bytes()
    assert sha(after) == item['sha256'], item['source'] + ': upload mismatch'
    pending[path] = after
for path, content in pending.items():
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
print('Integrated', len(pending), 'source/test files, byte-for-byte identical to local release-tested source.')
