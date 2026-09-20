#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""EXP03 regression, denial conditions, assembled integration, and call audit."""
import hashlib
import json
import re
import subprocess
from assemble_actions import ROOT,assemble

def main():
    source_hash=assemble()
    source=(ROOT/'src/c4_action_prototype.lua').read_text()
    for pattern in [r'WriteProcessMemory',r'VirtualProtect',r'VirtualAlloc',r'SendInput',
                    r'mouse_event',r'keybd_event',r'ffi\.C\.',r'ffi\.copy\([^\n]*game']:
        assert not re.search(pattern,source),pattern
    call_targets=re.findall(r"ffi\.cast\('[^'\n]*\(\*\)[^'\n]*',game\+(0x[0-9a-f]+)\)",source)
    assert call_targets==['0x7c21a0','0x73ca00','0x73bf20','0x74b220'],call_targets
    # Every cast to a callable type must be on this reviewed four-call allowlist.
    assert len(re.findall(r'ffi\.cast\([^\n]*\(\*\)',source))==4
    runs=[]
    for command in [['luajit','tests/test_actions.lua'],['luajit','tests/test_action_entry.lua'],
                    ['luajit','tests/test_context.lua'],['luajit','tests/test_context_entry.lua'],
                    ['luajit','tests/test_probe.lua'],
                    ['python','-B','tests/test_action_collection.py'],
                    ['luajit','-e',"assert(loadfile('src/c4_action_prototype.lua')); print('PASS EXP03 assembled syntax')"]]:
        run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
        print(run.stdout,end='');print(run.stderr,end='')
        runs.append(dict(command=command,exit_code=run.returncode,stdout=run.stdout,stderr=run.stderr))
    files=['src/context_reader.lua','src/read_only_windows.lua','src/c4_probe.lua',
        'src/action_reader.lua','src/action_backend.lua','src/action_controller.lua',
        'src/native_actions_windows.lua','src/window_focus.lua','src/c4_action_prototype.lua',
        'scripts/derive_actions.py','scripts/assemble_actions.py','scripts/check_actions.py',
        'tests/context_fixture.lua','tests/action_fixture.lua','tests/test_actions.lua',
        'tests/test_action_entry.lua','tests/test_context.lua','tests/test_context_entry.lua',
        'tests/test_probe.lua','scripts/collect_actions.py','tests/test_action_collection.py',
        'evidence/action-layout.json']
    report=dict(evidence_kind='MOCK_AND_STATIC',source_sha256=source_hash,
        exit_code=0 if all(r['exit_code']==0 for r in runs) else 1,
        passed=sum(r['stdout'].count('PASS ') for r in runs),runs=runs,
        direct_native_calls=call_targets,game_executed=False,direct_actions_live_verified=False,
        files={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files})
    (ROOT/'evidence/action-offline-tests.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(report['exit_code'])

if __name__=='__main__':main()
