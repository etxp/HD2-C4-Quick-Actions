local scenario=dofile('tests/gamepad_entry_fixture.lua')
GuardSpans=dofile('src/GuardSpans.lua')
local resolver=dofile('src/NativeResolver.lua')
local cat=dofile('private/build/native_catalog.lua')
local symbols=dofile('private/tests/mock_symbols.lua')
local function check(name,fn)fn();print('PASS '..name)end
local f=assert(io.open('private/tests/mock-native.bin','rb'));local image=f:read('*a');f:close()
local game=0x700000000000
local reads,bytes=0,0
local altered=false
local api={read=function(at,n)
    reads=reads+1;bytes=bytes+n
    local rva=at-game
    local out=image:sub(rva+1,rva+n)
    if altered and rva==symbols.fn_start then out='\0'..out:sub(2)end
    return out
end}
check('shared initialization buffer saves reads without changing resolved symbols',function()
    local one=resolver.resolve(api,game,cat);local standalone=bytes
    reads,bytes=0,0
    local scan=resolver.new_scan(api,game)
    local a=resolver.resolve(api,game,cat,scan)
    local b=resolver.resolve(api,game,cat,scan)
    for k,v in pairs(one.symbols)do assert(a.symbols[k]==v and b.symbols[k]==v)end
    assert(scan.read_bytes==one.scan_bytes and scan.shared_bytes==one.scan_bytes)
    assert(bytes==2*standalone-one.scan_bytes)
    scan.release();assert(scan.released)
    a.verify();b.verify()
    assert(not pcall(resolver.resolve,api,game,cat,scan))
end)
check('shared scan refuses changed live instructions and another module identity',function()
    local scan=resolver.new_scan(api,game)
    resolver.resolve(api,game,cat,scan)
    altered=true
    local ok,why=pcall(resolver.resolve,api,game,cat,scan)
    assert(not ok and tostring(why):find('compat_signature_changed_during_scan',1,true))
    altered=false
    assert(not pcall(resolver.resolve,{read=api.read},game,cat,scan))
    scan.release()
end)

local measurements={}
for _,mode in ipairs({'off','summary','verbose'})do
    check(mode..' diagnostics preserves repeated actions, interface guards and shutdown',function()
        local input={deploy=false,detonate=false}
        _G.ModBindingsMenu={api=1,version=2,ready=function()return true end,
            register_binding=function()return true end,
            is_down=function(id)return input[id:match('%.([^%.]+)$')]end}
        local s=scenario{entry='private/build/c4_quick_actions.'..mode..'.lua',window=true,native_ui=true}
        for _=1,8 do s.tick()end
        assert(not s.module.disabled,s.module.status)
        local function press(action)
            input[action]=true;s.tick();input[action]=false;s.tick()
        end
        for _=1,3 do
            local before=#s.calls
            press('deploy');assert(#s.calls==before+4,s.module.status)
            s.finish();press('detonate');assert(#s.calls==before+5,s.module.status);s.finish()
        end
        s.ui(11);local before=#s.calls
        press('deploy');press('detonate');assert(#s.calls==before)
        s.ui();for _=1,8 do s.tick()end
        press('deploy');assert(#s.calls==before+4)
        s.finish()
        s.tick(31) -- summary timer is elapsed time, not one record per frame
        assert(not s.module.disabled,s.module.status)
        assert(_G.shutdown()=='shutdown-original')
        local total=0;for _,line in ipairs(s.lines)do total=total+#line end
        measurements[mode]={bytes=total,records=#s.lines}
        if mode=='off' then assert(total==0 and next(s.log_files)==nil)
        elseif mode=='summary' then
            local log=table.concat(s.lines)
            assert(log:find('"record_type":"summary"',1,true))
            assert(log:find('"action_started":',1,true))
            assert(not log:find('"record_type":"input"',1,true))
            assert(#s.lines<20)
        end
    end)
end
assert(measurements.summary.bytes<measurements.verbose.bytes/10)
print(string.format('MEASURE diagnostics bytes: off=%d summary=%d verbose=%d; summary records=%d verbose records=%d',
    measurements.off.bytes,measurements.summary.bytes,measurements.verbose.bytes,
    measurements.summary.records,measurements.verbose.records))

check('fixed ring slots stay bounded over repeated sessions',function()
    local ring=dofile('src/RollingLog.lua')
    local files={}
    local function open(name)
        files[name]=''
        return {write=function(_,line)files[name]=files[name]..line;return true end,
            flush=function()return true end,close=function()return true end}
    end
    for session=1,10 do
        local writer=ring.new(open,function(row)return row.session_id end,'C4QuickActions_summary',
            function()return {}end,{slots=4,max_bytes=1024,session_id=tostring(session)})
        for _=1,100 do writer:write(string.rep('x',400))end
        writer:close()
    end
    local count,total=0,0
    for _,data in pairs(files)do count=count+1;total=total+#data;assert(#data<=1024)end
    assert(count==4 and total<=4096)
end)
