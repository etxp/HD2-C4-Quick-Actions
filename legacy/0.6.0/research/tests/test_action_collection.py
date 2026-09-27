import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from collect_actions import analyze,select_latest

def encode(rows):return b''.join((json.dumps(r)+'\n').encode() for r in rows)
def event(kind,**fields):return dict(record_type=kind,evidence_kind='MOCK',request_id=1,**fields)

rows=[event('action_call',requested_action='DEPLOY',ammo_available=4),
      event('action_returned'),event('action_started',fire_mode_before='DETONATE',fire_mode_after='DETONATE',
          fire_mode_unchanged=True,ammo_available=3),event('action_finished')]
r=analyze(encode(rows))
assert r['evidence_kind']=='MOCK_AND_STATIC' and r['actions'][0]['opposite_mode_lifecycle_observed']
assert r['actions'][0]['ammo_delta']==-1 and r['actions'][0]['gameplay_success']=='REQUIRES_VISUAL_CONFIRMATION'
assert r['final_route']=='PENDING'
print('PASS collector separates cross-mode lifecycle and ammo evidence from gameplay success')

r=analyze(encode(rows[:-1]+[event('action_fault',reason='unconfirmed')]))
assert not r['actions'][0]['lifecycle_ended'] and not r['actions'][0]['opposite_mode_lifecycle_observed']
assert len(r['faults'])==1
print('PASS collector never treats an interrupted or faulted lifecycle as completed')

r=analyze(encode(rows)+b'{"incomplete":')
assert r['trailing_partial_row_ignored'] and r['rows']==4
try:analyze(encode(rows)+b'{bad}\n')
except json.JSONDecodeError:pass
else:raise AssertionError('malformed complete record accepted')
print('PASS collector tolerates only a trailing incomplete write, not corrupt full records')

captures=[dict(record_type='session',version='fixture'),dict(record_type='layout_verified'),
    dict(record_type='capture',enabled=True,tick=10),*rows,
    dict(record_type='capture',enabled=False),dict(record_type='capture',enabled=True,tick=100),
    dict(record_type='input',input='F8',event='PRESSED'),
    dict(record_type='action_context',context_status='snapshot_unavailable',reason='unsupported_c4_weapon_driver_flags'),
    dict(record_type='action_rejected',reason='no_fresh_c4_context'),dict(record_type='capture',enabled=False),
    dict(record_type='capture',enabled=True,tick=200),dict(record_type='capture',enabled=False)]
r=analyze(encode(captures))
assert r['selection']['selected_capture']==2 and r['selection']['newer_captures_without_test_input']==1
assert r['actions']==[] and r['pressed_counts']=={'F8':1} and r['layout_verified']
assert r['rejections']=={'no_fresh_c4_context':1}
assert r['context_failures']=={'unsupported_c4_weapon_driver_flags':1}
print('PASS collector prioritizes the last actual capture and retains the underlying failure')

with tempfile.TemporaryDirectory() as d:
    old=Path(d)/'C4Actions_20260919T223819Z_001.log'
    tested=Path(d)/'C4Actions_20260919T224134Z_001.log'
    startup=Path(d)/'C4Actions_20260919T224455Z_001.log'
    old.write_bytes(encode(rows));tested.write_bytes(encode(captures));startup.write_bytes(encode([dict(record_type='session')]))
    chosen,skipped=select_latest([old,startup,tested])
    assert chosen==tested and len(skipped)==1 and skipped[0]['source']==str(startup)
    assert select_latest([startup])==(startup,[])
print('PASS newer startup-only logs cannot replace the most recent tested session')

r=analyze(encode([dict(record_type='action_context',action_context_status='rejected',
    action_context_error='unsupported_c4_ammo_path',weapon_driver_flags='00000088')]))
assert r['context_failures']=={'unsupported_c4_ammo_path':1}
print('PASS fixed diagnostic status is included in collection summaries')

mouse=[dict(record_type='capture',enabled=True,tick=10),
    dict(record_type='input',input='RMB',event='PRESSED_RELEASED',fire_gate_active=True),
    dict(record_type='capture',enabled=False),
    dict(record_type='capture',enabled=True,tick=20),
    dict(record_type='input',input='LMB',event='PRESSED',fire_gate_active=False),
    dict(record_type='capture',enabled=False)]
r=analyze(encode(mouse))
assert r['selection']['selected_capture']==1 and r['pressed_counts']=={'RMB':1}
assert r['selection']['newer_captures_without_test_input']==1
print('PASS EXP04 short mouse clicks count as tests only with an active C4 gate')
