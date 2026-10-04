"""Count exclusive read calls by Lua call path in synthetic, private fixtures."""
import argparse, json, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
INJECT=r'''
local profile={path='',counts={},enabled=false};_G.C4ReadProfile=profile
local function pack(...)return {n=select('#',...),...}end
local function profwrap(target,name,label)
    local original=target[name]
    if not original then return end
    target[name]=function(...)
        local previous=profile.path;profile.path=previous..'/'..label
        local result=pack(pcall(original,...));profile.path=previous
        if not result[1]then error(result[2],0)end
        return unpack(result,2,result.n)
    end
end
local function instance(module,constructor,label,names)
    local new=module[constructor]
    module[constructor]=function(...)
        local object=new(...)
        for _,name in ipairs(names)do profwrap(object,name,label..'.'..name)end
        return object
    end
end
for _,name in ipairs({'snapshot','avatar_snapshot','selected_snapshot'})do
    profwrap(ContextReader,name,'ContextReader.'..name)
end
profwrap(ActionReader,'snapshot','ActionReader.snapshot')
profwrap(ActionReader,'input_snapshot','ActionReader.input_snapshot')
if RoutingReader then profwrap(RoutingReader,'snapshot','RoutingReader.snapshot')end
profwrap(AimInputState,'read','AimInputState.read')
profwrap(ContactReader,'selected','ContactReader.selected')
profwrap(ContactReader,'tracked','ContactReader.tracked')
instance(NativeResolver,'resolve','NativeResolver',{'verify','verify_input_mapping'})
instance(ActionBackend,'new','ActionBackend',{'snapshot','input_snapshot','routing_snapshot','maintain','verify'})
instance(WeaponFireGate,'new','WeaponFireGate',{'sync'})
instance(AimInputGate,'new','AimInputGate',{'sync'})
instance(ModeLabels,'new','ModeLabels',{'sync'})
instance(ContactController,'new','ContactController',{'step'})
instance(AutoReload,'new','AutoReload',{'step','suspend'})
instance(ActionController,'new','ActionController',{'step'})
'''
API=r'''
local rawread=api.read
api.read=function(at,n)
    if profile.enabled then
        local key=profile.path
        local counts=profile.counts[key]
        if not counts then counts={0,0};profile.counts[key]=counts end
        counts[1]=counts[1]+1;counts[2]=counts[2]+n
    end
    return rawread(at,n)
end
'''
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base',type=Path,default=ROOT)
    p.add_argument('--label',default='candidate')
    p.add_argument('--pages',action='store_true',
        help='Page-granular fixture memory: guards on one page share one read, as in a real process')
    args=p.parse_args();base=args.base.resolve()
    text=(base/'private/build/c4_quick_actions.off.lua').read_text()
    needle="local existing = rawget(_G, 'HD2C4BoundaryProbe')"
    assert text.count(needle)==1
    text=text.replace(needle,INJECT+'\n'+needle)
    needle='local api=PassengerWindows(FireGateWindows(WindowsRead()))'
    assert text.count(needle)==1
    text=text.replace(needle,needle+'\n'+API)
    target=ROOT/'private/bench'/('reads-'+args.label+'.lua')
    target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text)
    result=subprocess.run(['luajit','tests/profile_reads.lua',str(target),
        str(base/'private/build/c4_catalog.lua'),'120','pages' if args.pages else 'sparse'],
        cwd=ROOT,text=True,capture_output=True)
    if result.returncode: raise RuntimeError(result.stdout+result.stderr)
    print(result.stdout)
    (ROOT/'evidence'/('read-profile-'+args.label+'.txt')).write_text(result.stdout)
if __name__=='__main__':main()
