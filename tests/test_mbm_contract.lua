-- Mod Bindings Menu contract, v2.1 and v2.2. The bindings layer must take the
-- same decisions whether the menu offers poll or only is_down, retry a refused
-- registration as each version asks, and read the assignments file in both
-- formats. Optional: pass the folder of Mod Bindings Menu v2.2's src/ to run
-- its real poll.lua against a simulated input owner.
local ffi=require('ffi')
local Bindings=dofile('src/MBMBindings.lua')
local Profile=dofile('src/MBMProfile.lua')
local MBM_SRC=arg[1]
local function check(name,fn)fn();print('PASS '..name)end
local DEPLOY,DETONATE='etxp.c4_quick_actions.deploy','etxp.c4_quick_actions.detonate'
local state=20261005
local function rnd(n)state=(state*69069+12345)%2147483648;return math.floor(state/1024)%n end

local function sample_key(r)
    return table.concat({tostring(r.available),tostring(r.released),tostring(r.deploy),tostring(r.detonate)},'/')
end
local function bindings_for(menu)
    local logs={}
    local b=Bindings.new(function()return menu end,function(kind,row)logs[#logs+1]=row;return true end)
    return b,logs
end

-- A scripted menu: values are set by the test; poll and revision optional.
local function scripted(options)
    local m={api=1,version=options.poll and 3 or 3,down={},registered={},refuse={},ready_value=true,
        calls={register=0,is_down=0,poll=0}}
    if options.revision then m.revision=0 end
    function m.register_binding(id,label,slot,opts)
        m.calls.register=m.calls.register+1
        assert(slot==0 and type(opts)=='table' and opts.category=='HD2 C4 Quick Actions')
        if m.refuse[id] then return false,m.refuse[id] end
        m.registered[id]=true
        if m.revision then m.revision=m.revision+1 end
        return true
    end
    function m.ready()return m.ready_value end
    function m.is_down(id)
        m.calls.is_down=m.calls.is_down+1
        if not m.registered[id] or not m.ready_value then return nil end
        return m.down[id]
    end
    if options.poll then
        function m.poll(ids,out)
            m.calls.poll=m.calls.poll+1
            if m.poll_error then error('poll_failed') end
            if m.poll_refuses then return false,'invalid poll arguments' end
            if type(ids)~='table' or type(out)~='table' then return false,'invalid poll arguments' end
            out.down=out.down or {}
            for i,id in ipairs(ids)do
                if not m.registered[id] or not m.ready_value then out.down[i]=nil else out.down[i]=m.down[id] end
            end
            return true
        end
    end
    return m
end

check('v2.2 menu: bindings are read through one poll per sample, never is_down',function()
    local m=scripted{poll=true,revision=true};local b=bindings_for(m)
    for i=1,50 do
        m.down[DEPLOY]=rnd(2)==1;m.down[DETONATE]=rnd(3)==0
        local r=b.sample(i*16)
        assert(r.available and r.deploy==m.down[DEPLOY] and r.detonate==m.down[DETONATE])
    end
    assert(m.calls.poll==50 and m.calls.is_down==0 and m.calls.register==2)
end)
check('poll and is_down menus produce identical samples over random states',function()
    local a,b=scripted{poll=true,revision=true},scripted{}
    local ba,bb=bindings_for(a),bindings_for(b)
    for step=1,20000 do
        local k=rnd(10)
        local values={deploy=({true,false,nil})[rnd(3)+1],detonate=({true,false,nil,'x'})[rnd(4)+1]}
        for _,m in ipairs({a,b})do
            m.down[DEPLOY],m.down[DETONATE]=values.deploy,values.detonate
            if k==0 then m.ready_value=not m.ready_value end
        end
        local ra,rb=ba.sample(step*16),bb.sample(step*16)
        assert(sample_key(ra)==sample_key(rb) and ba.status==bb.status and ba.reason==bb.reason,
            'step '..step..': '..sample_key(ra)..' / '..sample_key(rb)..' '..tostring(ba.reason)..' / '..tostring(bb.reason))
    end
end)
check('a poll that errors or refuses falls back to is_down for that sample',function()
    for _,mode in ipairs({'poll_error','poll_refuses'})do
        local m=scripted{poll=true,revision=true};local b=bindings_for(m)
        m.down[DEPLOY],m.down[DETONATE]=true,false;b.sample(0)
        m[mode]=true;local r=b.sample(16)
        assert(r.available and r.deploy==true and r.detonate==false and m.calls.is_down==2)
    end
end)
check('v2.2 refusal is retried only when the menu revision changes',function()
    local m=scripted{poll=true,revision=true};local b,logs=bindings_for(m)
    m.refuse[DETONATE]='all 29 automatic binding actions in use'
    local r=b.sample(0);assert(not r.available and b.reason=='all 29 automatic binding actions in use')
    local before=m.calls.register
    for i=1,600 do assert(not b.sample(i*16).available) end
    assert(m.calls.register==before,'refused registration was retried without a revision change')
    local emitted=#logs
    m.refuse[DETONATE]=nil;m.revision=m.revision+1
    r=b.sample(10000);assert(m.calls.register==before+1 and m.registered[DETONATE])
    m.down[DEPLOY],m.down[DETONATE]=false,false;r=b.sample(10016)
    assert(r.available and b.status=='ready' and #logs>emitted)
end)
check('v2.1 refusal (no revision) is retried once per second, as before',function()
    local m=scripted{};local b=bindings_for(m)
    m.refuse[DEPLOY]='slot already in use'
    b.sample(0);local n=m.calls.register
    b.sample(500);assert(m.calls.register==n)
    b.sample(1000);assert(m.calls.register==n+1)
    m.refuse[DEPLOY]=nil;b.sample(2000);assert(m.registered[DEPLOY] and m.registered[DETONATE])
end)
check('a replaced menu table registers again and forgets the old refusal',function()
    local m=scripted{poll=true,revision=true};local current=m
    local b=Bindings.new(function()return current end,function()return true end)
    m.refuse[DEPLOY]='invalid binding category';b.sample(0)
    local fresh=scripted{poll=true,revision=true};current=fresh
    fresh.down[DEPLOY],fresh.down[DETONATE]=false,false
    assert(b.sample(16).available and fresh.calls.register==2 and b.epoch==2)
end)
check('menus older than v2 stay unavailable',function()
    for _,m in ipairs({{api=1,version=1},{api=2,version=3},{api=1,version=3,register_binding=function()end}})do
        local b=bindings_for(m);assert(not b.sample(0).available and b.reason=='MBM v2 required')
    end
end)

-- The real poll.lua of Mod Bindings Menu v2.2 against a simulated input owner.
if MBM_SRC then
    pcall(ffi.cdef,'typedef unsigned char MBM_u8; typedef uint32_t MBM_u32;')
    local memory={}
    local function put32(at,v)for i=0,3 do memory[at+i]=math.floor(v/256^i)%256 end end
    local function put64(at,v)put32(at,v%4294967296);put32(at+4,math.floor(v/4294967296))end
    local BASE,OWNER_RVA,OWNER=0x140000000,0x2000,0x7000000
    local STATE_OFFSET,STRIDE=808,32
    local words=ffi.new('MBM_u32[6]')
    local function read_words(at,n)
        for i=0,n-1 do if memory[at+i]==nil then return false end end
        ffi.fill(words,24)
        local b=ffi.cast('uint8_t *',words)
        for i=0,n-1 do b[i]=memory[at+i] end
        return true
    end
    local function read_into(at,buffer,n)
        for i=0,n-1 do if memory[at+i]==nil then return false end end
        for i=0,n-1 do buffer[i]=memory[at+i] end
        return true
    end
    local function word_pointer(i)
        local v=words[i]+words[i+1]*4294967296
        if v<0x10000 or v>=0x800000000000 then return nil end
        return v
    end
    local mstate={registry={},build_rows=true,swept_counts={},base=BASE}
    local counts,sweeps={},0
    local mbm={state=mstate,DORMANT_ACTIONS={{12,1},{12,0},{10,1},{10,4},{10,8},{10,14},{10,9},{10,0},{10,2},
            {10,3},{10,5},{11,0},{11,3},{9,0},{9,11}},
        live_header=function(record)return 0x8000000+record.code,counts[record.code] end,
        active_screen=function()return nil end,
        sweep_bindings=function()sweeps=sweeps+1;for code,n in pairs(counts)do mstate.swept_counts[code]=n end end,
        read_words=read_words,read_into=read_into,word_pointer=word_pointer,words=words,
        INPUT_OWNER_PTR_RVA=OWNER_RVA,ACTION_STATE_OFFSET=STATE_OFFSET,ACTION_STATE_STRIDE=STRIDE}
    local f=assert(io.open(MBM_SRC..'/poll.lua'));local source=f:read('*a');f:close()
    assert(loadstring(source,'=poll.lua'))(mbm)
    -- is_down exactly as Mod Bindings Menu v2.2's api.is_down reads it.
    local function is_down(id)
        local record=mstate.registry[id]
        if not record or not mstate.build_rows then return nil end
        local bucket,count=mbm.live_header(record)
        if not bucket then return nil end
        if count~=mstate.swept_counts[record.code] and not mbm.active_screen() then mbm.sweep_bindings();return false end
        local owner=read_words(BASE+OWNER_RVA,8) and word_pointer(0)
        if not owner or not read_words(owner+STATE_OFFSET+STRIDE*(record.group*97+record.action),1) then return nil end
        return bit.band(words[0],0xff)~=0
    end
    local function register(id,group,action)
        local code=group*65536+action
        mstate.registry[id]={code=code,group=group,action=action}
        counts[code]=1;mstate.swept_counts[code]=1
    end
    local function set(id,down)
        local r=mstate.registry[id];memory[OWNER+STATE_OFFSET+STRIDE*(r.group*97+r.action)]=down and 1 or 0
    end
    -- The state stretch between the two actions exists in the owner.
    for i=0,STRIDE*20 do memory[OWNER+STATE_OFFSET+STRIDE*(10*97)+i]=0 end
    put64(BASE+OWNER_RVA,OWNER)
    check('real v2.2 poll accepts this addon\'s ids and table and equals is_down',function()
        register(DEPLOY,10,0);register(DETONATE,10,2)
        local polled,ids={},{DEPLOY,DETONATE}
        for step=1,5000 do
            local k=rnd(12)
            if k==0 then mstate.build_rows=not mstate.build_rows or nil
            elseif k==1 then counts[655360]=counts[655360]+1           -- the game restored defaults
            elseif k==2 then if memory[BASE+OWNER_RVA] then memory[BASE+OWNER_RVA]=nil else put64(BASE+OWNER_RVA,OWNER) end
            else set(DEPLOY,rnd(2)==1);set(DETONATE,rnd(3)==0) end
            -- Same memory, same moment: poll first, then is_down on a copy of the sweep state.
            local saved={};for c,n in pairs(mstate.swept_counts)do saved[c]=n end
            assert(mbm.poll(ids,polled)==true,'poll refused the arguments')
            local after={};for c,n in pairs(mstate.swept_counts)do after[c]=n end
            mstate.swept_counts=saved
            local a,b=is_down(DEPLOY),is_down(DETONATE)
            for c,n in pairs(after)do assert(mstate.swept_counts[c]==n) end
            assert(polled.down[1]==a and polled.down[2]==b,'step '..step..': poll '..tostring(polled.down[1])..','..
                tostring(polled.down[2])..' is_down '..tostring(a)..','..tostring(b))
        end
        assert(sweeps>0,'the sequence never exercised a sweep')
    end)
    check('the bindings layer runs on the real v2.2 poll',function()
        mstate.build_rows=true;put64(BASE+OWNER_RVA,OWNER);mstate.swept_counts[655360]=counts[655360]
        local menu={api=1,version=3,revision=1,poll=mbm.poll,is_down=function()error('is_down must not be used')end,
            ready=function()return mstate.build_rows~=nil end,register_binding=function()return true end}
        local b=bindings_for(menu)
        set(DEPLOY,true);set(DETONATE,false);local r=b.sample(0)
        assert(r.available and r.deploy==true and r.detonate==false and r.released==false)
        set(DEPLOY,false);r=b.sample(16);assert(r.available and r.released)
    end)
else
    print('SKIP real Mod Bindings Menu v2.2 poll.lua (pass its src folder as the first argument)')
end

-- The assignments file, in both formats, and its replacement through a
-- temporary file in v2.2.
local dir='private/tests/mbm-profile';os.execute('mkdir -p '..dir)
local path=dir..'/ModBindingsMenu.assignments'
local function write(text)
    if text==nil then os.remove(path);return end
    local f=assert(io.open(path,'wb'));f:write(text);f:close()
end
local V21='armored_overhaul.gunner_drive.back\t10\t6\n'..DEPLOY..'\t10\t0\n'..DETONATE..'\t10\t2\nother\t10\t3\n'
local V22='format 2\nsession 14\n'..DEPLOY..'\t10\t0\t14\n'..DETONATE..'\t10\t2\t14\nother.mod\t11\t4\t3\n'..
    'action 10:0 cleared 9 found 1a2b left 3c4d\naction 11:4 clear\nend\n'
check('assignments: v2.1 and v2.2 files give the same native actions',function()
    for _,text in ipairs({V21,V22,(V22:gsub('\n','\r\n'))})do
        local r=Profile.parse(text);assert(r.deploy==655360 and r.detonate==655362)
    end
end)
check('assignments: incomplete, duplicate, out-of-range and missing records are rejected',function()
    for _,text in ipairs({
        'format 2\nsession 14\n'..DEPLOY..'\t10\t0\t14\n'..DETONATE..'\t10\t2\t14\n',     -- no end
        V21..DEPLOY..'\t10\t5\n',                                                           -- duplicate
        DEPLOY..'\t13\t0\n'..DETONATE..'\t10\t2\n',                                          -- group
        DEPLOY..'\t10\t97\n'..DETONATE..'\t10\t2\n',                                         -- action
        DEPLOY..'\t10\t0\n'..DETONATE..'\t10\t0\n',                                          -- same action
        DEPLOY..'\t10\t0\n',                                                                 -- one missing
        'x'..DEPLOY..'\t10\t0\n'..DETONATE..'\t10\t2\n',                                     -- other id
        DEPLOY..'\t10\t0\textra\n'..DETONATE..'\t10\t2\n'})do                                -- malformed
        assert(not pcall(Profile.parse,text),text)
    end
end)
check('assignments: a missing or unusable file keeps the codes last read',function()
    local read=Profile.new({log_directory=dir})
    write(nil);assert(read(0)==nil,'no codes before any file')
    write(V21);local a=read(1000);assert(a and a.deploy==655360)
    write(nil);assert(read(2000)==a,'missing file dropped the codes')
    write('format 2\nsession 15\n');assert(read(3000)==a,'cut-short file dropped the codes')
    write(V22);local b=read(4000);assert(b.deploy==655360 and b.detonate==655362)
    write((V22:gsub('\t10\t2\t14','\t11\t1\t15')));local c=read(5000);assert(c.detonate==11*65536+1,'changed action not read')
    assert(read(5500)==c,'read more than once per second')
    write(nil)
end)
