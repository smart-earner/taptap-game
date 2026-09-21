#!/usr/bin/env python3
"""Black-box checks: only newly-created fixture saves, never a player's town."""
import base64
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / '.build/release/SanguoLifeCLI'
checks = 0

def check(condition, name):
    global checks
    assert condition, name
    checks += 1
    print('PASS', name)

with tempfile.TemporaryDirectory(prefix='godot-fixture-') as directory:
    save = pathlib.Path(directory) / 'world.json'
    def call(operation='snapshot', **kw):
        payload = dict(operation=operation, seconds=0, **kw)
        return json.loads(subprocess.check_output(
            [str(BIN), '--godot-bridge', json.dumps(payload), '--godot-save', directory], text=True))
    first = call()
    check(first['ok'] and first['coins'] == 200, 'initial 200 coins')
    check(sum(h['star'] > 0 for h in first['heroes']) == 5, 'five starting heroes')
    check(first['savePath'] == str(save), 'fixture save isolation')
    encoded = base64.b64encode(b'{"operation":"snapshot","seconds":0}').decode()
    transported = json.loads(subprocess.check_output([str(BIN), '--godot-request-b64', encoded, '--godot-save', directory], text=True))
    check(transported == first, 'Godot base64 transport preserves request and response')
    check(first['goldChain']['deliveredIngots'] * 10 == first['minted'] * 1000, 'gold-chain display matches actual consumed ingots')
    check(all(len(h['skills']) == 3 for h in first['heroes']), 'all heroes expose three authoritative star skills')
    original = save.read_bytes()
    check(call()['coins'] == 200 and save.read_bytes() == original, 'read does not rewrite save')
    draw = call('draw', commandID='test-draw-1', count=1)
    check(draw['ok'] and draw['coins'] == 100 and len(draw['receipt']['draws']) == 1, 'draw costs 100 and yields one result')
    saved = save.read_bytes()
    retry = call('draw', commandID='test-draw-1', count=1)
    check(retry['receipt'] == draw['receipt'] and retry['coins'] == 100, 'draw retry is idempotent')
    check(save.read_bytes() == saved, 'retry does not mutate save')
    check(not call('draw', commandID='too-expensive', count=10)['ok'], 'cannot buy ten draws without 1000 coins')
    check(save.read_bytes() == saved, 'failed purchase leaves save unchanged')
    check(not call('star', commandID='bad-star', hero='xunyu', target=5)['ok'], 'cannot skip stars')
    check(save.read_bytes() == saved, 'failed star-up leaves save unchanged')
    check(not call('draw', count=1)['ok'], 'player commands require identity')
    advanced = json.loads(subprocess.check_output([str(BIN), '--godot-bridge', json.dumps({'operation':'advance','seconds':2880}), '--godot-save', directory], text=True))
    check(advanced['ok'] and advanced['time'] == first['time'] + 2880, 'full engine day advances')
    check(advanced['coins'] == 100 + advanced['minted'], 'coins follow minted ledger, not a UI timer')
    check(advanced['minted'] > 0, 'real production completes gold delivery')
    check(advanced['goldChain']['deliveredIngots'] * 10 == advanced['minted'] * 1000, 'production presentation preserves ledger after a full day')
    check(call()['coins'] == advanced['coins'], 'reload preserves production and draws')
    blocked = json.loads(subprocess.check_output([str(BIN), '--godot-bridge', '{"operation":"snapshot","seconds":0}', '--godot-save', directory + '/native-save'], text=True))
    check(not blocked['ok'], 'rejects unapproved save directories')
print(f'{checks} checks passed')
