#!/usr/bin/env python3
"""Cross-check the versioned PRD/spec and Swift implementation; not gameplay acceptance."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]

def validate() -> dict:
    spec = json.loads((ROOT / 'spec/city-identity-v0.5.json').read_text())
    code = (ROOT / 'Sources/SanguoCore/CityIdentity.swift').read_text()
    prd = (ROOT / 'docs/PRD.md').read_text()
    tests = (ROOT / 'Tests/SanguoCoreTests/CityIdentityTests.swift').read_text()
    art_tests = (ROOT / 'Tests/SanguoPresentationTests/TownLayoutTests.swift').read_text()
    checks: list[str] = []
    def check(condition: bool, name: str) -> None:
        if not condition:
            raise ValueError(name)
        checks.append(name)
    check('PRD v0.5' in prd and spec['version'] == '0.5', 'PRD/spec versions')
    check(f'let version = "{spec["runtime_version"]}"' in code, 'runtime rule version')
    check(spec['schema'] == 4 and 'schemaVersion = 4' in code, 'schema migration')
    check(spec['explicit_migration'] is True, 'explicit migration flag')
    check(spec['trace_limit_per_city'] == 12 and 'historyLimit = 12' in code, 'bounded trace history')
    tracks = {'streets','water','homes','commerce','industry','academy','gardens','ramparts'}
    for policy, focused in spec['targets'].items():
        check(set(focused).issubset(tracks), f'{policy}: known tracks')
        pattern = rf'case \.{policy}: focus = \[([^\]]+)\]'
        match = re.search(pattern, code)
        actual = set(re.findall(r'\.([a-z]+)', match.group(1))) if match else set()
        check(actual == set(focused), f'{policy}: matching target tracks')
        check(set(focused.values()) == {2 if policy == 'balanced' else 3}, f'{policy}: matching depth')
    check('policy == .balanced ? 2 : 3' in code, 'Swift depth rule')
    check(spec['default_services'] == 1 and '($0, 1)' in code, 'basic service for every track')
    check(set(spec['prerequisites']) == tracks, 'prerequisite coverage')
    for track, building in spec['prerequisites'].items():
        line = next((ln for ln in code.splitlines() if re.match(r'\s*case .*\.'+track+r'\b', ln) and ': .' in ln), '')
        # Only the requirement switch has this simple return expression.
        lines = [ln for ln in code.splitlines() if re.match(r'\s*case .*\.'+track+r'\b', ln) and ': .' in ln]
        check(any(ln.rstrip().endswith(': .'+building) for ln in lines), f'{track}: prerequisite')
    check(spec['nominal_days_two_workers'] == [2,6,12] and 'tier == 1 ? 2 : tier == 2 ? 6 : 12' in code, 'nominal work durations')
    check(spec['income_channel'] == 'market' and 'plan.level(.market) == 0' in code, 'bootstrap income channel')
    check(spec['layout']['current'] == 2 and spec['layout']['plot_count'] == 16, 'layout contract')
    check(tests.count('@Test ') == 14 and art_tests.count('@Test ') == 13, '27 new runtime cases')
    check(all(f'# {i:02d} ' in prd for i in range(1,23)), '22 PRD chapters preserved')
    check(all(f'# 附录{x}' in prd for x in 'ABC'), 'all original appendices retained')
    check((ROOT/'docs/reference/PRD-v0.4.md').exists(), 'prior product baseline archived')
    return {'scope':'static version/spec checks only','checks_passed':len(checks),'checks':checks,
            'full_prd_accepted':False,'m4_gui_tested':False}

if __name__ == '__main__':
    print(json.dumps(validate(), ensure_ascii=False, indent=2))
