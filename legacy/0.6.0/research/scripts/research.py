#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Read-only local resource experiment. Outputs stay in this project.

Run with the existing helldivers-mod venv; that project's verified SDK reader
is reused without changing its database or any game file.
"""
import hashlib
import json
import re
import sqlite3
import struct
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ.get('C4_RESEARCH_WORKSPACE',str(Path(__file__).resolve().parents[2])))
TOOLS = Path(os.environ.get('C4_RESEARCH_TOOLS','<local-home>/helldivers-mod'))
INSPECTOR = Path(os.environ.get('C4_RESEARCH_INSPECTOR','<local-home>/hd2-spawn-inspector'))
STEAM = Path(os.environ.get('C4_RESEARCH_STEAM','<local-home>/.local/share/Steam'))
GAME = STEAM / 'steamapps/common/Helldivers 2'
RAW_COMMIT = '23f3258faa63a8cc3037c3d7198de7ea75f2abde'
sys.path.insert(0, str(TOOLS / 'src'))
from scan import Source  # noqa: E402; read-only methods only


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_info(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=sha(path.read_bytes()))


def save(name, data):
    (ROOT / 'evidence' / name).write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def hash64(name):
    data = name.encode()
    mask, mix = (1 << 64) - 1, 0xC6A4A7935BD1E995
    h = len(data) * mix & mask
    end = len(data) // 8 * 8
    for (k,) in struct.iter_unpack('<Q', data[:end]):
        k = k * mix & mask
        k ^= k >> 47
        h = ((h ^ (k * mix & mask)) * mix) & mask
    if data[end:]:
        h = (h ^ int.from_bytes(data[end:], 'little')) * mix & mask
    h ^= h >> 47
    h = h * mix & mask
    return h ^ (h >> 47)


def main():
    source = Source()
    stamp = datetime.now(timezone.utc).isoformat()
    database = TOOLS / 'reports/resources.sqlite'
    db = sqlite3.connect(f'file:{database}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    inputs = [ROOT / 'PRD.md', database, TOOLS / 'src/scan.py',
              TOOLS / 'src/sdk_adapter.py', TOOLS / 'tools.lock.json',
              GAME / 'bin/helldivers2.exe', GAME / 'bin/lua51.dll',
              GAME / 'data/game/game.dll', GAME / 'data/bundles.nxa',
              GAME / 'data/bundle_database.data',
              INSPECTOR / 'evidence/live-m0/api_catalog.json']
    names_path = TOOLS / 'tools/filediver/hashes/hashes.txt'
    inputs.append(names_path)
    names = {str(hash64(n)): n for n in names_path.read_text().splitlines()
             if re.search(r'c4_charge|firemode_.*c4|backpack_c4', n)}
    expected = {
        'content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge': 11201896471107657063,
        'content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_detonator': 5905641205788913469,
        'content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_backpack': 3033447149328295793,
    }
    for n, h in expected.items():
        assert hash64(n) == h, (n, hash64(n), h)
    rows = [dict(r) for r in db.execute(
        'SELECT * FROM resources WHERE resource_id IN (' + ','.join('?' for _ in names) +
        ') ORDER BY source_archive,resource_id,resource_type', list(names))]
    archives = {}
    for archive in sorted({r['source_archive'] for r in rows} | {'9ba626afa44a3aa3'}):
        old = db.execute('SELECT * FROM archives WHERE name=?', (archive,)).fetchone()
        toc = source.sdk.slim.get_package_toc(archive)
        actual = sha(toc)
        assert old and old['build_id'] == source.build, 'Index build differs'
        assert actual == old['toc_sha256'], f'Archive index stale: {archive}'
        archives[archive] = dict(toc_sha256=actual, index_verified=True)
    out = ROOT / 'experiments/extracted'
    out.mkdir(exist_ok=True)
    payloads = {}
    for r in rows:
        r['resource_path'] = names[r['resource_id']]
        r['resource_hex'] = f"{int(r['resource_id']):016x}"
        if r['resource_type'] in ('unit', 'state_machine', 'animation', 'bones', 'physics', 'material'):
            data = source.part(r['source_archive'], r['toc_offset'], r['toc_size'])
            name = f"{r['source_archive']}_{r['resource_hex']}.{r['resource_type']}"
            (out / name).write_bytes(data)
            r['payload_sha256'] = sha(data)
            r['local_payload'] = str((out / name).relative_to(ROOT))
            r['extracted_parts'] = ['toc']
            payloads[name] = data
    # Raw byte occurrences are leads, not decoded dependency edges.
    refs = []
    for name, data in payloads.items():
        for rid, path in names.items():
            needle = struct.pack('<Q', int(rid))
            offsets = [m.start() for m in re.finditer(re.escape(needle), data)]
            if offsets:
                refs.append(dict(source=name, target_path=path, target_id=rid,
                                 byte_offsets=offsets, status='raw_u64_match_only'))
    lua = []
    for r in db.execute("SELECT * FROM resources WHERE resource_type='lua' AND source_archive='9ba626afa44a3aa3'"):
        data = source.part(r['source_archive'], r['toc_offset'], r['toc_size'])
        strings = [m.group().decode('ascii') for m in re.finditer(rb'[\x20-\x7e]{4,}', data)]
        lua.append(dict(resource_id=r['resource_id'], sha256=sha(data),
                        strings=strings, status='bytecode_strings_not_execution'))
    catalog = json.loads((INSPECTOR / 'evidence/live-m0/api_catalog.json').read_text())
    selected = [r for r in catalog if re.search(
        r'\.(Mouse|Keyboard|Input)\.|\.(Player|Weapon)|deploy|detonat|fire|aim|action', r['path'], re.I)]
    save('local-resources.json', dict(observed_at=stamp, build=source.build,
         archive_verification=archives, candidates=rows, raw_reference_candidates=refs,
         limits=['Resource name is not a callable action.',
                 'TOC validated against current game; render GPU/stream payloads not extracted.',
                 'Raw reference matches need schema decoding.',
                 'No game state was changed.']))
    save('vanilla-lua-strings.json', lua)
    save('historical-api-analysis.json', dict(source=file_info(inputs[-2]),
         evidence_kind='historical_local_live_catalog', total_entries=len(catalog),
         scope='stingray tables, two levels; not all globals or native code',
         selected=selected, current_probe_verified=False,
         direct_action_status='unknown; no named Deploy/Detonate entry in selected catalog'))
    commits = {}
    for name, path in [('loader', INSPECTOR / 'references/BingusSharedLoader-v15'),
                       ('sdk', TOOLS / 'tools/HD2SDK-CommunityEdition'),
                       ('filediver', TOOLS / 'tools/filediver')]:
        commits[name] = subprocess.check_output(
            ['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    save('environment.json', dict(observed_at=stamp, build=source.build,
         inputs=[file_info(p) for p in inputs], source_commits=commits,
         game_patches=[file_info(p) for p in sorted((GAME / 'data').glob('*.patch_*'))],
         game_running='not established: sandbox process visibility may be incomplete',
         deployment_performed=False))
    folders = {'Hash.csv': 'Data', 'FireMode.txt': 'Data/enums',
               'FireTemplate.txt': 'Data/enums', 'WeaponFunctionType.txt': 'Data/enums'}
    downloaded = []
    for p in sorted((ROOT / 'references').iterdir()):
        if p.suffix not in ('.txt', '.json', '.csv'):
            continue
        folder = folders.get(p.name, 'Data/settings' if p.name.startswith('generated_') else 'Data/entities')
        downloaded.append(dict(**file_info(p), url=f'https://raw.githubusercontent.com/Darctor/Helldivers2_RawData/{RAW_COMMIT}/{folder}/{p.name}',
                               evidence_kind='third_party_dump_not_current_runtime'))
    save('reference-downloads.json', dict(retrieved_at=stamp, commit=RAW_COMMIT, files=downloaded))
    print(json.dumps(dict(build=source.build, candidates=len(rows),
                         extracted=len(payloads), raw_references=len(refs),
                         historical_api_entries=len(catalog))))


if __name__ == '__main__':
    main()
