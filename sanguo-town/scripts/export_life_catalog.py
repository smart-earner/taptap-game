#!/usr/bin/env python3
"""Rebuild the bundled runtime catalog from the checked 0.7.2 specifications."""
from pathlib import Path
import json, subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable,str(root/'scripts/build_slim_v072.py'),'--output',tmp],check=True)
    load=lambda name: json.loads((Path(tmp)/'resolved'/name).read_text())
    cfg,c,h,b=load('life.json'),load('content.json'),load('hero-system.json'),load('bootstrap.json')
    d={'version':'0.7.2','resources':cfg['resources'],'crops':cfg['crops'],'recipes':cfg['recipes'],'sources':cfg['sources'],'buildings':cfg['buildings'],'heroes':c['heroes'],'recruitment':c['recruitment'],'skills':h['skills'],'weights':h['job_weights_bp'],'roles':h['appointment_weights_bp'],'rates':h['rates'],'metrics':h['metrics'],'initial':cfg['initial'],'bootstrap':b}
    text=json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n'
    target=root/'Sources/SanguoLife/Resources/catalog.json'
    if '--check' in sys.argv:
        assert target.read_text()==text,'Bundled runtime catalog drifted from approved design'
    else:
        target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text)
    print('Runtime catalog: 8 resources, 4 recipes, 30 heroes, 22 skills; exact resolved data.')

# The new optional chain has one frozen, versioned configuration.
husbandry=json.loads((root/'spec/husbandry-v2.json').read_text())
pig=cfg['pig']
assert husbandry['purchasePrice']==pig['price_including_delivery']
assert husbandry['deliverySeconds']==pig['delivery_s']
assert husbandry['growthSegments']==pig['segments']
assert husbandry['segmentSeconds']==pig['segment_growth_s']
assert husbandry['feedPerSegment']==pig['feed_mU']['grain']
assert husbandry['careWorkSeconds']==pig['care_work_s']
assert husbandry['butcherWorkSeconds']==pig['butcher_s']
assert husbandry['meatPerAnimal']==pig['meat_mU']
htext=json.dumps(husbandry,ensure_ascii=False,indent=2)+'\n'
hpath=root/'Sources/SanguoLife/Resources/husbandry.json'
if '--check' in sys.argv:
    assert hpath.read_text()==htext,'Bundled husbandry rules differ from source'
else:
    hpath.write_text(htext)
print('Husbandry rules: 6 segments, exact feed and paid animal provenance; 8 resource IDs unchanged.')
