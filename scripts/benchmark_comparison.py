"""Compare release 1.12, 1.12-lean.1 and this build in one C/Wine fixture.

CPU timing is unmetered; reads are counted in a separate pass. Includes fixture
work, not live FPS or isolated C4 time. 300 initial warmup updates, 600 untimed
counted updates (default), 300 additional unmetered warmup updates, then timing.
Only synthetic data is read; native game actions are mocked.
"""
import argparse, hashlib, json, os, shutil, statistics, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT.parent.parent

def run(command, **kw):
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=120,**kw)
    if result.returncode:
        print(result.stdout+result.stderr,flush=True)
        result.check_returncode()
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--memory',choices=['c','wine'],default='c')
    p.add_argument('--lua-dll',type=Path)
    p.add_argument('--frames',type=int,default=600)
    p.add_argument('--repeats',type=int,default=3)
    p.add_argument('--cases',nargs='+',default=['no_mission','other_weapon','c4_idle','c4_volatile','crowded_bindings','menu','release_aim','tank_passenger'])
    args=p.parse_args();assert args.frames>=100 and args.repeats>=1
    bench=ROOT/'private/bench';bench.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    if args.memory=='c':
        run(['gcc','-O2','-shared','-fPIC','-Wall','-Wextra','tests/bench_memory.c','-o','private/tests/bench_memory.so'])
        launcher=['luajit'];runtime={'luajit':run(['luajit','-v']).stdout.strip()}
    else:
        assert args.lua_dll and args.lua_dll.is_file()
        dll=ROOT/'private/tests/game-lua51.dll'
        if args.lua_dll.resolve()!=dll.resolve():shutil.copy2(args.lua_dll,dll)
        run(['winegcc','-m64','-O2','-Wall','-Wextra','-o','private/tests/wine_lua_host.exe','tests/wine_lua_host.c'])
        launcher=['private/tests/wine_lua_host.exe','Z:'+str(dll).replace('/','\\')]
        env.update(WINEPREFIX=str(ROOT/'private/wine-prefix'),WINEDEBUG='-all')
        runtime={'lua_dll_sha256':hashlib.sha256(dll.read_bytes()).hexdigest(),
            'wine':run(['wine','--version']).stdout.strip()}
    inputs={}
    for label,base in [('release_1_12',PROJECT/'optimization/1.12'),
                       ('lean_1',PROJECT/'optimization/1.12-lean.1'),('candidate',ROOT)]:
        source=base/'private/build/c4_quick_actions.off.lua'
        text=source.read_text();needle='local api=PassengerWindows(FireGateWindows(WindowsRead()))'
        assert text.count(needle)==1
        path=bench/(label+'-comparison.lua')
        path.write_text(text.replace(needle,needle+'\n_G.C4BenchmarkApi=api'))
        inputs[label]={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'entry':str(path),'catalog':str(base/'private/build/c4_catalog.lua')}
    results=[]
    for case in args.cases:
        for repeat in range(args.repeats):
            orders=[['release_1_12','lean_1','candidate'],
                    ['candidate','lean_1','release_1_12'],
                    ['lean_1','release_1_12','candidate']]
            labels=orders[repeat%len(orders)]
            for label in labels:
                data=inputs[label]
                command=launcher+['tests/benchmark_isolated.lua',data['entry'],data['catalog'],
                    str(args.frames),args.memory,'on','reload',case]
                proc=run(command,env=env)
                row=json.loads(next(s[7:] for s in proc.stdout.splitlines() if s.startswith('RESULT ')))
                assert 'RESULT ' in proc.stdout
                row.update(variant=label,repeat=repeat,scenario=case);results.append(row)
                print(json.dumps(row),flush=True)
    medians={}
    for case in args.cases:
        by={label:{field:statistics.median(r[field] for r in results
            if r['variant']==label and r['scenario']==case)
            for field in ('ms_per_update','reads_per_update','bytes_per_update')} for label in inputs}
        by['change_percent']={field:(by['candidate'][field]/by['release_1_12'][field]-1)*100
            for field in by['candidate']}
        by['change_vs_lean_1_percent']={field:(by['candidate'][field]/by['lean_1'][field]-1)*100
            for field in by['candidate']}
        medians[case]=by
    report={'inputs':inputs,'runtime':runtime,'results':results,'medians':medians,
        'scope':__doc__,'live_verified':False}
    output=ROOT/'evidence'/('comparison-'+args.memory+'.json')
    output.write_text(json.dumps(report,indent=2)+'\n');print(output)

if __name__=='__main__':main()
