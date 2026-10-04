-- The Off gameplay guard must take exactly the decisions of the descriptive
-- one for every window, UI, focus, held and released combination and error.
local Guard=dofile('src/GameplayGuard.lua')
local function check(name,fn)fn();print('PASS '..name)end
local state=99
local function rnd(n)state=(state*69069+12345)%2147483648;return math.floor(state/1024)%n end
local function pair()
    local w={focus=true,cursor=false,mouse=true,active=false,map=false,menu=false}
    local calls={}
    local function make(quiet)
        local engine={Window={
            has_focus=function()calls[#calls+1]='focus';if w.focus_error then error('focus_failed')end;return w.focus end,
            show_cursor=function()calls[#calls+1]='cursor';return w.cursor end,
            mouse_focus=function()calls[#calls+1]='mouse';return w.mouse end}}
        local function native_ui(short)
            calls[#calls+1]='ui'
            if w.ui_error then error('ui_failed')end
            if short then return w.active,w.map,w.menu end
            return {native_ui_available=true,native_ui_active=w.active,tactical_map_active=w.map,weapon_menu_active=w.menu}
        end
        local emitted=0
        local guard=Guard.new(engine,function()emitted=emitted+1;return true end,native_ui,{diagnostics=not quiet})
        return guard,function()return emitted end
    end
    local full,full_emits=make(false)
    local quiet,quiet_emits=make(true)
    return w,full,quiet,calls,full_emits,quiet_emits
end
check('identical decisions, status and readiness over random sequences',function()
    local w,full,quiet=pair()
    local seen={}
    for step=1,20000 do
        local k=rnd(24)
        if k==0 then w.focus=not w.focus elseif k==1 then w.cursor=not w.cursor
        elseif k==2 then w.active=not w.active elseif k==3 then w.map=not w.map
        elseif k==4 then w.menu=not w.menu elseif k==5 then w.mouse=not w.mouse
        elseif k==6 then w.focus_error=not w.focus_error elseif k==7 then w.ui_error=not w.ui_error
        elseif k==8 then w.cursor=({0,1,true,false,'bad'})[rnd(5)+1]
        elseif k==9 then w.mouse=({0,1,true,false,7})[rnd(5)+1]
        elseif k<16 then w.focus,w.cursor,w.mouse,w.active,w.map,w.menu=true,false,true,false,false,false;w.focus_error,w.ui_error=nil,nil end
        local foreground,held,released=rnd(8)~=0,rnd(12)==0,rnd(3)~=0
        local a=full.sample(foreground,held,released)
        local b=quiet.sample(foreground,held,released)
        assert(a==b and full.status==quiet.status and full.ready==quiet.ready,
            'step '..step..': '..tostring(a)..'/'..tostring(b)..' '..tostring(full.status)..'/'..tostring(quiet.status))
        seen[full.status]=true
    end
    for _,status in ipairs({'gameplay','focus_lost','tactical_map_open','weapon_settings_open','native_game_ui_active',
        'game_ui_cursor_visible','reload_or_menu_key_held','waiting_for_released_controls','window_state_unavailable'})do
        assert(seen[status],'sequence never reached '..status)
    end
end)
check('the same engine and UI calls are made in the same order',function()
    local w,full,quiet,calls=pair()
    full.sample(true,false,true);local descriptive=table.concat(calls,',')
    for i=#calls,1,-1 do calls[i]=nil end
    quiet.sample(true,false,true);assert(table.concat(calls,',')==descriptive and descriptive=='focus,cursor,mouse,ui')
end)
check('the quiet guard builds no row and emits nothing',function()
    local w,full,quiet,_,full_emits,quiet_emits=pair()
    for _=1,5 do full.sample(true,false,true);quiet.sample(true,false,true);w.map=not w.map end
    assert(full_emits()>0 and quiet_emits()==0 and next(quiet.fields())==nil)
end)
