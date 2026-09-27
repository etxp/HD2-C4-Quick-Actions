import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from collect_actions import analyze,read_session,select_latest_session

def encode(rows):return b''.join((json.dumps(r)+'\n').encode() for r in rows)
def write_part(root,stem,segment,rows):
    slot=(segment-1)%4+1
    path=root/f'{stem}_part{slot}.log'
    path.write_bytes(encode([dict(record_type='log_segment',session_id=stem,segment=segment,slot=slot,
        version='0.5.0-exp05',startup_layout_verified=True),*rows]));return path

with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);stem='C4DualInput_20260920T010000Z_001'
    p=write_part(root,stem,4,[dict(record_type='capture',enabled=True),
        dict(record_type='input',input='RT',event='PRESSED'),
        dict(record_type='action_call',request_id=1,requested_action='DETONATE')])
    write_part(root,stem,5,[dict(record_type='action_returned',request_id=1),
        dict(record_type='action_started',request_id=1,fire_mode_before='DEPLOY',fire_mode_after='DEPLOY',fire_mode_unchanged=True)])
    write_part(root,stem,6,[dict(record_type='action_finished',request_id=1)])
    raw,parts,ring=read_session(p);r=analyze(raw)
    assert ring['retained_segments']==[4,5,6] and ring['earlier_history_overwritten']
    assert r['layout_verified'] and r['versions']==['0.5.0-exp05'] and r['pressed_counts']=={'RT':1}
    assert len(r['actions'])==1 and r['actions'][0]['opposite_mode_lifecycle_observed']
    assert len(parts)==3
    print('PASS collector orders wrapped ring slots by sequence and joins a split lifecycle')
    newer='C4DualInput_20260920T011000Z_001'
    write_part(root,newer,1,[dict(record_type='session',version='0.5.0-exp05')])
    old=root/'C4DualInput_20260920T005000Z_001.log'
    old.write_bytes(encode([dict(record_type='session',version='0.4.0-exp04'),dict(record_type='action_call')]))
    selected,skipped=select_latest_session(list(root.glob('*.log')),'0.5.')
    assert selected.name.startswith(stem) and len(skipped)==1
    print('PASS collector selects the latest tested EXP05 session over an untested startup and older EXP04')
    last=write_part(root,stem,7,[]);last.write_bytes(last.read_bytes()+b'{"incomplete":')
    _,_,ring=read_session(p);assert ring['partial_parts_ignored']==[last.name]
    print('PASS collector preserves raw ring parts and marks incomplete trailing writes')
    bad=write_part(root,newer,2,[])
    rows=[json.loads(x) for x in bad.read_text().splitlines()];rows[0]['session_id']=stem
    bad.write_bytes(encode(rows))
    try:read_session(bad)
    except AssertionError as e:assert str(e)=='wrong_ring_session'
    else:raise AssertionError('mixed sessions were accepted')
    print('PASS collector rejects unrelated session headers in a ring slot')
