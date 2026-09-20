#!/usr/bin/env python3
"""Validate v0.4 design contracts only, not runtime, balance, UI or M4 behavior."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main() -> None:
    config = json.loads((ROOT / 'spec/city-growth-v0.4.json').read_text(encoding='utf-8'))
    cases = json.loads((ROOT / 'spec/acceptance-v0.4.json').read_text(encoding='utf-8'))
    prd = (ROOT / 'docs/PRD.md').read_text(encoding='utf-8')
    acceptance = (ROOT / 'docs/ACCEPTANCE.md').read_text(encoding='utf-8')
    checks: list[str] = []
    def check(name: str, condition: bool) -> None:
        if not condition:
            raise ValueError('Static specification check failed: ' + name)
        checks.append(name)
    a, p, c, l = (config[k] for k in ('attention', 'pacing', 'capacity', 'legion'))
    check('document_version', config['document_version'] == '0.4' and 'PRD v0.4' in prd)
    check('not_runtime_config', config['status'] == 'design_target_not_runtime_configuration')
    check('city_first', config['priority'][0] == 'visible_city_growth')
    check('zero_daily_jobs', a['post_onboarding_mandatory_daily_actions'] == 0)
    check('two_onboarding_confirmations', a['onboarding_required_confirmations_max'] == 2)
    check('whole_faction_quota', a['quota_scope'] == 'whole_faction')
    check('proposal_interval', a['proposal_min_interval_hours'] == 72 and '72模拟小时' in prd)
    check('proposal_window', a['proposal_rolling_window_hours'] == 168 and a['proposal_max_per_window'] == 2)
    check('no_forced_reply', a['no_reply'] == 'continue_current_policy')
    check('persistent_offices', not a['appointments_expire'] and not a['policy_expires'])
    check('no_calendar_gate_or_reset', not p['calendar_unlocks'] and not p['forced_reset'])
    check('observation_windows', p['observation_days'] == [30, 60, 90])
    check('no_login_day_clock', p['normal_real_to_sim_ratio'] == 1 and '不是登录天数' in prd)
    check('phase_endpoints', config['construction_phase_boundaries'][0] == 0 and config['construction_phase_boundaries'][-1] == 1)
    check('phase_order', all(x < y for x,y in zip(config['construction_phase_boundaries'], config['construction_phase_boundaries'][1:])))
    check('five_phase_boundaries', len(config['construction_phase_boundaries']) == 5)
    check('shared_labor', c['shared_labor'] is True and c['ordinary_construction_slots'] == 2 and c['landmark_slots'] == 1)
    check('city_scope', c['cities'] == 3 and c['districts'] == 1 and c['plots_per_city'] == 16)
    check('collectibles_scope', c['heroes'] + c['weapons'] + c['mounts'] == 16)
    check('transport_capacity', c['foreign_trade_teams'] <= c['transport_teams'] <= c['active_contracts'])
    check('legion_steps', l['authorized_capacity_steps'] == [0,30,60,90])
    check('no_auto_second_legion', c['field_legions'] == 1 and l['new_legion_requires_approval'])
    check('military_offline_opt_in', l['military_expedition_offline_default'] is False)
    check('bounded_war', l['max_campaign_actions'] == 4 and l['changed_retry_after_failure'] == 1)
    check('offline_target_not_current', config['offline']['target_normal_cap_days'] == 30 and config['runtime_unchanged']['current_offline_days'] == 7)
    check('game_memory_only', config['city_memory']['capture_scope'] == 'game_state_render_only')
    check('historical_memory_no_rewards', config['city_memory']['uses_historical_state'] and not config['city_memory']['capture_awards_resources'])
    check('bounded_memory', config['city_memory']['automatic_limit'] == 60 and config['city_memory']['pinned_limit'] == 20)
    check('five_attributes_four_professions', len(set(config['characters']['base_attributes'])) == 5 and len(set(config['characters']['professions'])) == 4)
    check('no_daily_training', not config['characters']['daily_manual_training_required'])
    check('cash_not_duplicated', config['finance']['single_treasury'] and not config['finance']['internal_transfer_is_income'])
    check('reinvestment_bounds', all(0 <= n <= 1 for n in config['finance']['reinvestment_presets'].values()))
    check('45_longitudinal_scenarios', len(config['test_plan']['policy_profiles']) * len(config['test_plan']['view_interval_days']) * len(config['test_plan']['observation_days']) == 45)
    check('application_and_balance_not_run', all(config['test_plan'][k] == 'not_run' for k in ('application_status','m4_status','economy_simulation_status')))
    check('40_unique_cases', len(cases) == len({x['id'] for x in cases}) == 40)
    check('cases_not_run', all(x['status'] == 'not_run' for x in cases))
    check('case_chapters_exist', all(f"# {x['chapter']} " in prd for x in cases))
    check('case_table_same_ids', all(acceptance.count('| '+x['id']+' |') == 1 for x in cases))
    check('22_chapters', len(re.findall(r'^# \d{2} ',prd,re.M)) == 22)
    check('three_appendices', all('# 附录'+x+' ' in prd for x in 'ABC'))
    check('8_decision_examples', all('CD%02d' % n in prd for n in range(1,9)))
    check('no_raw_tool_markers', '' not in prd)
    for key, pair in p['duration_ranges_minutes'].items():
        check('duration_range_'+key, len(pair) == 2 and 0 < pair[0] <= pair[1])
    report = {
        'document_version':'0.4', 'scope':'static_document_and_configuration_only',
        'checks_passed':len(checks), 'checks':checks,
        'runtime_source_modified':False, 'economy_simulation_run':False,
        'm4_tested_in_this_change':False, 'application_cases_executed':0,
        'application_cases_planned':len(cases),
        'sha256': {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in ('docs/PRD.md','spec/city-growth-v0.4.json','spec/acceptance-v0.4.json')}
    }
    (ROOT/'docs/spec-validation-v0.4.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f"PASS: {len(checks)} static specification checks. 40 application cases / economy simulation / M4: NOT RUN.")

if __name__ == '__main__':
    main()
