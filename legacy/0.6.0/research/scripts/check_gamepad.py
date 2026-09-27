#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""EXP05 controller, guard, rolling-log and shared action regression audit."""
import hashlib
import json
import re
import subprocess
from assemble_gamepad import ROOT,assemble

def main():
    source_hash=assemble();source=(ROOT/'src/c4_dual_input_gamepad.lua').read_text()
    for pattern in [r'VirtualProtect',r'VirtualAlloc',r'SendInput',r'mouse_event',r'keybd_event',r'XInputSetState',
                    r'ffi\.C\.',r'ffi\.copy\([^\n]*game',r'\.set_down_threshold\(',r'\.set_dead_zone\(']:
        assert not re.search(pattern,source),pattern
    calls=re.findall(r"ffi\.cast\('[^'\n]*\(\*\)[^'\n]*',game\+(0x[0-9a-f]+)\)",source)
    assert calls==['0x7c21a0','0x73ca00','0x73bf20','0x74b220']
    assert len(re.findall(r'ffi\.cast\([^\n]*\(\*\)',source))==4
    assert source.count('k.WriteProcessMemory(')==1
    assert "k.WriteProcessMemory(process,ffi.cast('void *',flags_address+1),target,1,count)" in source
    assert 'bounded_log_limit' not in source and "M.status='log_limit'" not in source
    runs=[]
    commands=[['luajit','tests/test_gamepad.lua'],['luajit','tests/test_gamepad_mouse_regression.lua'],
        ['luajit','tests/test_mouse.lua'],['luajit','tests/test_actions.lua'],['luajit','tests/test_rolling_log.lua'],
        ['python','-B','tests/test_action_collection.py'],['python','-B','tests/test_gamepad_collection.py'],
        ['luajit','-e',"assert(loadfile('src/c4_dual_input_gamepad.lua')); print('PASS assembled EXP05 syntax')"]]
    for command in commands:
        run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
        print(run.stdout,end='');print(run.stderr,end='')
        runs.append(dict(command=command,exit_code=run.returncode,stdout=run.stdout,stderr=run.stderr))
    files=['src/c4_probe.lua','src/context_reader.lua','src/read_only_windows.lua','src/action_reader.lua',
        'src/action_backend.lua','src/action_controller.lua','src/native_actions_windows.lua','src/window_focus.lua',
        'src/fire_gate_windows.lua','src/weapon_fire_gate.lua','src/mouse_router.lua','src/mouse_tick.lua',
        'src/gamepad_input.lua','src/input_guard.lua','src/rolling_log.lua','src/dual_input_tick.lua','src/c4_dual_input_gamepad.lua',
        'scripts/assemble_mouse.py','scripts/assemble_gamepad.py','scripts/check_gamepad.py','scripts/build_probe.py',
        'scripts/collect_actions.py','tests/context_fixture.lua','tests/action_fixture.lua','tests/gamepad_entry_fixture.lua',
        'tests/test_gamepad.lua','tests/test_gamepad_mouse_regression.lua','tests/test_rolling_log.lua',
        'tests/test_actions.lua','tests/test_mouse.lua','tests/test_action_collection.py','tests/test_gamepad_collection.py',
        'evidence/mouse-layout.json']
    report=dict(evidence_kind='MOCK_AND_STATIC',source_sha256=source_hash,
        exit_code=0 if all(r['exit_code']==0 for r in runs) else 1,
        passed=sum(r['stdout'].count('PASS ') for r in runs),runs=runs,direct_native_calls=calls,
        game_executed=False,gamepad_live_verified=False,empty_ammo_disarm_live_resolved=False,
        known_log_limit_shutdown_removed=True,
        mapping=dict(mouse='RMB Deploy / LMB Detonate',xbox='LT Deploy / RT Detonate',playstation='L2 Deploy / R2 Detonate'),
        files={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files})
    (ROOT/'evidence/gamepad-offline-tests.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(report['exit_code'])

if __name__=='__main__':main()
