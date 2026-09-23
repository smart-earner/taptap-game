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
        # Freeze the authoritative war wall clock while testing byte-for-byte
        # gacha retries. A real desktop retry may legitimately settle a due raid.
        payload = dict(operation=operation, seconds=0, realUTC=0)
        payload.update(kw)
        return json.loads(subprocess.check_output(
            [str(BIN), '--godot-bridge', json.dumps(payload), '--godot-save', directory], text=True))
    first = call()
    check(first['ok'] and first['coins'] == 200, 'initial 200 coins')
    check(first['happiness'] == 70 and first['civicDuty'] ==
          {'clean': 0, 'watch': 0, 'drill': 0, 'capitalDefense': 0},
          'desktop snapshot exposes only completed, current civic effects')
    check(sum(h['star'] > 0 for h in first['heroes']) == 5, 'five starting heroes')
    check(first['idlePersonnel'] == sum(
        h.get('taskKind', '') == '' and not h.get('sleeping', False)
        and h.get('job') not in ('prefect', 'guard_day', 'guard_night')
        and h['id'] not in set(first['campaign']['reservedHeroIDs'])
        and h['id'] not in set(first['campaign'].get('awayHeroIDs', []))
        and not h.get('healthCondition')
        for h in first['heroes'] if 'x' in h
    ), 'idle personnel excludes active, sleeping, and reserved duty heroes')
    check(all(h.get('idleReason') for h in first['heroes'] if h.get('taskKind') == '' and 'x' in h),
          'every visible untasked resident explains why no real task is active')
    check(first['savePath'] == str(save), 'fixture save isolation')
    encoded = base64.b64encode(b'{"operation":"snapshot","seconds":0,"realUTC":0}').decode()
    transported = json.loads(subprocess.check_output([str(BIN), '--godot-request-b64', encoded, '--godot-save', directory], text=True))
    check(transported == first, 'Godot base64 transport preserves request and response')
    encoded_response = subprocess.check_output(
        [str(BIN), '--godot-request-b64', encoded, '--godot-response-b64', '--godot-save', directory], text=True).strip()
    check(encoded_response.isascii() and json.loads(base64.b64decode(encoded_response).decode('utf-8')) == first,
          'ASCII response transport round-trips the complete CJK snapshot without altering the save')
    invalid_response = subprocess.check_output(
        [str(BIN), '--godot-request-b64', 'invalid!', '--godot-response-b64', '--godot-save', directory], text=True).strip()
    check(not json.loads(base64.b64decode(invalid_response).decode('utf-8'))['ok'],
          'ASCII response transport also encodes protocol errors consistently')
    check(first['goldChain']['deliveredIngots'] * first['goldChain']['coinsPerIngot'] == first['minted'] * 1000, 'gold-chain display matches actual consumed ingots')
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
    advanced = json.loads(subprocess.check_output([str(BIN), '--godot-bridge', json.dumps({'operation':'advance','seconds':2880,'realUTC':0}), '--godot-save', directory], text=True))
    check(advanced['ok'] and advanced['time'] == first['time'] + 2880, 'full engine day advances')
    check(advanced['coins'] == 100 + advanced['minted'], 'coins follow minted ledger, not a UI timer')
    check(advanced['minted'] > 0, 'real production completes gold delivery')
    check(advanced['goldChain']['deliveredIngots'] * advanced['goldChain']['coinsPerIngot'] == advanced['minted'] * 1000, 'production presentation preserves ledger after a full day')
    check(call()['coins'] == advanced['coins'], 'reload preserves production and draws')
    night = call('advance', seconds=1860)
    check(night['ok'] and night['idlePersonnel'] == 0, 'off-shift heroes are not shown as idle workers')
    blocked = json.loads(subprocess.check_output([str(BIN), '--godot-bridge', '{"operation":"snapshot","seconds":0}', '--godot-save', directory + '/native-save'], text=True))
    check(not blocked['ok'], 'rejects unapproved save directories')
print(f'{checks} checks passed')
