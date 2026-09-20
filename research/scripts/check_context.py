#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""EXP02 checks: synthetic data, input regression, assembled syntax, read-only audit."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
from assemble_context import assemble,ROOT

def main():
    source_hash=assemble()
    source=(ROOT/'src/c4_context_probe.lua').read_text()
    # Reject memory mutation/input injection APIs and all native function casts.
    forbidden=[r'WriteProcessMemory',r'VirtualProtect',r'VirtualAlloc',r'SendInput',
               r'mouse_event',r'keybd_event',r'ffi\.cast\([^\n]*\(\s*\*',r'ffi\.C\.',
               r'ffi\.copy\([^\n]*game']
    for pattern in forbidden:assert not re.search(pattern,source),pattern
    runs=[]
    for command in [['luajit','tests/test_context.lua'],['luajit','tests/test_probe.lua'],
                    ['luajit','tests/test_context_entry.lua'],
                    ['luajit','-e',"assert(loadfile('src/c4_context_probe.lua')); print('PASS assembled Lua syntax')"]]:
        run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
        print(run.stdout,end='');print(run.stderr,end='')
        runs.append(dict(command=command,exit_code=run.returncode,stdout=run.stdout,stderr=run.stderr))
    files=['src/context_reader.lua','src/context_runtime.lua','src/read_only_windows.lua',
           'src/c4_probe.lua','src/c4_context_probe.lua','scripts/assemble_context.py',
           'tests/test_context.lua','tests/test_probe.lua','tests/test_context_entry.lua','evidence/context-layout.json']
    report=dict(evidence_kind='MOCK_AND_STATIC',source_sha256=source_hash,
        exit_code=0 if all(x['exit_code']==0 for x in runs) else 1,
        passed=sum(x['stdout'].count('PASS ') for x in runs),runs=runs,read_only_audit='passed',
        game_executed=False,context_live_verified=False,direct_actions_tested=False,
        files={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files})
    (ROOT/'evidence/context-offline-tests.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(report['exit_code'])

if __name__=='__main__':main()
