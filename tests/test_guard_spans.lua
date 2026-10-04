-- Page-coalesced guard comparison must accept and reject exactly what the
-- original one-read-per-guard comparison does. Synthetic memory only.
local Spans=dofile('src/GuardSpans.lua')
local Memo=dofile('src/ReadMemo.lua')
local function check(name,fn)fn();print('PASS '..name)end
-- sparse=true makes every unwritten byte unreadable, as the old fixtures do.
local function memory(sparse)
    local s={bytes={},pages={},reads=0,log={}}
    function s.put(at,text)
        for i=1,#text do s.bytes[at+i-1]=text:sub(i,i) end
        for page=math.floor(at/4096),math.floor((at+#text-1)/4096) do s.pages[page]=true end
    end
    s.api={read=function(at,n)
        s.reads=s.reads+1;s.log[#s.log+1]={at=at,n=n}
        assert(n>0 and n<=4096,'read_size_limit')
        local out={}
        for i=0,n-1 do
            local b=s.bytes[at+i]
            if not b then
                if sparse or not s.pages[math.floor((at+i)/4096)] then return nil end
                b='\0'
            end
            out[i+1]=b
        end
        return table.concat(out)
    end}
    function s.guard(at,n)
        local parts={}
        for offset=0,n-1,4096 do parts[#parts+1]=assert(s.api.read(at+offset,math.min(4096,n-offset))) end
        return {at=at,bytes=table.concat(parts)}
    end
    return s
end
local function original(api,guards)
    for _,g in ipairs(guards)do
        local b=api.read(g.at,#g.bytes)
        if not b then return nil end
        if b~=g.bytes then return false end
    end
    return true
end
local state=20261004
local function rnd(n)state=(state*69069+12345)%2147483648;return math.floor(state/1024)%n end

check('guards on one page share one read and every guarded byte is still compared',function()
    local s=memory();s.put(0x500000,string.rep('a',4096));s.put(0x900000,string.rep('b',64))
    local guards={s.guard(0x500010,8),s.guard(0x500100,24),s.guard(0x500ff0,16),s.guard(0x900000,64)}
    local plan=Spans.plan(guards);s.reads=0
    assert(Spans.same(s.api,plan,true,true) and s.reads==2)
    for _,g in ipairs(guards)do
        for i=0,#g.bytes-1 do
            local old=s.bytes[g.at+i];s.bytes[g.at+i]='!'
            assert(not Spans.same(s.api,plan,true,true),'guarded byte ignored')
            s.bytes[g.at+i]=old
        end
    end
    -- Bytes between guards belong to nobody: the engine may change them.
    s.bytes[0x500050]='!';s.bytes[0x500200]='!'
    s.reads=0;assert(Spans.same(s.api,plan,true,true) and s.reads==2)
end)
check('a guard crossing a page boundary is split and fully compared',function()
    local s=memory();s.put(0x600000-8192,string.rep('x',16384))
    local g=s.guard(0x600000-4096-10,4096+20)
    local plan=Spans.plan({g});assert(#plan==3)
    s.reads=0;assert(Spans.same(s.api,plan,true,true) and s.reads==3)
    for _,offset in ipairs({0,9,10,4105,4106,4115})do
        local at=g.at+offset;local old=s.bytes[at];s.bytes[at]='!'
        assert(not Spans.same(s.api,plan,true,true));s.bytes[at]=old
    end
    for _,c in ipairs(plan)do assert(c.stop-c.at<=4096) end
end)
check('an unreadable span falls back to the original individual reads and remembers',function()
    local s=memory(true);s.put(0x700010,'12345678');s.put(0x700800,'abcdefgh')
    local guards={s.guard(0x700010,8),s.guard(0x700800,8)}
    local plan=Spans.plan(guards);s.reads=0
    assert(Spans.same(s.api,plan,true,true) and s.reads==3)
    s.reads=0;assert(Spans.same(s.api,plan,true,true) and s.reads==2)
    s.bytes[0x700803]='!';assert(not Spans.same(s.api,plan,true,true))
end)
check('an unreadable guard raises when strict and is a plain mismatch otherwise',function()
    for _,sparse in ipairs({true,false})do
        local s=memory(sparse);s.put(0x710000,'12345678');s.put(0x710100,'abcdefgh')
        local guards={s.guard(0x710000,8),s.guard(0x710100,8)}
        local plan=Spans.plan(guards);assert(Spans.same(s.api,plan,true,true))
        for at=0x710000,0x710107 do s.bytes[at]=nil end;s.pages={}
        local ok,why=pcall(Spans.same,s.api,plan,true,true)
        assert(not ok and tostring(why)=='read_unavailable',tostring(why))
        assert(Spans.same(s.api,plan,true,false)==false)
    end
end)
check('coalesced comparison equals the per-guard comparison on random memory',function()
    for round=1,400 do
        local sparse=round%2==0
        local s=memory(sparse);local base=0x800000+rnd(4096)
        s.put(base,string.rep('\0',3*4096))
        for i=0,3*4096-1,7 do s.bytes[base+i]=string.char(rnd(256)) end
        if sparse then for _=1,40 do s.bytes[base+rnd(3*4096)]=nil end end
        local guards={}
        for _=1,1+rnd(24)do
            local at,n=base+rnd(3*4096-600),1+rnd(rnd(8)==0 and 600 or 40)
            local bytes=s.api.read(at,n)
            if bytes then guards[#guards+1]={at=at,bytes=bytes} end
        end
        local plan=Spans.plan(guards)
        for _=1,12 do
            local at=base+rnd(3*4096);local old=s.bytes[at]
            local kind=rnd(3)
            if kind==0 then s.bytes[at]=string.char(rnd(256))
            elseif kind==1 and sparse then s.bytes[at]=nil end
            local expected=original(s.api,guards)
            local ok,actual=pcall(Spans.same,s.api,plan,true,true)
            -- Exactly the original outcome: the first bad guard in walk order
            -- decides between raising (unreadable) and false (different).
            if expected==nil then assert(not ok and tostring(actual)=='read_unavailable','unreadable guard did not raise')
            else assert(ok and actual==expected,'coalesced result differs') end
            assert((Spans.same(s.api,plan,true,false)==true)==(expected==true))
            s.bytes[at]=old
        end
    end
end)
check('shared comparison reuses only spans read in this phase',function()
    local s=memory();s.put(0x900000,string.rep('m',4096));Memo(s.api)
    local wide={s.guard(0x900000,8),s.guard(0x900800,8)}
    local narrow={s.guard(0x900400,8)}
    local a,b=Spans.plan(wide),Spans.plan(narrow)
    -- Outside a phase nothing is remembered.
    s.reads=0;assert(Spans.same(s.api,a,false,true) and Spans.same(s.api,b,false,true) and s.reads==2)
    s.api.memo_begin();s.reads=0
    assert(Spans.same(s.api,a,false,true) and s.reads==1)
    assert(Spans.same(s.api,b,false,true) and s.reads==1,'covered span was read again')
    -- A boundary check never trusts the phase spans.
    s.bytes[0x900402]='!'
    assert(Spans.same(s.api,b,false,true),'phase observation is shared until invalidated')
    assert(not Spans.same(s.api,b,true,true))
    s.api.memo_reset();assert(not Spans.same(s.api,b,false,true))
    s.api.memo_end()
end)
check('after a difference the pass completes and leaves every span for the rebuild',function()
    local s=memory();Memo(s.api)
    for page=0,3 do s.put(0xa00000+page*4096,string.rep('p',4096)) end
    local guards={};for page=0,3 do guards[#guards+1]=s.guard(0xa00000+page*4096+16,8) end
    local plan=Spans.plan(guards);s.bytes[0xa00010]='!'
    s.api.memo_begin();s.reads=0
    assert(not Spans.same(s.api,plan,false,true) and s.reads==4)
    s.reads=0
    for page=0,3 do assert(s.api.peek(0xa00000+page*4096+16,8)) end
    assert(s.reads==0,'rebuild read spans the sweep already holds')
    s.api.memo_end()
end)
check('the earliest bad guard in walk order decides between false and raising',function()
    for _,sparse in ipairs({false,true})do
        -- Walk order: a guard on a high page first, then one on a low page.
        local s=memory(sparse);s.put(0xc02000,'later-pg');s.put(0xc00000,'first-pg')
        local late,early=s.guard(0xc02000,8),s.guard(0xc00000,8)
        local function unmap(at)for i=at,at+7 do s.bytes[i]=nil end;s.pages[math.floor(at/4096)]=nil end
        -- Different guard walked first, unreadable guard second: false, as before.
        local plan=Spans.plan({late,early})
        s.bytes[0xc02000]='!';unmap(0xc00000)
        local ok,result=pcall(Spans.same,s.api,plan,true,true)
        assert(ok and result==false,'a change walked first must not raise')
        -- Unreadable guard walked first: raises, as before.
        plan=Spans.plan({early,late})
        ok,result=pcall(Spans.same,s.api,plan,true,true)
        assert(not ok and tostring(result)=='read_unavailable')
        assert(Spans.same(s.api,plan,true,false)==false)
    end
end)
check('a checker follows a growing guard list',function()
    local s=memory();s.put(0xb00000,string.rep('q',256))
    local guards={s.guard(0xb00000,8)}
    local same=Spans.checker(s.api,guards,true);assert(same())
    guards[#guards+1]=s.guard(0xb00080,8);s.bytes[0xb00081]='!'
    assert(not same(),'later guard was not included')
end)
