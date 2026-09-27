-- EXP03. Exact C4 configuration from EXP02, plus the original eligibility data.
-- Reads only. The returned capability is private and expires after this callback.
local bit=require('bit')
local M={}
local EXPECTED='090200000000000000000000000000003482df840000000014f02aa3c6abad38010100000000000008020000000000000000000000000000926c9d6c00000000f8934147834337550001000000000000'

function M.snapshot(api,game,base)
    return base.snapshot(api,game,function(e,row)
        local read,ptr,global,lookup,u32=e.read,e.ptr,e.global,e.lookup,e.u32
        row.action_read_stage='c4_descriptors'
        assert(row.ability_template_status=='present' and
            row.ability_template_hex:sub(1,160)==EXPECTED,'unsupported_c4_descriptors')
        assert(row.weapon_data_status~='missing' and e.weapon_data_index and e.weapon_data_index~=0xffffffff,
            'weapon_data_missing')
        local types=row.weapon_function_types
        assert(types and types['0']==10 and types['1']==0 and types['2']==0 and types['3']==0,
            'unsupported_c4_function_types')
        local selector=row.weapon_function_values['0']
        assert(selector==0 or selector==1,'unsupported_c4_selector')
        row.current_fire_mode=selector==0 and 'DEPLOY' or 'DETONATE'
        row.layout_evidence='EXP02_EQUIPPED_IDENTITY_AND_DESCRIPTORS_CONFIRMED'
        local function index(manager,offset,id)
            local i=lookup(manager+offset,id,65536)
            if i then assert(i<4096,'action_component_index_limit') end
            return i
        end
        local function component(manager,map,registry,id,entity)
            local i=assert(index(manager,map,id),'action_component_missing')
            assert(read(ptr(ptr(manager+registry,true)+i*8,true),24,true)==entity,
                'action_component_identity_mismatch')
            return i
        end
        local cap={weapon_id=e.weapon_id,weapon_data=e.weapon_data,same=e.checked,
            identity=table.concat({e.hex(e.entity),e.hex(e.weapon),tostring(e.owner)},':')}
        row.action_read_stage='weapon_driver'
        cap.weapon_manager=global(0x276c390)
        local wi=component(cap.weapon_manager,0x28,0x40,e.weapon_id,e.weapon)
        local state=read(ptr(cap.weapon_manager+0x50,true)+wi*40,40,true)
        local flags=u32(state,0)
        row.weapon_driver_flags=string.format('%08x',flags)
        -- 0x73d210 checks projectile/other weapon kinds before AbilityWeapon.
        -- Ammo selection below follows 0x73cf80's ordered bit tests; requiring
        -- the exclusive 0x408 profile incorrectly rejected live EXP03 C4.
        assert(bit.band(flags,0x19)==8,'unsupported_c4_weapon_kind_flags')
        if bit.band(flags,0x80)~=0 then row.ammo_path='weapon_magazine'
        elseif bit.band(flags,0x100)~=0 then row.ammo_path='weapon_rounds'
        elseif bit.band(flags,0x400)~=0 then row.ammo_path='weapon_resource'
        elseif bit.band(flags,0x200)~=0 then row.ammo_path='weapon_heat'
        else row.ammo_path='no_native_ammo_component' end
        assert(row.ammo_path=='weapon_rounds' or row.ammo_path=='weapon_resource',
            'unsupported_c4_ammo_path')

        row.action_read_stage='ability_state'
        local driver=global(0x276c728)
        local di=component(driver,0x20,0x38,e.weapon_id,e.weapon)
        row.native_fire_held=read(ptr(driver+0x48,true)+di*8,8,true):byte(1)~=0
        cap.ability_manager=global(0x276c370)
        local bi=component(cap.ability_manager,0x18,0x30,e.weapon_id,e.weapon)
        local ability=read(ptr(cap.ability_manager+0x38,true)+bi*0xe0,32,true)
        assert(ability:byte(17)<=1,'unsupported_ability_active_flag')
        row.active_ability_id=u32(ability,0)
        row.native_action_active=ability:byte(17)~=0
        cap.active=row.native_action_active;cap.ability_id=row.active_ability_id

        -- Original 0x73ce40 -> 0x91c940: reject the same >= 2 state, if present.
        row.action_read_stage='native_weapon_gates'
        local blocked=false
        local wm=global(0x276c3b8)
        local si=index(wm,0x28,e.weapon_id)
        if si then
            row.native_block_state=u32(read(ptr(wm+0x50,true)+si*0x1b8+0x19c,4,true),0)
            blocked=row.native_block_state>=2
        end
        -- Original 0x76f3d0 -> 0x76f320. These are the native exclusion bits;
        -- their gameplay names are deliberately not inferred from bit numbers.
        local fm=global(0x276c788)
        local fi=index(fm,0x20,e.weapon_id)
        local exclusions=fi and u32(read(ptr(fm+0x50,true)+fi*4,4,true),0) or 0
        row.native_exclusion_flags=string.format('%08x',exclusions)
        blocked=blocked or (bit.band(exclusions,1)~=0 and bit.band(exclusions,2)==0)
            or (bit.band(exclusions,8)~=0 and bit.band(exclusions,16)==0)
            or (bit.band(exclusions,32)~=0 and bit.band(exclusions,64)==0)
            or bit.band(exclusions,4)~=0

        row.action_read_stage='ammo_component'
        if row.ammo_path=='weapon_rounds' then
            -- 0x73cf80 (0x73d122..0x73d1dd): the selected magazine count
            -- alone is insufficient when this weapon uses a chambered round.
            local rm=global(0x276ca00)
            local ri=component(rm,0x28,0x40,e.weapon_id,e.weapon)
            local rounds=read(ptr(rm+0x50,true)+ri*24,24,true)
            local runtime=read(ptr(rm+0x58,true)+ri*20,20,true)
            row.rounds_state_hex=e.hex(rounds);row.rounds_runtime_hex=e.hex(runtime)
            local selected=u32(runtime,4)
            row.rounds_selected_magazine=selected
            assert(selected<=1,'unsupported_rounds_magazine_index')
            row.rounds_magazine_count=u32(rounds,4+selected*4)
            row.rounds_chamber_token=u32(rounds,0x10)
            row.rounds_chamber_blocked=runtime:byte(0x11)~=0

            -- Effective settings getter 0x4f7ff0: instance override first,
            -- then the exact resource table used by leaf 0x4f7bc0.
            row.action_read_stage='rounds_configuration'
            local override=index(rm,0x68,e.weapon_id)
            local config
            if override then
                config=read(ptr(rm+0xa8,true)+override*0x84,0x84,true)
                row.rounds_config_source='entity_override'
            else
                local templates=ptr(e.owner+0xf113a8,true)
                -- Hash is uint64. Compute the remainder by bytes to avoid
                -- rounding its high bits through a Lua double.
                local start=0
                for b=8,1,-1 do start=(start*256+e.weapon:byte(b))%46 end
                for probe=0,45 do
                    local entry=read(templates+((start+probe)%46)*16,16,true)
                    local hash=e.resource(entry)
                    if hash=='0000000000000000' then break end
                    if hash==row.current_weapon_resource then
                        local ti=u32(entry,8)
                        assert(ti<46,'rounds_template_index_limit')
                        config=read(templates+0x2e0+ti*0x84,0x84,true)
                        break
                    end
                end
                row.rounds_config_source='resource_template'
            end
            assert(config,'rounds_configuration_missing')
            row.rounds_config_hex=e.hex(config)
            row.rounds_chambered=config:byte(0x69)~=0
            if row.rounds_chambered then
                row.deploy_ammo_ready=not row.rounds_chamber_blocked and row.rounds_chamber_token~=0
                row.deploy_ammo_reason=row.rounds_chamber_blocked and 'rounds_chamber_blocked' or
                    row.rounds_chamber_token==0 and 'rounds_chamber_empty' or 'rounds_chamber_ready'
            else
                -- Native setg is signed, so 0xffffffff must never pass as ammo.
                row.deploy_ammo_ready=row.rounds_magazine_count>0 and row.rounds_magazine_count<0x80000000
                row.deploy_ammo_reason=row.deploy_ammo_ready and 'rounds_magazine_ready' or 'rounds_magazine_empty'
            end
            row.ammo_available=row.rounds_magazine_count
            row.ammo_counter_source='native_rounds_selected_magazine'
            row.ammo_counter_semantics='SELECTED_MAGAZINE_ONLY_NOT_BACKPACK_OR_CHAMBER'
        else
        -- Original 0x76a1e0: resolve the resource provider, then its actual
        -- remaining counter. 0x73bf20 also counts an already deployed charge,
        -- so it MUST NOT be used as the Deploy admission check.
        local rm=global(0x276c7c0)
        local ri=component(rm,0x20,0x38,e.weapon_id,e.weapon)
        local provider=u32(read(ptr(rm+0x48,true)+ri*36,4,true),0)
        row.ammo_provider_entity_id=provider
        row.ammo_available=0
        if provider~=0 and provider~=0xffffffff and provider~=0x7fff then
            local cm=global(0x276c318)
            local ci=index(cm,0x20,provider)
            if ci then
                row.ammo_available=u32(read(ptr(cm+0x50,true)+ci*8,8,true),0)
                assert(row.ammo_available<=1024,'unsupported_ammo_counter')
                row.ammo_counter_source='native_resource_counter'
            else
                local alternate=global(0x276c448)
                local ai=index(alternate,0x20,provider)
                if ai then
                    local b=read(ptr(alternate+0x50,true)+ai*0x2c,8,true)
                    row.ammo_available=u32(b,0)~=0 and u32(b,4)~=0 and 1 or 0
                end
                row.ammo_counter_source='native_resource_boolean'
            end
        else row.ammo_counter_source='no_resource_provider' end
        row.ammo_counter_semantics='RESOURCE_PROVIDER_COUNTER_OR_BOOLEAN'
        row.deploy_ammo_ready=row.ammo_available>0
        row.deploy_ammo_reason=row.deploy_ammo_ready and 'resource_ready' or 'empty_c4_resource'
        end

        -- The EXP03 test scope is deliberately limited to the conservative
        -- local grounded state used by the same-build reference. This is an
        -- EXTRA veto, not a replacement for any C4 native eligibility rule.
        row.action_read_stage='avatar_scope'
        local av=read(e.avatar+0x53e880+e.avatar_index*0x1238,24,true)
        row.avatar_flags=e.hex(av)
        row.test_avatar_allowed=bit.band(u32(av,0),2)~=0
            and bit.band(u32(av,0),0x101000)==0 and bit.band(u32(av,4),0x81000000)==0
            and bit.band(u32(av,8),0xc4010800)==0 and bit.band(u32(av,12),0x2000a347)==0
            and bit.band(u32(av,16),1)==0
        cap.interrupt=not row.test_avatar_allowed or row.native_fire_held
        cap.blocked=blocked or cap.interrupt
        cap.deploy_ready=row.deploy_ammo_ready
        row.action_gate=blocked and 'NATIVE_WEAPON_BLOCKED' or
            not row.test_avatar_allowed and 'OUTSIDE_EXP03_AVATAR_SCOPE' or
            row.native_fire_held and 'ORIGINAL_FIRE_ACTIVE' or
            cap.active and 'NATIVE_ACTION_ACTIVE' or 'READY'
        row.action_read_stage='complete'
        return cap
    end)
end
return M
