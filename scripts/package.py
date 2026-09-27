"""Build one HD2MM/Arsenal V1 ZIP from the verified source."""
import hashlib
import argparse
import gzip
import json
import subprocess
import sys
import tempfile
import zipfile
import struct
from pathlib import Path
from assemble import ROOT, VERSION, assemble

GUID = 'b0aa8e22-956d-4c7d-973c-937085f9c0d8'

class Deflate12:
    """Standard ZIP DEFLATE via libdeflate; payload bytes remain unchanged."""
    def __init__(self): self.data = bytearray()
    def compress(self, data):
        self.data.extend(data)
        return b''
    def flush(self):
        packed = subprocess.run(['libdeflate-gzip', '-12', '-c'], input=bytes(self.data),
                                capture_output=True, check=True, timeout=30).stdout
        # stdin mode must emit a fixed gzip header without names/extra fields.
        assert packed[:4] == b'\x1f\x8b\x08\x00' and len(packed) >= 18
        assert gzip.decompress(packed) == self.data, 'Compression changed payload'
        return packed[10:-8]  # raw DEFLATE; ZipFile supplies ZIP CRC and sizes

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader', type=Path, required=True,
                        help='External BingusSharedLoader checkout; see dependencies.lock.json')
    args = parser.parse_args()
    helper = args.loader.resolve()
    lock = json.loads((ROOT / 'dependencies.lock.json').read_text())['loader']
    for name, digest in lock['files'].items():
        assert hashlib.sha256((helper/name).read_bytes()).hexdigest() == digest, 'Unverified helper: '+name
    entry = assemble()
    report = json.loads((ROOT / 'evidence/checks.json').read_text())
    assert report['passed'] and report['entry_sha256'] == hashlib.sha256(entry.read_bytes()).hexdigest(), 'Run scripts/check.py on this source first'
    catalog=(ROOT/'private/build/c4_catalog.lua').read_bytes()
    assert report['catalog_sha256']==hashlib.sha256(catalog).hexdigest(), 'Unchecked catalog resource'
    for filename, digest in report['files'].items():
        assert hashlib.sha256((ROOT / filename).read_bytes()).hexdigest() == digest, 'Checked input changed: ' + filename
    manifest = {
        'Version': 1, 'Guid': GUID, 'Name': 'HD2 C4 Quick Actions ' + VERSION,
        'Description': 'C4 throw and detonate actions with customizable mouse and controller bindings, Manual/Contact detonation modes, passenger throwing and automatic reload. Requires Mod Bindings Menu v2 and Bingus Shared Loader v17+.',
        'IconPath': None,
        'Options': [{'Name': 'Installation / 安裝', 'Description': 'Install the MBM control version / 安裝 MBM 操作版本',
                     'SubOptions': [{'Name': 'C4 Quick Actions — MBM controls', 'Description': 'Set Throw C4 and Detonate C4 on the MODS tab. No fixed mouse/controller mapping.', 'Image': None, 'Include': ['Core']}]}]
    }
    with tempfile.TemporaryDirectory(dir=ROOT / 'private', prefix='package-') as temp:
        built = Path(temp) / 'addon.zip'
        subprocess.run([sys.executable, str(helper / 'scripts/build_addon.py'),
            '--name', 'mods/etxp/c4_boundary_probe', '--entry', str(entry), '--guid', GUID,
            '--display-name', manifest['Name'], '--output', str(built)], check=True)
        entries = {'manifest.json': (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode(),
                   'README.txt': (ROOT / 'docs/INSTALL.txt').read_bytes(),
                   'LICENSE.txt': (ROOT / 'LICENSE').read_bytes()}
        with zipfile.ZipFile(built) as z:
            for name in z.namelist():
                if name.startswith('Addon/'):
                    entries['Core/' + Path(name).name] = z.read(name)
    # The loader explicitly supports require() of separate archived resources.
    # Only the main script has a discovery declaration; dependency order is
    # explicit. Each ZIP entry stays small enough for the checked Arsenal worker.
    sys.path.insert(0,str(helper/'scripts'))
    from archive import make_archive,resource_hash,ARCHIVE
    assert ARCHIVE.endswith('.patch_0')
    support=ARCHIVE[:-1]+'1'
    entries['Core/'+support]=make_archive({resource_hash('mods/etxp/c4_quick_actions_catalog'):
        struct.pack('<II',len(catalog),2)+catalog})
    entries['Core/'+support+'.stream']=b''
    entries['Core/'+support+'.gpu_resources']=b''
    target = ROOT / 'dist' / ('HD2-C4-Quick-Actions-' + VERSION + '.zip')
    target.parent.mkdir(parents=True, exist_ok=True)
    # Use stronger standard DEFLATE and verify the original Arsenal worker.
    # CPython's write handle owns CRC/sizes; only its compressor is replaced.
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            with z.open(info, 'w') as handle:
                assert hasattr(handle, '_compressor'), 'Unsupported Python ZIP writer'
                handle._compressor = Deflate12()
                handle.write(data)
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        assert {name:z.read(name) for name in z.namelist()} == entries
    (ROOT / 'evidence/package.json').write_text(json.dumps(dict(
        version=VERSION, package=str(target.relative_to(ROOT)), sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
        manifest=manifest, payloads={name:hashlib.sha256(data).hexdigest() for name,data in entries.items() if name.startswith('Core/')},
        live_gameplay_verified=False), indent=2, ensure_ascii=False) + '\n')
    print(target)

if __name__ == '__main__': main()
