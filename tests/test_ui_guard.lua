-- The retained UI stack image is trusted only while a new read of the
-- manager pointer and the stack is byte-identical to it.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local base=dofile('private/tests/modules/context_reader.lua')(R,D)
local f=assert(io.open('src/NativeUiGuard.lua'));local text=f:read('*a');f:close()
local Guard=assert(loadstring('local R,D,AvatarFlags=...\n'..text))(R,D,dofile('src/AvatarFlags.lua'))
local fixture=dofile('tests/context_fixture.lua')
local function check(name,fn)fn();print('PASS '..name)end
local function setup()
    local s=fixture();s.manager=0x55000000;s.ptr(s.game+R.global_ui,s.manager)
    s.stack=s.manager+D.ui_shift+0x84;s.zero(s.stack,0x90)
    s.observed=0
    s.guard=Guard.new(s.api,s.game,base,function()
        s.observed=s.observed+1
        return {tactical_map_active=s.map==true,weapon_menu_active=false}
    end)
    function s.count(fn)local before=s.read_calls;local result=fn();return result,s.read_calls-before end
    return s
end
check('an unchanged stack needs three reads and returns the same state',function()
    local s=setup()
    local first,reads=s.count(s.guard);assert(reads==4 and not first.native_ui_active)
    for _=1,20 do
        local row,n=s.count(s.guard)
        assert(n==3 and not row.native_ui_active and row.native_ui_stack_count==0)
    end
    -- Avatar flags are asked for on every call while no UI is active.
    assert(s.observed==21)
end)
check('every stack field change is seen on the next call',function()
    for _,field in ipairs({0,4,0x84,0x8c})do
        local s=setup();s.guard();s.guard()
        s.u32(s.stack+field,7)
        local row,reads=s.count(s.guard);assert(row.native_ui_active and reads==4)
        local observed=s.observed;row=s.guard();assert(row.native_ui_active and s.observed==observed)
        s.u32(s.stack+field,0);assert(not s.guard().native_ui_active)
    end
    local s=setup();s.guard();s.u32(s.stack+0x1c,2);s.u32(s.stack+12,9)
    local row=s.guard();assert(row.native_ui_active and row.native_ui_stack=='0,9')
end)
check('tactical map behind an inactive stack is forwarded on every call',function()
    local s=setup();assert(not s.guard().tactical_map_active)
    s.map=true;assert(s.guard().tactical_map_active)
    s.map=false;assert(not s.guard().tactical_map_active)
end)
check('a replaced manager is read from the new manager',function()
    local s=setup();s.guard();s.guard()
    local replacement=0x56000000;s.zero(replacement+D.ui_shift+0x84,0x90)
    s.u32(replacement+D.ui_shift+0x84,3);s.ptr(s.game+R.global_ui,replacement)
    assert(s.guard().native_ui_active)
end)
check('a manager pointer changing around the stack read is rejected, then recovers',function()
    local s=setup();s.guard();s.guard()
    local pointer=s.api.read(s.game+R.global_ui,8);local calls=0
    s.intercept=function(at,n)
        if at==s.game+R.global_ui then
            calls=calls+1
            if calls==2 then return string.rep('\1',8),true end
        end
    end
    local ok,why=pcall(s.guard)
    assert(not ok and tostring(why):find('ui_state_changed_during_read',1,true),tostring(why))
    s.intercept=nil;assert(not s.guard().native_ui_active)
end)
check('a stack changing during its confirmation is rejected and never retained',function()
    local s=setup();s.guard()
    s.u32(s.stack,5);local calls=0
    s.intercept=function(at,n)
        if at==s.stack then
            calls=calls+1
            if calls==2 then return string.rep('\0',0x90),true end
        end
    end
    assert(not pcall(s.guard))
    s.intercept=nil;s.u32(s.stack,0)
    local row,reads=s.count(s.guard);assert(not row.native_ui_active and reads==4,'torn image was retained')
end)
check('an unreadable stack is an error, as before',function()
    local s=setup();s.guard()
    s.intercept=function(at)if at==s.stack then return nil,true end end
    local ok,why=pcall(s.guard);assert(not ok and tostring(why):find('ui_read_unavailable',1,true))
    s.intercept=nil;assert(not s.guard().native_ui_active)
end)
