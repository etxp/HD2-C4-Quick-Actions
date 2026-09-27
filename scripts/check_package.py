"""Portable package checks; does not install or invoke either mod manager."""
from pathlib import Path
import hashlib,json,sys,uuid,zipfile
import argparse
from assemble import ROOT,VERSION

def sha(b):return hashlib.sha256(b).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader',type=Path,required=True)
    args=parser.parse_args(); helper=args.loader.resolve()
    lock=json.loads((ROOT/'dependencies.lock.json').read_text())['loader']
    for name,digest in lock['files'].items():
        assert sha((helper/name).read_bytes())==digest,'Unverified helper: '+name
    package=json.loads((ROOT/'evidence/package.json').read_text()); artifact=ROOT/package['package']
    assert sha(artifact.read_bytes())==package['sha256']
    with zipfile.ZipFile(artifact) as z:
        assert z.testzip() is None
        sys.path.insert(0,str(ROOT/'tests'))
        from package_resources import check
        resources=check(ROOT,z,VERSION,helper)
        manifest=json.loads(z.read('manifest.json'))
        assert artifact.name=='HD2-C4-Quick-Actions-'+VERSION+'.zip'
        assert manifest['Name']=='HD2 C4 Quick Actions '+VERSION
        assert str(uuid.UUID(manifest['Guid']))=='b0aa8e22-956d-4c7d-973c-937085f9c0d8'
        assert ('Version '+VERSION+'\n') in z.read('README.txt').decode('utf-8')
        assert manifest['IconPath'] is None
        def options(items):
            for item in items:
                assert item['Description'].strip()
                if 'Include' in item:
                    assert item['Include'], 'Empty Include is forbidden'
                    for folder in item['Include']:
                        assert any(n.startswith(folder.rstrip('/')+'/') for n in z.namelist())
                if 'SubOptions' in item: options(item['SubOptions'])
        options(manifest['Options'])
        for p,h in package['payloads'].items():assert sha(z.read(p))==h
        assert set(z.namelist())=={'manifest.json','README.txt','LICENSE.txt',*package['payloads']}
    assert manifest['Version']==1 and manifest['Description'].strip()
    assert 'Include' not in manifest['Options'][0]
    assert manifest['Options'][0]['SubOptions'][0]['Include']==['Core']
    report=dict(passed=True,resources=resources,artifact_sha256=package['sha256'],
                manager_integration_retested=False,real_game_modified=False,live_gameplay_verified=False)
    (ROOT/'evidence/package-checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS V1 manifest rules, ZIP paths, payload hashes and both Lua resources')
    print('Manager integration is recorded separately in evidence/release-1.1.json')
if __name__=='__main__':main()
