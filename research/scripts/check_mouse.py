#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""EXP04 synthetic integration and audited mutation surface; no live game calls."""
import hashlib
import json
import re
import subprocess
from assemble_mouse import ROOT,assemble

def main():
    source_hash=assemble()
    source=(ROOT/'src/c4_dual_input.lua').read_text()
    for pattern in [r'VirtualProtect',r'VirtualAlloc',r'SendInput',r'mouse_event',r'keybd_event',
                    r'ffi\.C\.',r'ffi\.copy\([^\n]*game']:
        assert not re.search(pattern,source),pattern
    calls=re.findall(r"ffi\.cast\('[^'\n]*\(\*\)[^'\n]*',game\+(0x[0-9a-f]+)\)",source)
    assert calls==['0x7c21a0','0x73ca00','0x73bf20','0x74b220']
    assert len(re.findall(r'ffi\.cast\([^\n]*\(\*\)',source))==4
    assert source.count('k.WriteProcessMemory(')==1
    assert "k.WriteProcessMemory(process,ffi.cast('void *',flags_address+1),target,1,count)" in source
    assert "(before==0x1148 and after==0x148) or (before==0x148 and after==0x1148)" in source
    assert 'fire_gate_exchange' not in (ROOT/'src/read_only_windows.lua').read_text()
    assert "device_button(engine.Keyboard,'f8'" not in source and "device_button(engine.Keyboard,'f9'" not in source
    runs=[]
    for command in [['luajit','tests/test_mouse.lua'],['luajit','tests/test_mouse_entry.lua'],
                    ['luajit','tests/test_actions.lua'],['python','-B','tests/test_action_collection.py'],
                    ['luajit','-e',"assert(loadfile('src/c4_dual_input.lua')); print('PASS EXP04 assembled syntax')"]]:
        run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
        print(run.stdout,end='');print(run.stderr,end='')
        runs.append(dict(command=command,exit_code=run.returncode,stdout=run.stdout,stderr=run.stderr))
    files=['src/c4_probe.lua','src/context_reader.lua','src/read_only_windows.lua',
        'src/action_reader.lua','src/action_backend.lua','src/action_controller.lua',
        'src/native_actions_windows.lua','src/window_focus.lua','src/fire_gate_windows.lua',
        'src/weapon_fire_gate.lua','src/mouse_router.lua','src/mouse_tick.lua','src/c4_dual_input.lua',
        'scripts/derive_mouse.py','scripts/assemble_mouse.py','scripts/check_mouse.py',
        'scripts/build_probe.py','scripts/collect_actions.py','tests/test_action_collection.py',
        'tests/context_fixture.lua','tests/action_fixture.lua','tests/test_actions.lua',
        'tests/test_mouse.lua','tests/test_mouse_entry.lua','evidence/mouse-layout.json']
    report=dict(evidence_kind='MOCK_AND_STATIC',source_sha256=source_hash,
        exit_code=0 if all(r['exit_code']==0 for r in runs) else 1,
        passed=sum(r['stdout'].count('PASS ') for r in runs),runs=runs,
        direct_native_calls=calls,game_executed=False,mouse_routing_live_verified=False,
        scoped_data_write=dict(bytes=1,field='Weapon.flags bit 12',transitions=['0x1148 -> 0x148','0x148 -> 0x1148']),
        files={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files})
    (ROOT/'evidence/mouse-offline-tests.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(report['exit_code'])

if __name__=='__main__':main()
