#!/usr/bin/env python3
"""Build the current public mod with a separately supplied, pinned loader helper."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def sha(data):return hashlib.sha256(data).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader',type=Path,required=True,help='BingusSharedLoader checkout; see dependencies.lock.json')
    args=parser.parse_args()
    project=json.loads((ROOT/'project.json').read_text())
    lock=json.loads((ROOT/'dependencies.lock.json').read_text())
    tests=json.loads((ROOT/'evidence/automatic-offline-tests.json').read_text())
    assert tests['exit_code']==0,'run scripts/check_automatic.py first'
    for name,expected in tests['files'].items():
        assert sha((ROOT/name).read_bytes())==expected,'tested input changed: '+name
    source=ROOT/project['source'];source_bytes=source.read_bytes()
    assert sha(source_bytes)==tests['source_sha256']==project['tested_source_sha256'],'review source hash and rerun tests'
    helper=args.loader.resolve()
    for name,expected in lock['loader']['files'].items():
        assert sha((helper/name).read_bytes())==expected,'loader helper differs from pinned version: '+name
    target=ROOT/project['package'];target.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='c4-quick-actions-') as temporary:
        intermediate=Path(temporary)/'addon.zip'
        subprocess.run([sys.executable,'-B',str(helper/'scripts/build_addon.py'),
            '--name',lock['addon']['resource'],'--entry',str(source),
            '--guid',lock['addon']['guid'],'--display-name',project['name']+' v'+project['version'],
            '--output',str(intermediate)],check=True,capture_output=True,text=True)
        with zipfile.ZipFile(intermediate) as z:content={n:z.read(n) for n in z.namelist()}
    manifest=json.loads(content['manifest.json'])
    assert manifest['Guid']==lock['addon']['guid'] and len(manifest['Options'])==1
    manifest['Description']=project['description']
    manifest['Options'][0]['Description']=project['description']
    content['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    content['README.txt']=(ROOT/'docs/INSTALL.txt').read_bytes()
    content['LICENSE.txt']=(ROOT/'LICENSE').read_bytes()
    archive_name='Addon/9ba626afa44a3aa3.patch_0';archive=content[archive_name]
    assert struct.unpack_from('<III',archive)==(0xF0000011,1,1)
    entry=struct.unpack_from('<7Q6I',archive,104)
    resource,kind,offset=entry[:3];size=entry[7]
    assert resource==0x7AF491CCD120B4EA and kind==0xA14E8DFA2CD117E2
    length,version=struct.unpack_from('<II',archive,offset)
    body=archive[offset+8:offset+size]
    assert version==2 and length==len(body) and body==source_bytes
    assert content[archive_name+'.stream']==content[archive_name+'.gpu_resources']==b''
    with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(content.items()):
            info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
            z.writestr(info,data)
    with zipfile.ZipFile(target) as z:assert z.testzip() is None
    report=dict(project=project['name'],version=project['version'],package=project['package'],
        sha256=sha(target.read_bytes()),bytes=target.stat().st_size,
        entries={name:sha(data) for name,data in content.items()},source_sha256=sha(source_bytes),
        plaintext_matches_tested_source=True,native_behavior_changes=False,
        resources=1,loader_included=False,installed=False,game_executed_by_build=False)
    (ROOT/'evidence/public-package.json').write_text(json.dumps(report,indent=2)+'\n')
    (target.parent/'SHA256SUMS.txt').write_text(report['sha256']+'  '+target.name+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
