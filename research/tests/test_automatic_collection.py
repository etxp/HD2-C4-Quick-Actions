import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from collect_actions import analyze,infer_phase,read_session,select_latest_session

def encode(rows):return b''.join((json.dumps(r)+'\n').encode() for r in rows)

with tempfile.TemporaryDirectory() as directory:
    root=Path(directory)
    def session(time,version,rows):
        stem=f'C4DualInput_20260920T{time}Z_001'
        path=root/(stem+'_part1.log')
        path.write_bytes(encode([dict(record_type='log_segment',session_id=stem,segment=1,slot=1,
            version=version,startup_layout_verified=True),*rows]))
        return path
    current=session('040000','0.6.0-exp06',[
        dict(record_type='capture',enabled=True,reason='automatic_activation'),
        dict(record_type='input',input='RMB',event='PRESSED',fire_gate_active=True),
        dict(record_type='gameplay_guard',runtime_state='reload_or_menu_key_held',controls_allowed=False),
        dict(record_type='gameplay_guard',runtime_state='gameplay',controls_allowed=True),
        dict(record_type='input',input='LMB',event='PRESSED',fire_gate_active=True)])
    session('050000','0.5.0-exp05',[dict(record_type='action_call')])
    session('060000','0.6.0-exp06',[dict(record_type='capture',enabled=True)])
    chosen,skipped=select_latest_session(list(root.glob('*.log')),'0.6.')
    assert chosen==current and len(skipped)==1
    print('PASS EXP06 selection ignores newer EXP05 and unused automatic startup')
    raw,_,_=read_session(chosen);r=analyze(raw)
    assert r['selection']['capture_sessions']==1 and not r['selection']['stopped']
    assert r['pressed_counts']=={'RMB':1,'LMB':1} and len(r['gameplay_guard_transitions'])==2
    print('PASS automatic capture includes inputs before and after a transient reload pause')
    assert infer_phase(current.name,r['versions'],'exp03')=='exp06'
    assert infer_phase(current.name,['0.5.0-exp05'],'exp06')=='exp05'
    assert infer_phase(current.name,['0.4.0-exp04'],'exp06')=='exp04'
    assert infer_phase('C4Actions_test.log',['0.3.2-exp03'],'exp03')=='exp03'
    print('PASS archived phase follows runtime version including ring-only EXP06 header')
