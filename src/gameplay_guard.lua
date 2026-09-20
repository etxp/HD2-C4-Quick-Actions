-- Read-only window state for automatic pause/resume. Never changes cursor,
-- focus, or input bindings. Requires a fresh released baseline after a pause.
local M={}
local function boolean(v)
    assert(type(v)=='boolean' or v==0 or v==1,'invalid_window_state')
    return v==true or v==1
end
function M.new(engine,emit)
    local self={ready=false,status=nil,last_key=nil,latest={}}
    local function window_state()
        local window=assert(type(engine.Window)=='table' and engine.Window,'window_api_missing')
        assert(type(window.has_focus)=='function' and type(window.show_cursor)=='function','window_api_missing')
        local row={window_has_focus=boolean(window.has_focus()),
            window_show_cursor=boolean(window.show_cursor())}
        -- Log mouse capture for live comparison; do not require it because
        -- controller play may not retain mouse capture in every input mode.
        if type(window.mouse_focus)=='function' then
            row.window_mouse_focus=boolean(window.mouse_focus())
        end
        return row
    end
    function self.sample(foreground,guard_held,released)
        local ok,row=pcall(window_state)
        if not ok then row={window_state_error=tostring(row)} end
        local reason=not ok and 'window_state_unavailable' or
            (not foreground or not row.window_has_focus) and 'focus_lost' or
            row.window_show_cursor and 'game_ui_cursor_visible' or
            guard_held and 'reload_or_menu_key_held' or nil
        if reason then self.ready=false
        elseif not self.ready then
            if released then self.ready=true else reason='waiting_for_released_controls' end
        end
        local allowed=self.ready and reason==nil
        row.controls_allowed=allowed;row.runtime_state=reason or 'gameplay'
        row.activation='AUTOMATIC_LOCAL_C4'
        self.latest=row;self.status=row.runtime_state
        local key=table.concat({self.status,tostring(row.window_has_focus),tostring(row.window_show_cursor),
            tostring(row.window_mouse_focus),tostring(row.window_state_error)},':')
        if key~=self.last_key then
            assert(emit('gameplay_guard',row),'gameplay_guard_log_unavailable');self.last_key=key
        end
        return allowed
    end
    function self.fields() return self.latest end
    return self
end
return M
