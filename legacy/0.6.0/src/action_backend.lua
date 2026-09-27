-- Native calls are restricted to the original weapon driver sequence.
local M={}
function M.new(api,reader,base,layout,bind)
    local game=assert(api.module('game.dll'),'game_module_missing')
    assert(api.module_hash(game)==layout.module_sha256,'unsupported_game_module_hash')
    local signatures={}
    for _,s in ipairs(layout.signatures) do
        local bytes=s.hex:gsub('..',function(h) return string.char(tonumber(h,16)) end)
        assert(api.read(game+s.rva,#bytes)==bytes,string.format('unsupported_live_action_code_%08x',s.rva))
        signatures[#signatures+1]={rva=s.rva,bytes=bytes}
    end
    local native=bind(game)
    local self={}
    function self.verify()
        for _,s in ipairs(signatures) do
            assert(api.read(game+s.rva,#s.bytes)==s.bytes,string.format('action_code_changed_%08x',s.rva))
        end
    end
    function self.snapshot()
        local row,reason,cap=reader.snapshot(api,game,base)
        if not row then return nil,reason end
        return row,nil,cap
    end
    function self.execute(action,cap)
        assert(action=='DEPLOY' or action=='DETONATE','unsupported_action')
        assert(cap and not cap.active and not cap.blocked,'ineligible_action_capability')
        assert(action~='DEPLOY' or cap.deploy_ready==true,'native_deploy_ammo_not_ready')
        -- Verify all guarded code again on each request; no native mutation
        -- occurs if another mod patched these functions after initialization.
        self.verify()
        assert(cap.same(),'action_context_changed')
        local id=action=='DEPLOY' and 521 or 520
        -- Fifth argument is 1.0, loaded by 0x7cd36b from RVA 0x211c5b0.
        -- It is not 0.0. R9D=1 retains the original local/network path.
        native.start(cap.ability_manager,cap.weapon_id,id,1,1.0)
        if action=='DEPLOY' then
            native.consume(cap.weapon_manager,cap.weapon_id)
            local count=native.count(cap.weapon_manager,cap.weapon_id)
            native.after(cap.weapon_data,cap.weapon_id,count,true)
        end
        return id
    end
    return self
end
return M
