#!/usr/bin/env python3
"""Pure data-driven PRD reference arithmetic. Not wired to the Swift game engine."""
from __future__ import annotations
from dataclasses import dataclass
from typing import Any, Iterable

ATTRS = {'administration', 'strategy', 'valor', 'command'}
ROLES = {'worker', 'prefect', 'governor', 'commander'}

def ceildiv(a: int, b: int) -> int:
    if type(a) is not int or type(b) is not int or a < 0 or b <= 0:
        raise ValueError('invalid nonnegative integer division')
    return (a + b - 1) // b

def aptitude(attributes: dict[str, int], weights: dict[str, int]) -> int:
    if set(attributes) != ATTRS or any(type(v) is not int or not 0 <= v <= 100 for v in attributes.values()):
        raise ValueError('exactly four attributes in 0..100 required')
    if not set(weights) <= ATTRS or sum(weights.values()) != 10000 or any(type(v) is not int or v <= 0 for v in weights.values()):
        raise ValueError('invalid attribute weights')
    return sum(attributes[k] * v for k, v in weights.items()) // 10000

@dataclass(frozen=True)
class Source:
    # Derive eligibility from actual office, presence, task and authority. Default-deny.
    person: dict[str, Any]
    role: str
    eligible: bool = False

def checked_sources(sources: Iterable[Source]) -> list[Source]:
    values = list(sources)
    if any(s.role not in ROLES for s in values):
        raise ValueError('unknown role')
    if len({s.person['id'] for s in values}) != len(values):
        raise ValueError('same person supplied twice')
    if len({s.role for s in values}) != len(values):
        raise ValueError('multiple holders of one contextual role')
    return values

def resolve(lib: dict, sources: Iterable[Source], metric: str, *, job: str | None = None,
            event: str | None = None, coverage_bp: int = 0) -> int:
    meta = lib['metrics'][metric]
    event = event or meta['event']
    if job is not None and job not in lib['job_weights_bp']:
        raise ValueError('unknown job')
    families: dict[str, int] = {}
    catalog = {s['id']: s for s in lib['skills']}
    for source in checked_sources(sources):
        if not source.eligible:
            continue
        ids = source.person.get('skill_ids', [])
        if len(ids) != len(set(ids)):
            raise ValueError('duplicate skill')
        for skill_id in ids:
            skill = catalog[skill_id]
            for effect in skill['effects']:
                if effect['metric'] != metric or effect['event'] != event or source.role not in effect['roles']:
                    continue
                if 'jobs' in effect and job not in effect['jobs']:
                    continue
                if coverage_bp < effect.get('requires_coverage_bp', 0):
                    continue
                scale = lib['rates']['governor_scale_bp'] if source.role == 'governor' else 10000
                amount = effect['value'] * scale // 10000
                family = effect['family']
                families[family] = max(families.get(family, 0), amount)
    return min(meta['cap'], sum(families.values()))

def leader_bonus(lib: dict, sources: Iterable[Source], job: str) -> int:
    r = lib['rates']; values = []
    for s in checked_sources(sources):
        if not s.eligible or s.role not in {'prefect', 'governor'}:
            continue
        a = aptitude(s.person['attributes'], lib['job_weights_bp'][job])
        amount = min(r['leader_attribute_cap'], max(0, a - r['baseline']) * r['leader_bp_per_point'])
        if s.role == 'governor':
            amount = amount * r['governor_scale_bp'] // 10000
        values.append(amount)
    return max(values, default=0)

def work_rate(lib: dict, worker: dict, job: str, *, leaders: Iterable[Source] = (),
              level: int = 1, facility_bp: int = 0, penalty_bp: int = 0) -> int:
    r = lib['rates']; leaders = list(leaders)
    if not 1 <= level <= r['job_level_max'] or not 0 <= facility_bp <= 5000 or not 0 <= penalty_bp <= 5000:
        raise ValueError('rate bounds')
    if any(s.role not in {'prefect', 'governor'} for s in leaders):
        raise ValueError('not a city leader')
    sources = [Source(worker, 'worker', True)] + leaders
    checked_sources(sources)
    a = aptitude(worker['attributes'], lib['job_weights_bp'][job])
    personal = min(r['worker_attribute_cap'], max(0, a - r['baseline']) * r['worker_bp_per_point'])
    skills = resolve(lib, sources, 'work_rate_bp', job=job)
    result = 10000 + personal + (level - 1) * r['job_xp_bp_per_level'] + leader_bonus(lib, leaders, job) + skills + facility_bp - penalty_bp
    return max(r['work_total_min'], min(r['work_total_max'], result))

def purchase_discount(lib: dict, sources: Iterable[Source]) -> int:
    values = checked_sources(sources); r = lib['rates']; attrs = []
    for s in values:
        if not s.eligible or s.role == 'commander':
            continue
        a = aptitude(s.person['attributes'], lib['job_weights_bp']['merchant'])
        amount = min(r['leader_attribute_cap'], max(0, a - r['baseline']) * r['purchase_attribute_bp_per_point'])
        if s.role == 'governor': amount = amount * r['governor_scale_bp'] // 10000
        attrs.append(amount)
    return min(r['purchase_total_cap'], max(attrs, default=0) + resolve(lib, values, 'purchase_discount_bp'))

def purchase_price(lib: dict, listed_total: int, transport_fee: int, sources: Iterable[Source], regional_bp: int = 0) -> int:
    if listed_total < 0 or transport_fee < 0 or not 0 <= regional_bp <= 1000:
        raise ValueError('invalid price')
    discount = max(purchase_discount(lib, sources), regional_bp)
    return ceildiv(listed_total * (10000 - discount), 10000) + transport_fee

def escort_score(lib: dict, person: dict, active: int, training: int, ramparts: int) -> int:
    a = person['attributes']; aptitude(a, {'command': 10000})
    if active < 0 or not 0 <= training <= 5 or not 0 <= ramparts <= 3:
        raise ValueError('escort bounds')
    bonus = resolve(lib, [Source(person,'commander',True)], 'escort_score')
    return active + 10 * training + 5 * ramparts + max(0,a['command']-50)//5 + max(0,a['valor']-50)//10 + max(0,a['strategy']-50)//10 + bonus

def validate(lib: dict, content: dict, cfg: dict) -> None:
    if set(lib['attribute_labels']) != ATTRS:
        raise ValueError('attribute registry')
    if set(lib['job_weights_bp']) != {j['id'] for j in cfg['jobs']}:
        raise ValueError('job registry mismatch')
    for j in cfg['jobs']:
        if 'attribute' in j or j['attribute_weights_bp'] != lib['job_weights_bp'][j['id']]:
            raise ValueError('conflicting job mapping')
        aptitude(dict.fromkeys(ATTRS,50),j['attribute_weights_bp'])
    allowed_metrics = {'work_rate_bp','purchase_discount_bp','patrol_speed_bp','training_rate_bp','escort_score','wounded_reduction_bp','happiness_rise_extra'}
    if set(lib['metrics']) != allowed_metrics:
        raise ValueError('unsupported primitive')
    ids = [s['id'] for s in lib['skills']]
    if len(ids) != len(set(ids)): raise ValueError('duplicate skill ID')
    families = {}
    for s in lib['skills']:
        if s['kind'] not in {'common','signature'} or s['level'] != 1 or s['activation'] != 'automatic' or not s['effects']:
            raise ValueError('skill contract')
        for e in s['effects']:
            allowed = {'metric','value','event','roles','family','jobs','requires_coverage_bp'}
            if set(e)-allowed: raise ValueError('unknown effect field')
            m=lib['metrics'][e['metric']]
            if e['event'] != m['event'] or not e['roles'] or not set(e['roles']) <= set(m['allowed_roles']):
                raise ValueError('invalid effect event or scope')
            if len(e['roles']) != len(set(e['roles'])) or type(e['value']) is not int or not 0 < e['value'] <= m['cap']:
                raise ValueError('invalid effect amount')
            if 'jobs' in e and (not e['jobs'] or not set(e['jobs']) <= set(lib['job_weights_bp'])):
                raise ValueError('invalid effect filter')
            if e['family'] in families and families[e['family']] != e['metric']:
                raise ValueError('cross-metric stack family')
            families[e['family']] = e['metric']
    catalog={s['id']:s for s in lib['skills']}
    for h in content['heroes']:
        if set(h) & {'prefect','commander','trait','effects'}: raise ValueError('inline hero effects forbidden')
        aptitude(h['attributes'],{'command':10000})
        skills=h['skill_ids']
        if not 1 <= len(skills) <= 5 or len(skills) != len(set(skills)): raise ValueError('hero skill slots')
        if any(s not in catalog for s in skills): raise ValueError('unknown skill reference')
        if sum(catalog[s]['kind']=='signature' for s in skills)>1: raise ValueError('signature count')
    if 'policy_fit' in cfg['governance']: raise ValueError('per-name policy fit forbidden')

def recommendation(lib: dict, person: dict, policy: str) -> int:
    base = aptitude(person['attributes'], lib['appointment_weights_bp']['prefect'])
    weights = lib['policy_fit_job_weights_bp'][policy]
    source = Source(person,'prefect',True)
    total = sum(weight * (leader_bonus(lib,[source],job) + resolve(lib,[source],'work_rate_bp',job=job)) for job,weight in weights.items())
    return base + min(lib['policy_fit_max_bonus'], total * lib['policy_fit_max_bonus'] // (10000 * lib['policy_fit_normalizer_bp']))

def training_rate(lib: dict, commander: dict, level: int=1, facility_bp: int=0, penalty_bp: int=0) -> int:
    r=lib['rates']
    if not 1<=level<=5 or not 0<=facility_bp<=5000 or not 0<=penalty_bp<=5000: raise ValueError('training rate bounds')
    a=aptitude(commander['attributes'],lib['job_weights_bp']['guard'])
    personal=min(r['worker_attribute_cap'],max(0,a-r['baseline'])*r['worker_bp_per_point'])
    skill=resolve(lib,[Source(commander,'commander',True)],'training_rate_bp')
    return max(r['work_total_min'],min(r['work_total_max'],10000+personal+(level-1)*100+skill+facility_bp-penalty_bp))
