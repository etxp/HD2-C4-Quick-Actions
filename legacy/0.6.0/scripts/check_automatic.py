#!/usr/bin/env python3
"""EXP06 automatic activation, reload recovery and shared input regression audit."""
import hashlib
import json
import re
import subprocess
from assemble_automatic import ROOT,assemble

def main():
    source_hash=assemble();source=(ROOT/'src/c4_dual_input_auto.lua').read_text()
    for pattern in [r'VirtualProtect',r'VirtualAlloc',r'SendInput',r'mouse_event',r'keybd_event',r'XInputSetState',
                    r'ffi\.C\.',r'ffi\.copy\([^\n]*game',r'\.set_down_threshold\(',r'\.set_dead_zone\(',
                    r'Window\.set_',r"device_button\(engine.Keyboard,'f6'"]:
        assert not re.search(pattern,source),pattern
    calls=re.findall(r"ffi\.cast\('[^'\n]*\(\*\)[^'\n]*',game\+(0x[0-9a-f]+)\)",source)
    assert calls==['0x7c21a0','0x73ca00','0x73bf20','0x74b220']
    assert len(re.findall(r'ffi\.cast\([^\n]*\(\*\)',source))==4
    assert source.count('k.WriteProcessMemory(')==1
    assert "k.WriteProcessMemory(process,ffi.cast('void *',flags_address+1),target,1,count)" in source
    assert "version='0.6.0-exp06', capture=true" in source
    runs=[]
    commands=[['luajit','tests/test_automatic.lua'],['luajit','tests/test_gamepad.lua'],
        ['luajit','tests/test_gamepad_mouse_regression.lua'],['luajit','tests/test_mouse.lua'],
        ['luajit','tests/test_actions.lua'],['luajit','tests/test_rolling_log.lua'],
        ['python','-B','tests/test_action_collection.py'],['python','-B','tests/test_gamepad_collection.py'],
        ['python','-B','tests/test_automatic_collection.py'],
        ['luajit','-e',"assert(loadfile('src/c4_dual_input_auto.lua')); print('PASS assembled EXP06 syntax')"]]
    for command in commands:
        run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
        print(run.stdout,end='');print(run.stderr,end='')
        runs.append(dict(command=command,exit_code=run.returncode,stdout=run.stdout,stderr=run.stderr))
    files={str(p.relative_to(ROOT)) for directory,pattern in [('src','*.lua'),('scripts','*.py'),('tests','*.lua'),('tests','*.py'),('evidence','*-layout.json')] for p in (ROOT/directory).glob(pattern)}
    files.update({'dependencies.lock.json','project.json','docs/INSTALL.txt','LICENSE'})
    report=dict(evidence_kind='MOCK_AND_STATIC',source_sha256=source_hash,
        exit_code=0 if all(r['exit_code']==0 for r in runs) else 1,
        passed=sum(r['stdout'].count('PASS ') for r in runs),runs=runs,direct_native_calls=calls,
        game_executed=False,validation_scope='MOCK_AND_STATIC_ONLY',
        tested_exp05_xbox_user_confirmed=True,playstation_hardware_verified=False,
        reload_disarm_root_cause='EXP05 input_guard R fresh edge permanently cleared M.capture',
        activation='AUTOMATIC_LOCAL_C4',reload='TRANSIENT_PAUSE_THEN_RELEASE_BASELINE',
        mapping=dict(mouse='RMB Deploy / LMB Detonate',xbox='LT Deploy / RT Detonate',playstation='L2 Deploy / R2 Detonate'),
        files={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sorted(files)})
    (ROOT/'evidence/automatic-offline-tests.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(report['exit_code'])

if __name__=='__main__':main()
