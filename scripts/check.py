"""Regression checks and captured-native validation; never attaches to the game."""
import hashlib
import argparse
from pathlib import Path
import json
import subprocess
import sys
from assemble import ROOT, VERSION, assemble

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

# Optional: the source of Mod Bindings Menu v2.2 (src/ folder holding poll.lua),
# from https://github.com/CowboyBingus/ModBindingsMenu/releases/tag/v2.2. When
# present, the contract test also runs that release's real poll.lua.
import os
_mbm = os.environ.get('MBM_V22_SRC') or str(ROOT.parent.parent / 'private/deps-20261005/ModBindingsMenu-v2.2/src/src')
MBM_SOURCE = [_mbm] if (Path(_mbm) / 'poll.lua').is_file() else []

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--with-native-capture', action='store_true',
                        help='Also validate a separately supplied private native capture')
    args = parser.parse_args()
    entry = assemble()
    runs = []
    commands = [[sys.executable, 'tests/make_native_fixture.py'],
                [sys.executable, 'tests/test_lua_packaging.py'],
                ['luajit', '-b', str(entry), str(entry.with_suffix('.luac'))],
                ['luajit', '-b', 'private/build/c4_catalog.lua', 'private/build/c4_catalog.luac'],
                # Every gameplay case, in Off and Verbose, against both the
                # historical byte-granular fixture and page-granular memory.
                ['luajit', 'tests/test_runtime.lua'],
                ['luajit', 'tests/test_runtime.lua', 'off'],
                ['luajit', 'tests/test_runtime.lua', 'verbose', 'pages'],
                ['luajit', 'tests/test_runtime.lua', 'off', 'pages'],
                # The same suite with a Mod Bindings Menu v2.2 table (poll, revision).
                ['env', 'C4_MBM=v22', 'luajit', 'tests/test_runtime.lua', 'off'],
                ['env', 'C4_MBM=v22', 'luajit', 'tests/test_runtime.lua', 'verbose'],
                ['luajit', 'tests/test_mbm_contract.lua'] + MBM_SOURCE,
                ['luajit', 'tests/test_flight_observer.lua'],
                ['luajit', 'tests/test_contact_probe.lua'],
                ['luajit', 'tests/test_collision_events.lua'],
                ['luajit', 'tests/test_contact_actions.lua'],
                ['luajit', 'tests/test_mode_labels.lua'],
                ['luajit', 'tests/test_airborne_manual.lua'],
                ['luajit', 'tests/test_optimization.lua'],
                ['luajit', 'tests/test_guard_spans.lua'],
                ['luajit', 'tests/test_snapshot_cache.lua'],
                ['luajit', 'tests/test_snapshot_equivalence.lua'],
                ['luajit', 'tests/test_ui_guard.lua'],
                ['luajit', 'tests/test_guard_quiet.lua'],
                ['luajit', 'tests/test_reload_interval.lua'],
                ['luajit', 'tests/test_routing_observation.lua'],
                ['luajit', 'tests/test_context_scopes.lua'],
                ['luajit', 'tests/test_hex_bytes.lua'],
                ['luajit', 'tests/test_pointer_values.lua'],
                ['luajit', 'tests/test_quiet_context.lua'],
                ['luajit', 'tests/test_scoped_verification.lua'],
                ['luajit', 'tests/test_binding_hints.lua'],
                ['luajit', 'tests/test_idle_work.lua']]
    if args.with_native_capture:
        commands += [[sys.executable, 'scripts/prepare_capture.py'],
                     ['luajit', 'tests/test_capture.lua']]
    for command in commands:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
        runs.append(dict(command=command, exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr))
        print(('PASS' if result.returncode == 0 else 'FAIL'), ' '.join(command))
        if result.returncode:
            print(result.stdout[-3000:], result.stderr[-3000:])
            break
    files = {}
    for folder in ('src', 'tests', 'scripts', 'docs'):
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                files[str(path.relative_to(ROOT))] = sha(path)
    text = entry.read_text()
    assert 'MouseRouter' not in text and 'GamepadInput' not in text and 'ModBindingsBridge' not in text
    assert 'device_button' not in text and 'module_hash' not in text and 'SendInput' not in text
    # Regression barrier for the dev.5 executable-memory hook withdrawn after 1015.
    for forbidden in ('VirtualAlloc', 'VirtualProtect', 'FlushInstructionCache',
                      'LeanGateCode', 'LeanGateWindows', 'VehicleLeanHold', 'expect_prefix'):
        assert forbidden not in text, 'Executable-hook regression: ' + forbidden
    result = dict(version=VERSION, native_capture_checked=args.with_native_capture,
        passed=len(runs)==len(commands) and all(r['exit_code']==0 for r in runs),
        checks=sum(r['stdout'].count('PASS ') for r in runs), runs=runs, files=files,
        entry_sha256=sha(entry), catalog_sha256=sha(ROOT/'private/build/c4_catalog.lua'),
        live_gameplay_verified=False, real_game_modified=False)
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence/checks.json').write_text(json.dumps(result, indent=2, ensure_ascii=False)+'\n')
    print('Checks:', result['checks'], 'live gameplay verified:', False)
    raise SystemExit(0 if result['passed'] else 1)

if __name__ == '__main__': main()
