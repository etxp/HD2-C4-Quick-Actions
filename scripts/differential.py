"""Compare this runtime with preserved builds on identical scripted sessions.

Every native call, data write, input-gate state and native query count must be
identical on every update. Synthetic memory and mocked native functions only.
"""
import argparse, hashlib, json, subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent.parent
BASELINES = {'1.12': PROJECT / 'optimization/1.12', '1.12-opt.2': PROJECT / 'optimization/1.12-opt.2',
             '1.13': PROJECT / 'releases/1.13'}

def trace(base, seed, ticks, memory):
    command = ['luajit', 'tests/differential_trace.lua',
               str(base / 'private/build/c4_quick_actions.off.lua'),
               str(base / 'private/build/c4_catalog.lua'), str(seed), str(ticks), memory]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
    if result.returncode:
        raise RuntimeError(f'{base.name} seed {seed}: {result.stdout[-2000:]}{result.stderr[-2000:]}')
    return result.stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeds', type=int, default=120)
    parser.add_argument('--ticks', type=int, default=600)
    args = parser.parse_args()
    jobs = [(seed, memory) for seed in range(1, args.seeds + 1) for memory in ('sparse', 'pages')]
    report = dict(seeds=args.seeds, ticks=args.ticks, sessions=len(jobs), baselines={}, activity={})
    def run(job):
        seed, memory = job
        mine = trace(ROOT, seed, args.ticks, memory)
        return seed, memory, mine, {name: trace(base, seed, args.ticks, 'sparse')
                                    for name, base in BASELINES.items()}
    with ThreadPoolExecutor(8) as pool:
        results = list(pool.map(run, jobs))
    totals = dict(start_calls=0, data_writes=0, reloads=0, disabled_sessions=0)
    for name in BASELINES:
        report['baselines'][name] = dict(identical=0, different=[])
    for seed, memory, mine, others in results:
        lines = mine.splitlines()
        totals['start_calls'] += sum(line.count('start/') for line in lines)
        totals['data_writes'] += sum(1 for line in lines if 'writes= ' not in line and 'writes=' in line)
        totals['reloads'] += int(lines[-2].split('reload=')[1].split('/')[0])
        totals['disabled_sessions'] += 'disabled=true' in lines[-2]
        for name, other in others.items():
            entry = report['baselines'][name]
            if other == mine:
                entry['identical'] += 1
                continue
            theirs = other.splitlines()
            at = next((i for i, (a, b) in enumerate(zip(lines, theirs)) if a != b), min(len(lines), len(theirs)))
            entry['different'].append(dict(seed=seed, memory=memory, first_difference_update=at + 1,
                this=lines[at] if at < len(lines) else None, baseline=theirs[at] if at < len(theirs) else None))
    report['activity'] = totals
    report['passed'] = all(not entry['different'] for entry in report['baselines'].values())
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence/differential.json').write_text(json.dumps(report, indent=2) + '\n')
    for name, entry in report['baselines'].items():
        print(f"{name}: {entry['identical']}/{len(jobs)} identical sessions")
        for item in entry['different'][:3]:
            print(json.dumps(item, indent=1))
    print('activity', totals)
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__':
    main()
