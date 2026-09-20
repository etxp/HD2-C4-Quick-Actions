-- HD2-Addon: mods/etxp/c4_boundary_probe
-- Research probe only: no action invocation, mode writes, input injection,
-- native pointers, projectile creation, animation events or gameplay hooks.
local existing = rawget(_G, 'HD2C4BoundaryProbe')
if existing then return existing end
local M = {version='0.1.0-exp01', capture=false, tick=0, elapsed_ms=0,
           status='starting', records=0, bytes=0, disabled=false}
rawset(_G, 'HD2C4BoundaryProbe', M)
local loader = rawget(_G, 'CowboyBingusModLoader')
local engine = rawget(_G, 'stingray')
local previous_update = rawget(_G, 'update')
if type(loader) ~= 'table' or loader.api ~= 1 or type(loader.version) ~= 'number'
    or loader.version < 16 or type(loader.open_log) ~= 'function'
    or type(engine) ~= 'table' or type(previous_update) ~= 'function' then
    M.status = 'unsupported_loader_engine_or_update'; M.disabled = true
    print('[C4BoundaryProbe] '..M.status)
    return M
end

local function quote(s)
    return '"'..s:gsub('[%z\1-\31\\"]', function(c)
        if c == '\\' then return '\\\\' end
        if c == '"' then return '\\"' end
        return string.format('\\u%04x', string.byte(c))
    end)..'"'
end
local function json(v)
    local kind = type(v)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return v and 'true' or 'false' end
    if kind == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        return string.format('%.15g', v)
    end
    if kind == 'string' then return quote(v) end
    assert(kind == 'table', 'non_json_value')
    local keys, parts = {}, {}
    for k in pairs(v) do assert(type(k) == 'string', 'non_string_key'); keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts+1] = quote(k)..':'..json(v[k]) end
    return '{'..table.concat(parts, ',')..'}'
end

local file
local function close()
    if file then pcall(file.flush, file); pcall(file.close, file); file = nil end
end
local function emit(kind, extra)
    if not file or M.disabled then return end
    local row = {schema=1, record_type=kind, evidence_kind='RUNTIME_OBSERVATION',
        timestamp_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'), tick=M.tick,
        tick_kind='lua_update_callback_count', elapsed_ms=M.elapsed_ms,
        clock_kind='sum_of_valid_update_dt', phase='before_original_update',
        current_weapon='UNKNOWN', current_fire_mode='UNKNOWN', input='NONE',
        requested_action='NONE', executed_action='NONE', pending_action='NONE',
        action_lock='NOT_IMPLEMENTED', action_result='OBSERVATION_ONLY'}
    for k, v in pairs(extra or {}) do row[k] = v end
    local line = json(row)..'\n'
    if M.records >= 10000 or M.bytes + #line > 4*1024*1024 then
        local final = json({schema=1, record_type='limit', tick=M.tick,
                            reason='bounded_log_limit', capture_stopped=true})..'\n'
        assert(file:write(final)); close()
        M.disabled=true; M.status='log_limit'; M.capture=false
        return
    end
    assert(file:write(line), 'log_write_failed')
    M.records=M.records+1; M.bytes=M.bytes+#line
end

local function fail(reason)
    pcall(emit, 'probe_error', {reason=tostring(reason)})
    M.disabled=true; M.capture=false; M.status=tostring(reason); close()
    print('[C4BoundaryProbe] disabled: '..M.status)
end

local function open_log()
    local base = loader.log_directory
    if not base then
        local local_app_data = os.getenv('LOCALAPPDATA')
        assert(local_app_data and local_app_data ~= '', 'log_directory_unknown')
        base=local_app_data..'/CowboyBingus/Helldivers2/Logs'
    end
    local prefix='C4Boundary_'..os.date('!%Y%m%dT%H%M%SZ')
    for i=1,100 do
        local name=prefix..'_'..string.format('%03d',i)..'.log'
        -- open_log uses mode w; check existence before choosing a session name.
        local prior=io.open(base..'/'..name,'rb')
        if prior then prior:close() else
            file=assert(loader.open_log(name), 'log_open_failed')
            M.log_name=name
            return
        end
    end
    error('session_name_limit')
end

local function relevant(path)
    path=path:lower()
    for _, word in ipairs({'mouse','keyboard','input','player','weapon','action',
                          'deploy','detonat','fire','aim','ability','controller'}) do
        if path:find(word,1,true) then return true end
    end
    return false
end
local function catalog()
    local visited, emitted=0,0
    local truncated=false
    local function walk(t, prefix, depth)
        for k,v in next,t do
            visited=visited+1
            if visited>8192 or emitted>=1024 then truncated=true; return end
            if type(k)=='string' and k~='__index' and k~='_G' then
                local path=prefix..'.'..k
                if relevant(path) then
                    emit('api', {path=path, raw_type=type(v), callable_verified=false})
                    emitted=emitted+1
                end
                if depth>0 and type(v)=='table' then walk(v,path,depth-1) end
                if truncated then return end
            end
        end
    end
    walk(engine,'stingray',1)
    -- Other globals are inspected by name/type only. No candidate is called.
    for k,v in next,_G do
        visited=visited+1
        if visited>8192 or emitted>=1024 then truncated=true; break end
        if type(k)=='string' and k~='stingray' and relevant(k) then
            emit('api', {path='_G.'..k, raw_type=type(v), callable_verified=false})
            emitted=emitted+1
            if type(v)=='table' then walk(v,'_G.'..k,0) end
        end
        if truncated then break end
    end
    emit('catalog_complete', {visited=visited, emitted=emitted, truncated=truncated,
        scope='stingray two levels plus named relevant globals; absence is not proof of no API'})
end

local function flag(v)
    if type(v)=='boolean' then return v end
    if type(v)=='number' and v==v then return v>0 end
    error('unexpected_input_value_'..type(v))
end
local function device_button(device, name, label)
    assert(type(device)=='table','missing_input_device_'..label)
    for _,method in ipairs({'button_id','button','pressed','released'}) do
        assert(type(rawget(device,method))=='function', 'missing_input_method_'..method)
    end
    local id=device.button_id(name)
    assert(type(id)=='number' and id>=0 and id==math.floor(id), 'unresolved_button_'..name)
    local reported=type(device.button_name)=='function' and device.button_name(id) or name
    emit('button_binding', {input=label, engine_name=tostring(reported), button_id=id,
         source='stingray device; no OS hook'})
    return {device=device, id=id, label=label, down=nil, held_ticks=0}
end
local mouse, toggle, marker
local function sample(b)
    return flag(b.device.button(b.id)), flag(b.device.pressed(b.id)), flag(b.device.released(b.id))
end
local function poll_mouse(b, down, pressed, released)
    local old=b.down
    local event
    if pressed and released then event='PRESSED_RELEASED'
    elseif pressed then event='PRESSED'
    elseif released then event='RELEASED'
    elseif old==nil then event=down and 'HELD_AT_CAPTURE_START' or 'BASELINE'
    elseif down and not old then event='DOWN_WITHOUT_PRESSED'
    elseif not down and old then event='UP_WITHOUT_RELEASED'
    elseif down and b.held_ticks==1 then event='HELD' end
    if event then
        emit('input', {input=b.label, event=event, native_pressed=pressed,
            native_released=released, down=down, held_ticks=b.held_ticks,
            repeated_pressed_while_down=pressed and old==true,
            derived_pressed=old==false and down, derived_released=old==true and not down})
    end
    b.held_ticks=down and (b.held_ticks+1) or 0
    b.down=down
end

local function tick(dt)
    M.tick=M.tick+1
    if type(dt)=='number' and dt>=0 and dt<math.huge then M.elapsed_ms=M.elapsed_ms+dt*1000 end
    local toggle_down, toggle_pressed=sample(toggle)
    if toggle_pressed and toggle.down~=true then
        M.capture=not M.capture
        for _,b in ipairs(mouse) do b.down=nil; b.held_ticks=0 end
        emit('capture', {enabled=M.capture, input='F6',
             scope='all mouse contexts; C4 equip and outcome require manual annotation'})
        assert(file:flush(), 'log_flush_failed')
    end
    toggle.down=toggle_down
    local marker_down, marker_pressed=sample(marker)
    if marker_pressed and marker.down~=true then
        emit('manual_marker', {input='F7', note='tester marker; does not assert weapon, mode or action'})
    end
    marker.down=marker_down
    if M.capture then
        local ld,lp,lr=sample(mouse[1])
        local rd,rp,rr=sample(mouse[2])
        if lp and rp then
            emit('simultaneous_input', {input='LMB+RMB', resolution='OBSERVE_BOTH_NO_PRIORITY_SELECTED'})
        end
        poll_mouse(mouse[1],ld,lp,lr); poll_mouse(mouse[2],rd,rp,rr)
    end
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end
end

local ok,why=pcall(function()
    open_log()
    emit('session', {version=M.version, loader_api=loader.api, loader_version=loader.version,
        game_build='UNVERIFIED_AT_RUNTIME', action_execution_enabled=false,
        capture_toggle='F6', manual_marker='F7'})
    catalog()
    toggle=device_button(engine.Keyboard,'f6','F6')
    marker=device_button(engine.Keyboard,'f7','F7')
    mouse={device_button(engine.Mouse,'left','LMB'),device_button(engine.Mouse,'right','RMB')}
    assert(file:flush(),'log_flush_failed')
end)
if not ok then fail(why); return M end
M.status='ready'
update=function(dt,...)
    if not M.disabled then
        local success,err=pcall(tick,dt)
        if not success then fail(err) end
    end
    return previous_update(dt,...)
end
local previous_shutdown=rawget(_G,'shutdown')
shutdown=function(...)
    pcall(emit,'shutdown'); close(); M.disabled=true; M.capture=false; M.status='closed'
    if previous_shutdown then return previous_shutdown(...) end
end
print('[C4BoundaryProbe] F6 toggles capture; F7 marks a moment. Log: '..M.log_name)
return M
