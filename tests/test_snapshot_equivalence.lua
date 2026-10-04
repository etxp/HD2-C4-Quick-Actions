-- The retained snapshot must always equal what a new walk of current memory
-- returns: same row, same capability fields, same error. Random single-byte
-- changes, restorations and unreadable bytes; synthetic memory only.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local base=dofile('private/tests/modules/context_reader.lua')(R,D)
local action=dofile('private/tests/modules/action_reader.lua')(R,D)
local routing=dofile('private/tests/modules/routing_reader.lua')(R,D)
local Cache=dofile('src/SnapshotCache.lua')
local Memo=dofile('src/ReadMemo.lua')
local fixture=dofile('tests/action_fixture.lua')
local function check(name,fn)fn();print('PASS '..name)end
local state=7
local function rnd(n)state=(state*69069+12345)%2147483648;return math.floor(state/1024)%n end
local ignored={}
local function equal(a,b,path)
    if type(a)~=type(b)then return false,path end
    if type(a)=='function'then return true end
    if type(a)~='table'then
        if a~=b then return false,path..'='..tostring(a)..' / '..tostring(b)end
        return true
    end
    for k,v in pairs(a)do
        if not ignored[k]then
            local ok,where=equal(v,b[k],path..'.'..tostring(k));if not ok then return false,where end
        end
    end
    for k in pairs(b)do if a[k]==nil and not ignored[k]then return false,path..'.'..tostring(k)..' missing'end end
    return true
end
local function message(e)return (tostring(e):gsub('^.-:%d+: ',''))end
local function session(paged,read_snapshot,label)
    local s=fixture('rounds')
    if paged then s.fill=function(at)return s.pages[math.floor(at/4096)]and '\0' or nil end end
    Memo(s.api)
    -- Addresses the walk depends on, plus everything else the fixture owns.
    local touched,seen={},{}
    local read=s.api.read
    s.api.read=function(at,n)
        for i=at,at+n-1 do if not seen[i]then seen[i]=true;touched[#touched+1]=i end end
        return read(at,n)
    end
    read_snapshot(s.api,s.game,base);s.api.read=read
    local every={};for at in pairs(s.memory)do every[#every+1]=at end;table.sort(every)
    local cache=Cache.new(function()return read_snapshot(s.api,s.game,base)end)
    local changed,stats={},{steps=0,hits=0,walks=0,errors=0,rejected=0,valid=0}
    local walks=0
    local counted=Cache.new(function()walks=walks+1;return read_snapshot(s.api,s.game,base)end)
    for step=1,3000 do
        -- Mostly return to a valid context, so both valid and broken states recur.
        if rnd(10)<6 then
            for at,old in pairs(changed)do s.memory[at]=old==false and nil or old end
            changed={}
        end
        if rnd(10)<8 then
            local at=rnd(10)<8 and touched[rnd(#touched)+1] or every[rnd(#every)+1]
            if changed[at]==nil then changed[at]=s.memory[at] or false end
            if rnd(12)==0 then s.memory[at]=nil else s.memory[at]=string.char(rnd(256)) end
        end
        local before=walks
        s.api.memo_begin();counted.begin_phase()
        local ok,row,why,cap=pcall(counted.snapshot)
        local again_ok,again=pcall(counted.snapshot)
        counted.end_phase();s.api.memo_end()
        local fresh_ok,fresh_row,fresh_why,fresh_cap=pcall(read_snapshot,s.api,s.game,base)
        assert(ok==fresh_ok,label..' step '..step..': error presence differs: '..tostring(row)..' / '..tostring(fresh_row))
        if ok then
            local same,where=equal({row=row,why=why,cap=cap},{row=fresh_row,why=fresh_why,cap=fresh_cap},'')
            assert(same,label..' step '..step..': retained snapshot differs at '..tostring(where))
            -- A walk that met an unreadable address is not retained; a second
            -- use then walks again and must still describe the same memory.
            assert(again_ok and (again==row or equal(again,fresh_row,'')),'second use in the phase differs')
            if cap then stats.valid=stats.valid+1
            elseif row and row.action_context_status=='rejected' then stats.rejected=stats.rejected+1 end
        else
            assert(message(row)==message(fresh_row),label..' step '..step..': '..message(row)..' / '..message(fresh_row))
            stats.errors=stats.errors+1
        end
        stats.steps=stats.steps+1
        if walks==before then stats.hits=stats.hits+1 else stats.walks=stats.walks+1 end
    end
    assert(stats.hits>100 and stats.walks>100 and stats.valid>100 and stats.errors+stats.rejected>100,
        label..': the session did not exercise both reuse and replacement')
    print(string.format('MEASURE %s steps=%d reused=%d rewalked=%d valid=%d rejected=%d errors=%d',
        label,stats.steps,stats.hits,stats.walks,stats.valid,stats.rejected,stats.errors))
end
for _,paged in ipairs({false,true})do
    local memory=paged and 'page-granular' or 'sparse'
    check('retained complete action snapshot equals a new walk ('..memory..')',function()
        session(paged,action.snapshot,'action/'..memory)
    end)
    check('retained routing observation equals a new walk ('..memory..')',function()
        session(paged,routing.snapshot,'routing/'..memory)
    end)
end
check('a walk served by stale phase spans is repeated from memory, never reported',function()
    local s=fixture('rounds');s.fill=function(at)return s.pages[math.floor(at/4096)]and '\0' or nil end
    Memo(s.api);s.api.memo_begin()
    local row,_,cap=action.snapshot(s.api,s.game,base);assert(cap and row.current_fire_mode=='DEPLOY')
    -- Another thread changes the selector while this phase still holds spans.
    s.u32(0x4b000000+16,0x100)
    local hits=s.api.memo_hits()
    local again,why,next_cap=action.snapshot(s.api,s.game,base)
    assert(again and next_cap,tostring(why))
    assert(again.current_fire_mode=='DETONATE','stale phase span decided the new walk')
    s.api.memo_end()
end)
check('a walk that met an unreadable address is never retained',function()
    local s=fixture('rounds');Memo(s.api)
    local walks=0
    local cache=Cache.new(function()walks=walks+1;return action.snapshot(s.api,s.game,base)end)
    s.intercept=function(at,n)if at==s.rounds_state and n==24 then return nil,true end end
    s.api.memo_begin();cache.begin_phase()
    local row,_,cap=cache.snapshot();assert(row and not cap and row.action_context_status=='rejected')
    cache.end_phase();s.api.memo_end()
    -- No guarded byte changed, yet the address is readable again.
    s.intercept=nil
    s.api.memo_begin();cache.begin_phase()
    row,_,cap=cache.snapshot();assert(cap and walks==2,'unreadable observation was reused')
    cache.end_phase();s.api.memo_end()
end)
