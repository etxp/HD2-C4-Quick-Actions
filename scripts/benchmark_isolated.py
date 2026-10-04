"""Reproduce synthetic A/B/candidate tests; never attaches to a game process."""
import argparse, hashlib, json, os, shutil, statistics, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT.parent.parent

def run(command, **kw):
    return subprocess.run(command,cwd=ROOT,check=True,capture_output=True,text=True,timeout=90,**kw)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--memory',choices=['c','wine'],default='c')
    p.add_argument('--lua-dll',type=Path)
    p.add_argument('--repeats',type=int,default=3)
    p.add_argument('--frames',type=int,default=1000)
    args=p.parse_args()
    assert args.repeats>0 and args.frames>=100
    bench=ROOT/'private/bench';bench.mkdir(exist_ok=True,parents=True)
    env=os.environ.copy()
    if args.memory=='c':
        run(['gcc','-O2','-shared','-fPIC','-Wall','-Wextra','tests/bench_memory.c','-o','private/tests/bench_memory.so'])
        launcher=['luajit'];runtime=dict(version=run(['luajit','-v']).stdout.strip())
    else:
        assert args.lua_dll and args.lua_dll.is_file(),'Supply a locally available Lua DLL; it stays private.'
        dst=ROOT/'private/tests/game-lua51.dll';shutil.copy2(args.lua_dll,dst)
        run(['winegcc','-m64','-O2','-Wall','-o','private/tests/wine_lua_host.exe','tests/wine_lua_host.c'])
        launcher=['private/tests/wine_lua_host.exe','Z:'+str(dst).replace('/','\\')]
        env.update(WINEPREFIX=str(ROOT/'private/wine-prefix'),WINEDEBUG='-all')
        runtime=dict(lua_dll_sha256=hashlib.sha256(dst.read_bytes()).hexdigest(),wine=run(['wine','--version']).stdout.strip())
    inputs={}
    bases={'A':PROJECT,'B':PROJECT/'optimization/1.1-opt.2','Candidate':ROOT}
    for name,base in bases.items():
        entry=base/'private/build'/('c4_quick_actions.lua' if name=='A' else 'c4_quick_actions.summary.lua')
        body=entry.read_text();needle='local api=PassengerWindows(FireGateWindows(WindowsRead()))'
        assert body.count(needle)==1
        target=bench/(name+'-repro.lua');target.write_text(body.replace(needle,needle+'\n_G.C4BenchmarkApi=api'))
        inputs[name]=dict(entry_sha256=hashlib.sha256(entry.read_bytes()).hexdigest(),
            entry=str(target),catalog=str(base/'private/build/c4_catalog.lua'))
    results=[]
    for repeat in range(args.repeats):
        for name in (['A','B','Candidate'] if repeat%2==0 else ['Candidate','B','A']):
            data=inputs[name]
            command=launcher+['tests/benchmark_isolated.lua',data['entry'],data['catalog'],str(args.frames),args.memory,'on','reload']
            proc=run(command,env=env)
            row=json.loads(next(s[7:] for s in proc.stdout.splitlines() if s.startswith('RESULT ')))
            row.update(variant=name,repeat=repeat);results.append(row);print(json.dumps(row),flush=True)
    medians={name:statistics.median(r['ms_per_update'] for r in results if r['variant']==name) for name in bases}
    report=dict(inputs=inputs,runtime=runtime,results=results,median_ms=medians,
        candidate_change_vs_A_percent=(medians['Candidate']/medians['A']-1)*100,
        scope='os.clock reported synthetic whole-update time, including fixture work; not rendered FPS or live C4 callback time. Real game native calls remain mocks. The live opt.2 regression has NOT been reproduced by this harness.')
    (ROOT/'evidence'/('isolated-final-'+args.memory+'.json')).write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
