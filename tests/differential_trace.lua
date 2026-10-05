-- Deterministic scripted session for comparing two assembled runtimes.
-- Prints every native call, data write and input-gate state per update.
-- Synthetic memory and mocked native functions only; no game process.
-- usage: luajit tests/differential_trace.lua ENTRY CATALOG SEED TICKS [pages]
local entry,catalog=assert(arg[1]),assert(arg[2])
local seed,ticks=assert(tonumber(arg[3])),assert(tonumber(arg[4]))
_G.C4FixturePages=arg[5]=='pages'
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local scenario=dofile('tests/gamepad_entry_fixture.lua')
local ffi=require('ffi')
local state=seed%2147483648
-- Exact in a double: 2^31*69069 < 2^53.
local function rnd(n) state=(state*69069+12345)%2147483648;return math.floor(state/1024)%n end
local function chance(percent) return rnd(1000)<percent*10 end

local values={deploy=false,detonate=false}
local menu={api=1,version=2,ready=function()return true end,
    register_binding=function()return true end,
    is_down=function(id)return values[id:match('%.([^%.]+)$')] end}
-- Odd seeds: a Mod Bindings Menu v2.2 table, with revision and poll. Builds
-- that do not know poll still read is_down, which gives the same answers.
if seed%2==1 then
    menu.version=3;menu.revision=1
    function menu.poll(ids,out)
        if type(ids)~='table' or type(out)~='table' then return false,'invalid poll arguments' end
        out.down=out.down or {}
        for i,id in ipairs(ids)do out.down[i]=values[id:match('%.([^%.]+)$')] end
        return true
    end
end
_G.ModBindingsMenu=menu
local real_print=print
print=function()end -- the entry banner names its own version
local s=scenario{entry=entry,window=true,native_ui=true,aim_profile=true,pad_profile='xbox',
    before_load=function()
        package.preload['mods/etxp/c4_quick_actions_catalog']=function()return dofile(catalog)end
    end}
dofile('tests/reload_fixture.lua')(s,seed%5==1 and 'supply' or nil)
local seated=seed%3==0
if seated then
    local config,seat=1+seed%45,2+seed%2
    local manager=s.allocate();s.ptr(s.game+R.global_vehicle,manager)
    s.map(manager+0x20,s.allocate(),{{s.aid,1}})
    local registry=s.allocate();s.ptr(manager+0x38,registry);s.ptr(registry+8,s.eaddr)
    local states=s.allocate();s.ptr(manager+0x48,states);local row=states+64;s.zero(row,64)
    s.u32(row+0x18,0xffffffff);s.u32(row+0x20,0xffffffff)
    s.seat_row=row
    local id=s.otherid+100;s.u32(row,id);s.u32(row+4,config);s.u32(row+8,3);s.u32(row+0x1c,seat)
    s.map(s.owner+D.entity_id_map,0x42000000,{{s.wid,5},{s.otherid,6},{s.aid,3},{id,7}})
    local entity=s.owner+D.entity_array+7*24;s.zero(entity,24);s.put(entity,'VEHICLE!');s.u32(entity+8,id)
    s.lean_calls=0
    function s.leaned(value,transition)
        s.put(row+0x30,transition and '\1' or '\0');s.put(row+0x31,value and '\1' or '\0')
    end
    s.native.lean=function(m,a)
        assert(m==manager and a==s.aid);s.lean_calls=s.lean_calls+1;s.leaned(true,true)
    end
end
local function pose(flags)
    s.zero(s.avatar_flags,24);s.u32(s.avatar_flags,2)
    if seated then flags[#flags+1]=D.seated end
    for _,flag in ipairs(flags) do
        local address=s.avatar_flags+math.floor(flag/32)*4
        local raw=s.api.read(address,4);local a,b,c,d=raw:byte(1,4)
        local old=a+b*256+c*65536+d*16777216;local bit=2^(flag%32)
        if math.floor(old/bit)%2==0 then s.u32(address,old+bit) end
    end
end
pose{}
local queries={mapping=0,eligible=0}
for name,key in pairs({input_mapping='mapping',reload_eligible='eligible'}) do
    local call=s.native[name]
    s.native[name]=function(...) queries[key]=queries[key]+1;return call(...) end
end
local poses={function()pose{}end,function()pose{D.prone}end,function()pose{D.diving}end,
    function()pose{D.airborne}end,function()pose{D.diving,D.airborne}end,
    function()pose{D.tactical_map}end,function()pose{D.weapon_menu}end,
    function()s.zero(s.avatar_flags,24)end,function()pose{D.blocked[1]}end}
local ui_open,api_present,posed=false,true,false
local events
events={
    -- Short presses, occasional holds across several updates.
    {14,function()values.deploy=true end},
    {45,function()values.deploy=false end},
    {9,function()values.detonate=true end},
    {45,function()values.detonate=false end},
    {2,function()s.u32(s.state+0x1c,({1,2})[rnd(2)+1])end},
    {12,function()s.u32(s.state+0x1c,3)end},
    {2,function()ui_open=true;s.ui(11)end},
    {30,function()if ui_open then ui_open=false;s.ui() end end},
    {4,function()posed=true;poses[rnd(#poses)+1]()end},
    {25,function()if posed then posed=false;pose{} end end},
    {10,function()s.complete()end},
    {6,function()s.phase(rnd(90))end},
    -- Resupply, an empty chamber, and a chamber the engine has not refilled.
    {5,function()s.u32(s.spare_state,rnd(4))end},
    {8,function()s.u32(s.rounds_state+0x10,55);s.put(s.rounds_runtime+0x10,'\0')end},
    {2,function()s.u32(s.rounds_state+0x10,0)end},
    {1,function()s.put(s.rounds_runtime+0x10,'\1')end},
    {1,function()s.focused=false end},
    {30,function()s.focused=true end},
    {1,function()s.engine_focus=false end},
    {30,function()s.engine_focus=true end},
    {1,function()s.cursor_visible=true end},
    {30,function()s.cursor_visible=false end},
    {1,function()api_present=false;_G.ModBindingsMenu=nil end},
    {30,function()api_present=true;_G.ModBindingsMenu=menu end},
    {2,function()s.mouse[0]={down=true,pressed=true,released=false}end},
    {30,function()s.mouse[0]={down=false,pressed=false,released=true}end},
    {2,function()s.mouse[1]={down=true,pressed=true,released=false}end},
    {20,function()s.mouse[1]={down=false,pressed=false,released=true}end},
    {3,function()s.avatar_action(rnd(2)==0 and s.reload_id or 77,true,rnd(100)/10)end},
    {20,function()s.avatar_action(0,false,0)end},
    {1,function()s.reload_allowed=false end},
    {20,function()s.reload_allowed=true end},
    {1,function()s.mapping('deploy',({0,1,7})[rnd(3)+1],rnd(2))end},
    {1,function()s.mapping('detonate',rnd(2),rnd(2))end},
    {6,function()if seated then s.leaned(rnd(4)~=0,rnd(5)==0) end end},
    {3,function()
        local index=rnd(#events-1)+1
        s.original_hook=function()s.original_hook=nil;events[index][2]()end
    end},
}
for _=1,8 do s.tick() end
local seen={calls=0,writes=0,passenger=0,vanilla=0}
local function fresh(list,key)
    local out={}
    for i=seen[key]+1,#list do
        local item=list[i];local parts={}
        if item.address then parts={string.format('%x',item.address),item.byte:byte()}
        else for j=1,#item do parts[j]=tostring(item[j]) end end
        if type(item)=='string' then parts={item} end
        out[#out+1]=table.concat(parts,'/')
    end
    seen[key]=#list
    return table.concat(out,';')
end
local lines={}
for tick=1,ticks do
    for _,event in ipairs(events) do if chance(event[1]) then event[2]() end end
    s.tick()
    lines[#lines+1]=table.concat({tick,
        'calls='..fresh(s.calls,'calls'),'writes='..fresh(s.writes,'writes'),
        'seat='..fresh(s.passenger_writes,'passenger'),'vanilla='..fresh(s.vanilla,'vanilla'),
        'flags='..string.format('%x',s.flags()),'aim='..s.mask_mode(),'fire='..s.fire_mask_mode(),
        'inhibit='..s.inhibit_calls..'/'..s.unblock_calls..'/'..s.fire_inhibit_calls..'/'..s.fire_unblock_calls,
        'reload='..s.reload_calls..'/'..queries.eligible,'mapping='..queries.mapping,
        'lean='..tostring(s.lean_calls),'sprint='..s.sprint_breaks..'/'..s.aim_ticks,
        'disabled='..tostring(s.module.disabled),
        s.module.disabled and tostring(s.module.status):gsub('^.-:%d+: ','') or ''},' ')
end
_G.ModBindingsMenu=menu
local closed=_G.shutdown()
lines[#lines+1]='shutdown='..tostring(closed)..' flags='..string.format('%x',s.flags())..
    ' aim='..s.mask_mode()..' fire='..s.fire_mask_mode()..' seat='..fresh(s.passenger_writes,'passenger')
print=real_print
io.write(table.concat(lines,'\n'),'\n')
