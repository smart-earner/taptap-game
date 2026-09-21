import base64, hashlib, subprocess, zlib
from pathlib import Path
hashes=['e2d4f58a143e2092e8c2064f953f1289d3efb8409c78f37eeea633b20da2f5d5','202270333e66c4d41003589012e992b717a27fb75138cb1425e41711850d4e4b','8d1329476468e15df004ec598e660c573982c9d9ec159f605ba29d688ead0434','119a5f0e9d9151ae0324bd3f01c33a50d51cd9d8e51367b6f61ed98af6d07f46','49b63546445d240cce7963787dad323e83f6301fbf640dec3a576822bec30110','d431eb36a9c24d48737c82d499660a4f5c2a76eca6014eaa7dad61b877ead0eb','2bbf6e443f07704dade9e5b95e31947c55dd52b66e255e935942ed031e1f55a6','1fed69dfb7c84e0967337cc13c8aa08178ee0c8f8a30e751bd48c658e8237869']
parts=[]
for i,h in enumerate(hashes):
    p=Path(f'sanguo-town/checkpoints/life072/ui02.{i}').read_text().strip().encode()
    if i==4 and len(p)==4001 and p.startswith(b'wOkY'):
        p=p[1:]
    assert hashlib.sha256(p).hexdigest()==h,f'part {i} mismatch'
    parts.append(p)
data=b''.join(parts)
assert hashlib.sha256(data).hexdigest()=='b6e9e5c954527863cc5c6e51e98a70bc282f6eac0d9ecad2b36686d26a1d6535'
patch=zlib.decompress(base64.b64decode(data));path=Path('/tmp/life-ui.patch');path.write_bytes(patch)
for line in patch.decode().splitlines():
    if not line.startswith('+++ b/'):continue
    p=line[6:]
    assert '..' not in Path(p).parts and (p.startswith(('sanguo-town/Sources/SanguoLife/','sanguo-town/Sources/SanguoLifeVisual/','sanguo-town/Sources/SanguoLifeCLI/','sanguo-town/Tests/SanguoLifeTests/')) or p in ('sanguo-town/Sources/SanguoMac/LifeScene.swift','sanguo-town/Sources/SanguoMac/LifeViews.swift','sanguo-town/Sources/SanguoMac/SanguoMacApp.swift','sanguo-town/Package.swift','sanguo-town/scripts/build-macos.sh')),p
subprocess.run(['git','apply','--check',str(path)],check=True)
subprocess.run(['git','apply',str(path)],check=True)
# Swift 6: avoid the mutable C stderr global in the bundle self-check error path.
p=Path('sanguo-town/Sources/SanguoMac/SanguoMacApp.swift')
s=p.read_text().replace('fputs("Life catalog failed: \\(error.localizedDescription)\\n",stderr)','FileHandle.standardError.write(Data("Life catalog failed: \\(error.localizedDescription)\\n".utf8))')
p.write_text(s)
print('Exact source patch applied and catalog self-check made concurrency safe.')
