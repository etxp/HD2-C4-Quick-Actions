#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Archive one EXP02 log; never equate observation with action success."""
import argparse
import collections
import hashlib
import json
from pathlib import Path

ROOT=Path(os.environ.get('C4_RESEARCH_WORKSPACE',str(Path(__file__).resolve().parents[2])))
LOGS=Path(os.environ.get('C4_RESEARCH_LOGS','<local-home>/.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/CowboyBingus/Helldivers2/Logs'))

def summarize(rows):
    sessions=[r for r in rows if r.get('record_type')=='session']
    assert len(sessions)==1 and sessions[0]['version']=='0.2.0-exp02','not one EXP02 session'
    layouts=[r for r in rows if r.get('record_type')=='layout_verified']
    expected=json.loads((ROOT/'evidence/context-layout.json').read_text())['module_sha256']
    verified=any(r.get('module_sha256')==expected for r in layouts)
    captures=[];active=None
    for r in rows:
        if r.get('record_type')=='capture':
            if r.get('enabled'):
                active={'start_tick':r['tick'],'end_tick':None,'markers':[],'context_samples':0}
                captures.append(active)
            elif active is not None:
                active['end_tick']=r['tick'];active=None
        elif active is not None:
            if r.get('record_type')=='context':active['context_samples']+=1
            if r.get('record_type')=='manual_marker':
                keys=['tick','elapsed_ms','current_weapon','current_weapon_resource','selected_slot',
                      'context_status','context_sample_age_ms','weapon_function_types','weapon_function_values',
                      'weapon_state_12','ability_template_status','ability_descriptors']
                active['markers'].append({k:r[k] for k in keys if k in r})
    context=[r for r in rows if r.get('record_type')=='context']
    templates={}
    for r in context:
        if r.get('ability_template_status')=='present':
            templates[r['ability_template_hex']]=r.get('ability_descriptors')
    return dict(evidence_kind='RUNTIME_OBSERVATION',rows=len(rows),layout_verified=verified,
        context_samples=len(context),captures=captures,
        statuses=dict(collections.Counter(r.get('context_status','missing') for r in context)),
        resources=dict(collections.Counter(r.get('current_weapon_resource','UNKNOWN') for r in context)),
        snapshot_failures=dict(collections.Counter(r.get('reason') for r in context if r.get('reason'))),
        ability_templates=templates,
        errors=[r for r in rows if r.get('record_type') in ('probe_error','limit')],
        max_sample_cost_ms=max((r.get('sample_cost_ms',0) for r in context),default=0),
        interpretation='Markers require tester confirmation of protocol order; candidates are not action validation.',
        deploy_independently_callable='UNRESOLVED',detonate_independently_callable='UNRESOLVED',
        gameplay_actions_invoked_by_probe=False,multiplayer_tested=False)

def main():
    p=argparse.ArgumentParser();p.add_argument('log',nargs='?',type=Path);args=p.parse_args()
    candidates=sorted(LOGS.glob('C4Context_*.log'),key=lambda q:q.stat().st_mtime)
    path=args.log or (candidates[-1] if candidates else None)
    if path is None:raise SystemExit('No EXP02 log yet. Install EXP02 and follow docs/CONTEXT_PROBE_README.txt.')
    data=path.read_bytes();assert len(data)<=5*1024*1024,'unexpected log size'
    assert data.endswith(b'\n'),'last record incomplete; retry after log flush'
    rows=[json.loads(line) for line in data.splitlines() if line]
    assert all(r.get('evidence_kind','RUNTIME_OBSERVATION')=='RUNTIME_OBSERVATION' for r in rows),'mock evidence rejected'
    report=summarize(rows)
    report.update(source=str(path),sha256=hashlib.sha256(data).hexdigest())
    output=ROOT/'evidence'/('live-exp02-'+path.stem)
    output.mkdir(exist_ok=True)
    target=output/path.name
    if target.exists():assert target.read_bytes()==data,'existing evidence differs; use a new session'
    else:target.write_bytes(data)
    (output/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
