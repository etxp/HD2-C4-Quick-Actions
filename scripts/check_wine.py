"""Run the Windows declaration test in a locally supplied game Lua DLL (Wine).

Optional and private: needs Wine, winegcc and the game's bin/lua51.dll, which
stays under ignored private/. It calls the real kernel32/user32 on the test
process's own memory only and never attaches to the game.
"""
import argparse, hashlib, json, os, shutil, subprocess
from pathlib import Path
from assemble import ROOT

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua-dll', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, help='Another src/ folder to run for comparison')
    args = parser.parse_args()
    private = ROOT / 'private/tests'; private.mkdir(parents=True, exist_ok=True)
    dll = private / 'game-lua51.dll'
    if args.lua_dll.resolve() != dll.resolve(): shutil.copy2(args.lua_dll, dll)
    host = private / 'wine_lua_host.exe'
    if not host.exists():
        subprocess.run(['winegcc', '-m64', '-O2', '-Wall', '-o', str(host), 'tests/wine_lua_host.c'], cwd=ROOT, check=True)
    env = dict(os.environ, WINEPREFIX=str(ROOT / 'private/wine-prefix'), WINEDEBUG='-all', WINEDLLOVERRIDES='mscoree,mshtml=')
    runs = []
    for label, folder in [('current', 'src')] + ([('baseline', str(args.baseline))] if args.baseline else []):
        for mode in ('none', 'loader', 'hostile'):
            result = subprocess.run([str(host), 'Z:' + str(dll).replace('/', '\\'), 'tests/test_ffi_names.lua', folder, mode],
                                    cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
            stderr = '\n'.join(l for l in result.stderr.splitlines() if 'MESA' not in l and 'pci id' not in l)
            runs.append(dict(build=label, mode=mode, exit_code=result.returncode, stdout=result.stdout, stderr=stderr))
            print(('PASS' if result.returncode == 0 else 'FAIL'), label, mode, stderr.strip()[-160:])
    report = dict(lua_dll_sha256=hashlib.sha256(dll.read_bytes()).hexdigest(), runs=runs,
                  passed=all(r['exit_code'] == 0 for r in runs if r['build'] == 'current'),
                  scope='real kernel32/user32 on own memory in the game Lua DLL; no game process')
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence/wine-checks.json').write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__':
    main()
