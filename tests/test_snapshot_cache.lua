-- A retained observation is reused only after all of its guards compare equal.
local Cache=dofile('src/SnapshotCache.lua')
local function check(name,fn)fn();print('PASS '..name)end
local function fixture()
    local s={value=1,walks=0,checks=0}
    s.cache=Cache.new(function()
        s.walks=s.walks+1
        if s.failure then error('read_failed')end
        if s.missing then return nil,'missing'end
        local captured=s.value
        local function same(shared)
            s.checks=s.checks+1;s.shared=shared
            if s.unreadable then error('read_unavailable')end
            return s.value==captured
        end
        return {value=captured},nil,not s.no_cap and {same=function()return same()end} or nil,
            not s.unguarded and same or nil
    end)
    return s
end
check('uses in one phase share one observation without further reads',function()
    local s=fixture();s.cache.begin_phase()
    for _=1,100 do assert(s.cache.snapshot().value==1)end
    assert(s.walks==1 and s.checks==0)
end)
check('the next phase rereads every guard once and never repeats an unchanged walk',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot();s.cache.end_phase()
    for phase=1,50 do
        s.cache.begin_phase()
        for _=1,5 do assert(s.cache.snapshot().value==1)end
        s.cache.end_phase()
        assert(s.walks==1 and s.checks==phase and s.shared==true)
    end
end)
check('a changed guard discards the entry and walks again in the same call',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot();s.cache.end_phase()
    s.value=2;s.cache.begin_phase()
    assert(s.cache.snapshot().value==2 and s.walks==2 and s.checks==1)
    assert(s.cache.snapshot().value==2 and s.walks==2 and s.checks==1)
end)
check('an unreadable guard only retires the entry; the new walk decides',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot();s.cache.end_phase()
    s.unreadable=true;s.cache.begin_phase()
    assert(s.cache.snapshot().value==1 and s.walks==2)
    s.cache.end_phase();s.cache.begin_phase();s.failure=true
    assert(not pcall(s.cache.snapshot),'walk failure must still propagate')
end)
check('an observation without a guard checker is shared inside its phase and never beyond',function()
    local s=fixture();s.unguarded=true;s.cache.begin_phase()
    local first=s.cache.snapshot();assert(s.cache.snapshot()==first and s.walks==1)
    -- A mutation or a new phase cannot prove it current again: walk.
    s.cache.invalidate();s.cache.snapshot();assert(s.walks==2 and s.checks==0)
    s.cache.end_phase();s.cache.begin_phase();s.cache.snapshot();assert(s.walks==3 and s.checks==0)
    s.cache.prime();s.cache.snapshot();assert(s.walks==3)
    s.cache.end_phase();s.cache.begin_phase();s.cache.prime();s.cache.snapshot();assert(s.walks==4)
end)
check('absent and throwing observations are never retained',function()
    local s=fixture();s.cache.begin_phase();s.missing=true
    local a,b=s.cache.snapshot();assert(a==nil and b=='missing')
    s.missing=false;s.failure=true;assert(not pcall(s.cache.snapshot))
    s.failure=false;assert(s.cache.snapshot().value==1 and s.walks==3)
end)
check('ordinary-weapon rows without a capability are retained and revalidated',function()
    local s=fixture();s.no_cap=true;s.cache.begin_phase()
    local row,_,cap=s.cache.snapshot();assert(row and not cap)
    s.cache.end_phase();s.cache.begin_phase()
    row,_,cap=s.cache.snapshot();assert(row and not cap and s.walks==1 and s.checks==1)
end)
check('nothing is reused outside a phase',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot();s.cache.end_phase()
    s.cache.snapshot();s.cache.snapshot();assert(s.walks==3 and s.checks==0)
end)
check('explicit invalidation rereads the guards before the next use in the phase',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot()
    s.cache.invalidate();assert(s.cache.snapshot().value==1 and s.walks==1 and s.checks==1)
    s.value=2;s.cache.invalidate();assert(s.cache.snapshot().value==2 and s.walks==2)
end)
check('wrapped native mutators invalidate before reentrant reads and preserve returns',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot()
    local native={change=function(v)
        s.value=v;assert(s.cache.snapshot().value==v);return 1,nil,3
    end}
    s.cache.wrap(native,{'change'})
    local a,b,c=native.change(2);assert(a==1 and b==nil and c==3 and s.walks==2)
end)
check('a failing native call still invalidates the retained observation',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot()
    local native={change=function()s.value=2;error('native_error')end}
    s.cache.wrap(native,{'change'});assert(not pcall(native.change))
    assert(s.cache.snapshot().value==2 and s.walks==2)
end)
check('a phase change during a walk cannot store that walk',function()
    local c,walks;walks=0
    c=Cache.new(function()
        walks=walks+1;if walks==1 then c.end_phase();c.begin_phase()end
        return {},nil,{},function()return true end
    end)
    c.begin_phase();c.snapshot();c.snapshot();assert(walks==2)
end)
check('a phase change during revalidation cannot approve the old entry',function()
    local c,walks,checks;walks,checks=0,0
    c=Cache.new(function()
        walks=walks+1
        return {walk=walks},nil,{},function()
            checks=checks+1;if checks==1 then c.end_phase();c.begin_phase()end
            return true
        end
    end)
    c.begin_phase();c.snapshot();c.end_phase();c.begin_phase()
    assert(c.snapshot().walk==2,'entry approved across a reentrant phase change')
end)
check('priming revalidates early and drops a changed entry without walking',function()
    local s=fixture();s.cache.begin_phase();s.cache.snapshot();s.cache.end_phase()
    s.cache.begin_phase();s.cache.prime();assert(s.checks==1 and s.walks==1)
    s.cache.snapshot();assert(s.checks==1 and s.walks==1)
    s.cache.end_phase();s.value=2;s.cache.begin_phase();s.cache.prime()
    assert(s.checks==2 and s.walks==1);assert(s.cache.snapshot().value==2 and s.walks==2)
end)
