"""Observe retained Lua heap in synthetic gameplay states; not whole-game memory."""
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
entry=ROOT/'private/build/c4_quick_actions.off.lua'
command=['luajit','tests/benchmark_runtime.lua',str(entry),'5000','soak']
process=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,timeout=300)
(ROOT/'evidence/soak-output.txt').write_text(process.stdout+process.stderr)
assert process.returncode==0,process.stdout[-1000:]+process.stderr
samples={};results=[]
for line in process.stdout.splitlines():
    if line.startswith('RESULT '):results.append(json.loads(line[7:]))
    m=re.fullmatch(r'HEAP (\w+) frame=(\d+) retained_KiB=([0-9.]+)',line)
    if m:samples.setdefault(m[1],[]).append({'frame':int(m[2]),'KiB':float(m[3])})
summary={}
for name,rows in samples.items():
    stable=[r['KiB'] for r in rows if r['frame']>=1000]
    summary[name]={'first_post_warmup_KiB':stable[0],'last_KiB':stable[-1],
        'post_warmup_range_KiB':max(stable)-min(stable),
        'net_growth_KiB':stable[-1]-stable[0]}
report={'command':command,'entry_sha256':hashlib.sha256(entry.read_bytes()).hexdigest(),
    'samples':samples,'summary':summary,'results':results,'live_verified':False,
    'scope':__doc__+' Six states, 5000 updates each, current full reload fixture; '
        'explicit collection and fixture history clearing every500 updates. '
        'Includes shared VM, test fixture and JIT memory; does not prove no real-game leak.'}
(ROOT/'evidence/soak.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(summary,indent=2))
