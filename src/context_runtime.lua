local M={}
function M.new(api,reader,layout)
    local game=assert(api.module('game.dll'),'game_module_missing')
    assert(api.module_hash(game)==layout.module_sha256,'unsupported_game_module_hash')
    for _,signature in ipairs(layout.signatures) do
        local expected=signature.hex:gsub('..',function(h) return string.char(tonumber(h,16)) end)
        assert(api.read(game+signature.rva,#expected)==expected,'unsupported_live_code_signature')
    end
    local self={latest={},last_ms=-math.huge,last_key=nil,last_emit=-math.huge}
    function self.fields(ms)
        local result={}
        for k,v in pairs(self.latest) do result[k]=v end
        result.context_sample_age_ms=ms-self.last_ms
        return result
    end
    function self.observe(active,ms,emit,force)
        if not active then
            self.latest={context_status='capture_off',current_weapon='UNKNOWN',current_fire_mode='UNKNOWN',
                c4_guard_candidate=false}
            self.last_ms=-math.huge
            return
        end
        if not force and ms-self.last_ms<50 then return end
        local start=api.time()
        local ok,row,reason=pcall(reader.snapshot,api,game)
        if not ok then reason=row;row=nil end
        if not row then row={current_weapon='UNKNOWN',current_fire_mode='UNKNOWN',
            c4_guard_candidate=false,context_status='snapshot_unavailable',reason=tostring(reason)} end
        row.context_sample_elapsed_ms=ms
        self.latest=row;self.last_ms=ms
        -- Inputs record the latest snapshot with its age. State rows are limited
        -- to 20 Hz; heartbeat every second includes runtime cost diagnostics.
        local key=table.concat({row.context_status,tostring(row.selected_entity_id),
            tostring(row.selected_slot),tostring(row.weapon_state_12),tostring(row.weapon_state_flags),
            tostring(row.reason)},'|')
        if force or key~=self.last_key or ms-self.last_emit>=1000 then
            emit('context',{sample_cost_ms=(api.time()-start)*1000})
            self.last_key=key;self.last_emit=ms
        end
    end
    return self
end
return M
