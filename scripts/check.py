"""Regression checks and captured-native validation; never attaches to the game."""
import hashlib
import argparse
import json
import subprocess
import sys
from assemble import ROOT, VERSION, assemble

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

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
                ['luajit', 'tests/test_runtime.lua'],
                ['luajit', 'tests/test_flight_observer.lua'],
                ['luajit', 'tests/test_contact_probe.lua'],
                ['luajit', 'tests/test_collision_events.lua'],
                ['luajit', 'tests/test_contact_actions.lua'],
                ['luajit', 'tests/test_mode_labels.lua'],
                ['luajit', 'tests/test_airborne_manual.lua']]
    if args.with_native_capture:
        commands += [[sys.executable, 'scripts/prepare_capture.py'],
                     ['luajit', 'tests/test_capture.lua']]
    for command in commands:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
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
