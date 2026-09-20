#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Build a single-resource research addon, without installation."""
import hashlib
import argparse
import json
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(os.environ.get('C4_RESEARCH_WORKSPACE',str(Path(__file__).resolve().parents[2])))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--phase',choices=['exp01','exp02','exp03','exp04','exp05','exp06'],default='exp01')
    args=parser.parse_args()
    context=args.phase=='exp02'
    action=args.phase=='exp03'
    automatic=args.phase=='exp06'
    gamepad=args.phase=='exp05'
    mouse=args.phase in ('exp04','exp05')
    lock = json.loads((ROOT/'dependencies.lock.json').read_text())
    loader = Path(lock['loader']['path'])
    for name, expected in lock['loader']['files'].items():
        assert sha((loader/name).read_bytes()) == expected, 'helper source changed: '+name
    source = ROOT/('src/c4_dual_input_auto.lua' if automatic else 'src/c4_dual_input_gamepad.lua' if gamepad else 'src/c4_dual_input.lua' if mouse else 'src/c4_action_prototype.lua' if action else 'src/c4_context_probe.lua' if context else 'src/c4_probe.lua')
    tests = json.loads((ROOT/('evidence/automatic-offline-tests.json' if automatic else 'evidence/gamepad-offline-tests.json' if gamepad else 'evidence/mouse-offline-tests.json' if mouse else 'evidence/action-offline-tests.json' if action else 'evidence/context-offline-tests.json' if context else 'evidence/offline-tests.json')).read_text())
    assert tests['exit_code'] == 0 and tests['source_sha256'] == sha(source.read_bytes()), 'run current probe checks first'
    if automatic:
        for name,expected in tests['files'].items():
            assert sha((ROOT/name).read_bytes())==expected, 'tested input changed: '+name
    target = ROOT/('dist/C4-Dual-Input-EXP06-Auto.zip' if automatic else 'dist/C4-Dual-Input-EXP05-Gamepad.zip' if gamepad else 'dist/C4-Dual-Input-EXP04.zip' if mouse else 'dist/C4-Action-Prototype-EXP03.2.zip' if action else 'dist/C4-Context-Probe-EXP02.zip' if context else 'dist/C4-Boundary-Probe-EXP01.zip')
    subprocess.run([sys.executable, '-B', str(loader/'scripts/build_addon.py'),
                    '--name', lock['addon']['resource'], '--entry', str(source),
                    '--guid', lock['addon']['guid'], '--display-name',
                    'C4 Dual Input EXP06 (Automatic Mouse / Gamepad)' if automatic else 'C4 Dual Input EXP05 (Mouse / Xbox / PlayStation)' if gamepad else 'C4 Dual Input EXP04 (RMB Deploy / LMB Detonate)' if mouse else 'C4 Action Prototype EXP03.2 (Pending Refill Fix)' if action else 'C4 Context Probe EXP02 (Read Only)' if context else 'C4 Boundary Probe EXP01 (Observation Only)',
                    '--output', str(target)], check=True)
    with zipfile.ZipFile(target) as package:
        content = {n: package.read(n) for n in package.namelist()}
    manifest = json.loads(content['manifest.json'])
    description = ('Read-only C4 research probe. F6: capture on/off; F7: marker. '
                   'Does not deploy or detonate C4. Requires Bingus Shared Loader v15+ / API 1.')
    if context:
        description += ' EXP02 observes local weapon and mode candidates; build 24826606 only. Replaces EXP01.'
    if action:
        description = ('EXPERIMENTAL C4 native action test. F6: arm/disarm; F8: Deploy; F9: Detonate; '
                       'F7: visual marker. Build 24826606 only. No mouse remap. Single-player tests first. '
                       'EXP03.2: keep one queued Deploy through native chamber refill within its original deadline. '
                       'Requires Bingus Shared Loader v15+ / API 1. Replaces earlier C4 prototypes.')
    if mouse:
        description = ('EXPERIMENTAL C4 dual mouse input. F6: enable/disable; RMB: Deploy; LMB: Detonate; '
                       'F7: marker. Build 24826606 only. Local equipped C4 gate prevents vanilla Fire dispatch; '
                       'native Aim unchanged. Release both buttons before enabling. No firing mode writes. '
                       'Requires Bingus Shared Loader v15+ / API 1. Replaces earlier C4 prototypes.')
    if gamepad:
        description = ('EXPERIMENTAL C4 mouse and engine gamepad input. RMB / LT / L2: Deploy; '
                       'LMB / RT / R2: Detonate. F6 enable/disable; F7 marker. Build 24826606. '
                       'Xbox and PlayStation button profiles, analog edge filtering, bounded rotating logs. '
                       'Native Aim unchanged. Gamepad hardware validation pending. '
                       'Requires Bingus Shared Loader v15+ / API 1. Replaces earlier C4 prototypes.')
    if automatic:
        description = ('EXPERIMENTAL automatic C4 mouse/gamepad input. RMB / LT / L2: Deploy; '
                       'LMB / RT / R2: Detonate. No F6 activation; F7 marker. Build 24826606. '
                       'Reload/focus/cursor guards pause and resume after release. Native Aim unchanged. '
                       'Automatic UI guards pending live validation. Requires Bingus Shared Loader v15+ / API 1. '
                       'Replaces earlier C4 prototypes.')
    manifest['Description'] = description
    manifest['Options'][0]['Description'] = description
    content['manifest.json'] = (json.dumps(manifest, indent=2)+'\n').encode()
    content['README.txt'] = (ROOT/('docs/AUTOMATIC_README.txt' if automatic else 'docs/GAMEPAD_README.txt' if gamepad else 'docs/DUAL_INPUT_README.txt' if mouse else 'docs/ACTION_PROTOTYPE_README.txt' if action else 'docs/CONTEXT_PROBE_README.txt' if context else 'docs/PROBE_README.txt')).read_bytes()
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(content.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            package.writestr(info, data)
    # Parse the result independently from the helper's reader.
    archive_name = 'Addon/9ba626afa44a3aa3.patch_0'
    data = content[archive_name]
    magic, kinds, count = struct.unpack_from('<III', data)
    assert (magic, kinds, count) == (0xF0000011, 1, 1)
    entry = struct.unpack_from('<7Q6I', data, 104)
    resource, kind, offset = entry[:3]
    size = entry[7]
    assert kind == 0xA14E8DFA2CD117E2
    assert resource == 0x7AF491CCD120B4EA, 'must contain only our named addon resource'
    length, version = struct.unpack_from('<II', data, offset)
    body = data[offset+8:offset+size]
    assert version == 2 and length == len(body) and body == source.read_bytes()
    assert body.startswith(('-- HD2-Addon: '+lock['addon']['resource']+'\n').encode())
    assert content[archive_name+'.stream'] == b'' and content[archive_name+'.gpu_resources'] == b''
    assert manifest['Guid'] == lock['addon']['guid']
    report = dict(package=str(target.relative_to(ROOT)), sha256=sha(target.read_bytes()),
                  bytes=target.stat().st_size, entries={n:sha(v) for n,v in content.items()},
                  lua_resource_hex=f'{resource:016x}', resources=1, plaintext_matches_source=True,
                  wwise_or_boot_override=False, loader_included=False,
                  installed=False, tested_in_game=False,
                  tests_source_sha256=tests['source_sha256'])
    (ROOT/('evidence/automatic-package.json' if automatic else 'evidence/gamepad-package.json' if gamepad else 'evidence/mouse-package.json' if mouse else 'evidence/action-package.json' if action else 'evidence/context-package.json' if context else 'evidence/package.json')).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
