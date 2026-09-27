#!/usr/bin/env python3
"""Archive C4 action evidence; distinguish native lifecycle from gameplay success."""
import argparse
from collections import Counter
import hashlib
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
LOGS=None

def parse(raw):
    assert len(raw)<=20*1024*1024,'log_size_limit'
    rows=[];partial=False
    lines=raw.splitlines()
    for i,line in enumerate(lines):
        try:row=json.loads(line)
        except json.JSONDecodeError:
            if i==len(lines)-1 and not raw.endswith(b'\n'):
                partial=True;break
            raise
        assert isinstance(row,dict),'non_object_row'
        rows.append(row)
    return rows,partial

def has_test_activity(rows):
    return any((r.get('record_type')=='input' and r.get('input') in ('F8','F9') and r.get('event')=='PRESSED')
               or (r.get('record_type')=='input' and r.get('input') in ('LMB','RMB')
                   and r.get('event') in ('PRESSED','PRESSED_RELEASED') and r.get('fire_gate_active') is True)
               or (r.get('record_type')=='input' and r.get('input') in ('LT','RT','L2','R2')
                   and r.get('event')=='PRESSED')
               or r.get('record_type') in ('action_request','action_rejected','action_call') for r in rows)

def last_test(rows):
    starts=[i for i,r in enumerate(rows) if r.get('record_type')=='capture' and r.get('enabled') is True]
    if not starts:return rows,dict(selection='no_capture_boundary',capture_sessions=0)
    segments=[rows[start:starts[i+1] if i+1<len(starts) else len(rows)] for i,start in enumerate(starts)]
    selected=next((i for i in range(len(segments)-1,-1,-1) if has_test_activity(segments[i])),len(segments)-1)
    chosen=segments[selected]
    return chosen,dict(selection='latest_capture_with_test_activity' if has_test_activity(chosen) else 'latest_capture_without_test_input',
        capture_sessions=len(segments),selected_capture=selected+1,newer_captures_without_test_input=len(segments)-1-selected,
        start_tick=chosen[0].get('tick'),start_utc=chosen[0].get('timestamp_utc'),
        stopped=any(r.get('record_type')=='capture' and r.get('enabled') is False for r in chosen))

def select_latest(paths):
    # UTC timestamps in filenames identify creation order; an older process
    # can flush late and therefore must not outrank a later test by mtime.
    candidates=sorted(paths,key=lambda p:p.name,reverse=True)
    skipped=[]
    for path in candidates:
        rows,_=parse(path.read_bytes())
        if has_test_activity(rows):return path,skipped
        skipped.append(dict(source=str(path),rows=len(rows),reason='no_test_input_or_action'))
    return (candidates[0],[]) if candidates else (None,[])

def read_session(path):
    """Reconstruct the retained ring in segment order; keep raw files for evidence."""
    match=re.fullmatch(r'(C4DualInput_\d{8}T\d{6}Z_\d{3})_part([1-4])\.log',path.name)
    if not match:
        raw=path.read_bytes();assert len(raw)<=5*1024*1024,'part_size_limit'
        return raw,[dict(path=path,raw=raw)],dict(rolling=False)
    stem=match[1];parts=[]
    for candidate in path.parent.glob(stem+'_part[1-4].log'):
        raw=candidate.read_bytes();assert len(raw)<=5*1024*1024,'part_size_limit'
        rows,partial=parse(raw);assert rows,'empty_ring_segment'
        h=rows[0];segment=h.get('segment');slot=h.get('slot')
        assert h.get('record_type')=='log_segment' and h.get('session_id')==stem,'wrong_ring_session'
        assert type(segment) is int and segment>0 and slot==(segment-1)%4+1,'invalid_ring_segment'
        assert candidate.name==stem+'_part'+str(slot)+'.log','wrong_ring_slot'
        parts.append(dict(path=candidate,raw=raw,rows=rows,segment=segment,partial=partial))
    parts.sort(key=lambda p:p['segment'])
    assert len({p['segment'] for p in parts})==len(parts),'duplicate_ring_segment'
    assert parts[-1]['segment']-parts[0]['segment']<4,'ring_changed_during_collection'
    merged=b''.join((json.dumps(row,separators=(',',':'))+'\n').encode() for p in parts for row in p['rows'])
    return merged,parts,dict(rolling=True,session_id=stem,retained_segments=[p['segment'] for p in parts],
        earlier_history_overwritten=parts[0]['segment']>1,
        gaps=[n for n in range(parts[0]['segment'],parts[-1]['segment']+1) if n not in {p['segment'] for p in parts}],
        partial_parts_ignored=[p['path'].name for p in parts if p['partial']])

def select_latest_session(paths,version_prefix=None):
    candidates={}
    for path in paths:
        stem=re.sub(r'_part[1-4](?=\.log$)','',path.name)
        candidates.setdefault(stem,path)
    eligible=[];skipped=[]
    for _,path in sorted(candidates.items(),reverse=True):
        raw,_,_=read_session(path);rows,_=parse(raw)
        if version_prefix and not any(str(r.get('version','')).startswith(version_prefix) for r in rows):continue
        eligible.append(path)
        if has_test_activity(rows):return path,skipped
        skipped.append(dict(source=str(path),rows=len(rows),reason='no_test_input_or_action'))
    return (eligible[0],[]) if eligible else (None,[])

def analyze(raw):
    all_rows,partial=parse(raw)
    rows,selection=last_test(all_rows)
    records=Counter(r.get('record_type','UNKNOWN') for r in rows)
    requests={}
    for row in rows:
        request=row.get('request_id')
        if request is None:continue
        requests.setdefault(str(request),{})[row['record_type']]=row
    actions=[]
    for request,events in requests.items():
        call=events.get('action_call',{});start=events.get('action_started',{})
        action=call.get('requested_action','UNKNOWN')
        mode=start.get('fire_mode_before')
        complete='action_finished' in events and not any(k in events for k in ('action_fault','action_observation_ended'))
        before,after=call.get('ammo_available'),start.get('ammo_available')
        actions.append(dict(request_id=request,action=action,call_tick=call.get('tick'),
            called='action_returned' in events,active_observed=bool(start),lifecycle_ended=complete,
            mode_before=mode,mode_after=start.get('fire_mode_after'),
            mode_unchanged=start.get('fire_mode_unchanged'),
            opposite_mode_lifecycle_observed=bool(complete and start.get('fire_mode_unchanged') is True
                and ((action=='DEPLOY' and mode=='DETONATE') or (action=='DETONATE' and mode=='DEPLOY'))),
            ammo_before=before,ammo_after=after,
            ammo_delta=after-before if isinstance(before,(int,float)) and isinstance(after,(int,float)) else None,
            ammo_counter_source=call.get('ammo_counter_source'),
            ammo_counter_semantics=call.get('ammo_counter_semantics','UNSPECIFIED'),
            ammo_delta_is_backpack_validation=False,
            gameplay_success='REQUIRES_VISUAL_CONFIRMATION',events=events))
    return dict(evidence_kind='MOCK_AND_STATIC' if any(r.get('evidence_kind')=='MOCK' for r in all_rows)
                else 'RUNTIME_OBSERVATION',rows=len(all_rows),selected_rows=len(rows),record_counts=dict(records),
        all_record_counts=dict(Counter(r.get('record_type','UNKNOWN') for r in all_rows)),
        selection=selection,versions=list(dict.fromkeys(r.get('version') for r in all_rows
            if r.get('record_type') in ('session','log_segment') and r.get('version'))),
        pressed_counts=dict(Counter(r.get('input') for r in rows
            if r.get('record_type')=='input' and r.get('event') in ('PRESSED','PRESSED_RELEASED'))),
        fire_gate_transitions=[r for r in rows if r.get('record_type')=='fire_gate'],
        context_failures=dict(Counter(r.get('action_context_error') or r.get('reason','UNKNOWN') for r in rows
            if r.get('record_type')=='action_context' and
            (r.get('context_status')=='snapshot_unavailable' or r.get('action_context_status')=='rejected'))),
        trailing_partial_row_ignored=partial,
        gameplay_guard_transitions=[r for r in rows if r.get('record_type')=='gameplay_guard'],
        layout_verified=any(r.get('record_type')=='layout_verified' or
            r.get('record_type')=='log_segment' and r.get('startup_layout_verified') is True for r in all_rows),
        actions=actions,rejections=dict(Counter(r.get('reason','UNKNOWN') for r in rows
                                               if r.get('record_type')=='action_rejected')),
        faults=[r for r in rows if r.get('record_type') in ('action_fault','probe_error','limit')],
        markers=[r for r in rows if r.get('record_type')=='manual_marker'],
        deploy_independently_callable='UNRESOLVED_PENDING_GAMEPLAY_CONFIRMATION',
        detonate_independently_callable='UNRESOLVED_PENDING_GAMEPLAY_CONFIRMATION',
        final_route='PENDING',multiplayer_tested=False,
        interpretation='Primary results use the last capture with test input. Native lifecycle and ammo counters do not prove a throw, explosion or backpack consumption.')

def infer_phase(source_name,versions,fallback):
    for prefix,phase in [('0.6.','exp06'),('0.5.','exp05')]:
        if any(str(v).startswith(prefix) for v in versions):return phase
    return 'exp04' if source_name.startswith('C4DualInput_') else fallback

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path)
    p.add_argument('--log-dir',type=Path,help='Directory containing your C4DualInput logs');p.add_argument('--phase',choices=['exp03','exp04','exp05','exp06'],default='exp03');args=p.parse_args()
    source=args.source;skipped=[]
    logs=args.log_dir
    if source is None and logs is None:p.error('provide --source FILE or --log-dir DIRECTORY')
    if source is None:
        paths=list(logs.glob('C4DualInput_*.log' if args.phase in ('exp04','exp05','exp06') else 'C4Actions_*.log'))
        source,skipped=select_latest_session(paths,{'exp06':'0.6.','exp05':'0.5.'}.get(args.phase))
        if source is None:
            print(json.dumps({'status':'waiting_for_first_'+args.phase.upper()+'_log','expected_directory':str(logs)}));return
    assert source.is_file(),'log_not_found'
    raw,parts,ring=read_session(source);digest=hashlib.sha256(raw).hexdigest()
    report=analyze(raw)
    report.update(source=str(source.resolve()),sha256=digest,skipped_newer_logs=skipped,ring=ring)
    phase=infer_phase(source.name,report['versions'],args.phase)
    directory=ROOT/'local-evidence'/('live-'+phase+'-'+ring.get('session_id',source.stem)+'-'+digest[:12])
    directory.mkdir(parents=True,exist_ok=True)
    report['parts']=[]
    for part in parts:
        archive=directory/part['path'].name
        if archive.exists():assert archive.read_bytes()==part['raw'],'archive_conflict'
        else:archive.write_bytes(part['raw'])
        report['parts'].append(dict(name=archive.name,sha256=hashlib.sha256(part['raw']).hexdigest(),
            bytes=len(part['raw']),segment=part.get('segment')))
    if ring['rolling']:(directory/'retained-session.jsonl').write_bytes(raw)
    (directory/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'archive':str(directory),'rows':report['rows'],'actions':len(report['actions']),
        'opposite_mode_lifecycles':sum(a['opposite_mode_lifecycle_observed'] for a in report['actions']),
        'faults':len(report['faults']),'rejections':report['rejections'],
        'pressed_counts':report['pressed_counts'],'context_failures':report['context_failures'],
        'selection':report['selection'],'skipped_newer_logs':skipped,
        'gameplay_success':'REQUIRES_VISUAL_CONFIRMATION'},indent=2))

if __name__=='__main__':main()
