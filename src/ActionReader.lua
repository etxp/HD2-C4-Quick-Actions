-- EXP03. Exact C4 configuration from EXP02, plus the original eligibility data.
-- Reads only. The returned capability is private and expires after this callback.
local bit=require('bit')
local M={}
local EXPECTED='090200000000000000000000000000003482df840000000014f02aa3c6abad38010100000000000008020000000000000000000000000000926c9d6c00000000f8934147834337550001000000000000'
local function gameplay_descriptor(hex)
    -- +16/+56 are localized captions, consumed by the native weapon menu.
    -- Keep every ability ID, trigger, function and gameplay flag checked.
    return hex:sub(1,32)..hex:sub(41,112)..hex:sub(121,160)
end

function M.snapshot(api,game,base)
    return base.snapshot(api,game,function(e,row)
        local read,ptr,global,lookup,u32=e.read,e.ptr,e.global,e.lookup,e.u32
        row.action_read_stage='c4_descriptors'
        assert(row.ability_template_status=='present' and
            gameplay_descriptor(row.ability_template_hex)==gameplay_descriptor(EXPECTED),'unsupported_c4_descriptors')
        assert(row.weapon_data_status~='missing' and e.weapon_data_index and e.weapon_data_index~=0xffffffff,
            'weapon_data_missing')
        local types=row.weapon_function_types
        assert(types and types['0']==10 and types['1']==0 and types['2']==0 and types['3']==0,
            'unsupported_c4_function_types')
        local selector=row.weapon_function_values['0']
        assert(selector==0 or selector==1,'unsupported_c4_selector')
        row.current_fire_mode=selector==0 and 'DEPLOY' or 'DETONATE'
        row.detonation_mode=selector==0 and 'MANUAL' or 'CONTACT'
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
        cap.reload_identity=cap.identity -- same avatar/C4 across passenger -> foot
        row.action_read_stage='weapon_driver'
        cap.weapon_manager=global(R.global_weapon)
        local wi=component(cap.weapon_manager,0x28,0x40,e.weapon_id,e.weapon)
        local state=read(ptr(cap.weapon_manager+0x50,true)+wi*40,40,true)
        local flags=u32(state,0)
        row.weapon_driver_flags=string.format('%08x',flags)
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
        local driver=global(R.global_fire_latch)
        local di=component(driver,0x20,0x38,e.weapon_id,e.weapon)
        row.native_fire_held=read(ptr(driver+0x48,true)+di*8,8,true):byte(1)~=0
        cap.ability_manager=global(R.global_ability)
        local bi=component(cap.ability_manager,0x18,0x30,e.weapon_id,e.weapon)
        local ability=read(ptr(cap.ability_manager+0x38,true)+bi*0xe0,32,true)
        assert(ability:byte(17)<=1,'unsupported_ability_active_flag')
        row.active_ability_id=u32(ability,0)
        row.native_action_active=ability:byte(17)~=0
        cap.active=row.native_action_active;cap.ability_id=row.active_ability_id
        cap.deploy_released=false
        if cap.active and cap.ability_id==521 then
            local clock_ok,elapsed=pcall(base.f32,ability,8)
            row.native_ability_clock_valid=clock_ok and elapsed>=0 and elapsed<3600
            if row.native_ability_clock_valid then
                row.native_ability_time=elapsed
                cap.deploy_released=ability:byte(18)==0 and elapsed*D.ability_phase_hz>=D.c4_release_phase
            end
        end

        row.action_read_stage='native_weapon_gates'
        local blocked=false
        local wm=global(R.global_blocker)
        local si=index(wm,D.blocker_map,e.weapon_id)
        if si then
            row.native_block_state=u32(read(ptr(wm+D.blocker_states,true)+si*0x1b8+0x19c,4,true),0)
            blocked=row.native_block_state>=2
        end
        -- their gameplay names are deliberately not inferred from bit numbers.
        local fm=global(R.global_exclusions)
        local fi=index(fm,0x20,e.weapon_id)
        local exclusions=fi and u32(read(ptr(fm+0x50,true)+fi*4,4,true),0) or 0
        row.native_exclusion_flags=string.format('%08x',exclusions)
        blocked=blocked or (bit.band(exclusions,1)~=0 and bit.band(exclusions,2)==0)
            or (bit.band(exclusions,8)~=0 and bit.band(exclusions,16)==0)
            or (bit.band(exclusions,32)~=0 and bit.band(exclusions,64)==0)
            or bit.band(exclusions,4)~=0

        row.action_read_stage='ammo_component'
        if row.ammo_path=='weapon_rounds' then
            -- alone is insufficient when this weapon uses a chambered round.
            local rm=global(R.global_rounds)
            local ri=component(rm,0x28,0x40,e.weapon_id,e.weapon)
            local rounds=read(ptr(rm+0x50,true)+ri*24,24,true)
            local runtime=read(ptr(rm+0x58,true)+ri*20,20,true)
            row.rounds_state_hex=e.hex(rounds);row.rounds_runtime_hex=e.hex(runtime)
            row.rounds_reserve_count=u32(runtime,0)
            local selected=u32(runtime,4)
            row.rounds_selected_magazine=selected
            assert(selected<=1,'unsupported_rounds_magazine_index')
            row.rounds_magazine_count=u32(rounds,4+selected*4)
            row.rounds_chamber_token=u32(rounds,0x10)
            row.rounds_chamber_blocked=runtime:byte(0x11)~=0

            row.action_read_stage='rounds_configuration'
            local override=index(rm,0x68,e.weapon_id)
            local config
            if override then
                config=read(ptr(rm+0xa8,true)+override*D.rounds_stride,D.rounds_stride,true)
                row.rounds_config_source='entity_override'
            else
                local templates=ptr(e.owner+D.rounds_templates,true)
                -- Hash is uint64. Compute the remainder by bytes to avoid
                -- rounding its high bits through a Lua double.
                local start=0
                for b=8,1,-1 do start=(start*256+e.weapon:byte(b))%D.rounds_capacity end
                for probe=0,D.rounds_capacity-1 do
                    local entry=read(templates+((start+probe)%D.rounds_capacity)*16,16,true)
                    local hash=e.resource(entry)
                    if hash=='0000000000000000' then break end
                    if hash==row.current_weapon_resource then
                        local ti=u32(entry,8)
                        assert(ti<D.rounds_capacity,'rounds_template_index_limit')
                        config=read(templates+D.rounds_capacity*16+ti*D.rounds_stride,D.rounds_stride,true)
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
                row.deploy_ammo_ready=row.rounds_magazine_count>0 and row.rounds_magazine_count<0x80000000
                row.deploy_ammo_reason=row.deploy_ammo_ready and 'rounds_magazine_ready' or 'rounds_magazine_empty'
            end
            row.ammo_available=row.rounds_magazine_count
            row.ammo_counter_source='native_rounds_selected_magazine'
            row.ammo_counter_semantics='SELECTED_MAGAZINE_ONLY_NOT_BACKPACK_OR_CHAMBER'
        else
        -- so it MUST NOT be used as the Deploy admission check.
        local rm=global(R.global_resource_provider)
        local ri=component(rm,0x20,0x38,e.weapon_id,e.weapon)
        local provider=u32(read(ptr(rm+0x48,true)+ri*36,4,true),0)
        row.ammo_provider_entity_id=provider
        row.ammo_available=0
        if provider~=0 and provider~=0xffffffff and provider~=0x7fff then
            local cm=global(R.global_resource_counter)
            local ci=index(cm,0x20,provider)
            if ci then
                row.ammo_available=u32(read(ptr(cm+0x50,true)+ci*8,8,true),0)
                assert(row.ammo_available<=1024,'unsupported_ammo_counter')
                row.ammo_counter_source='native_resource_counter'
            else
                local alternate=global(R.global_alternate_counter)
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
        row.test_avatar_allowed=AvatarScope.apply(e,row,cap,av)
        cap.interrupt=not row.test_avatar_allowed or row.native_fire_held
        cap.blocked=blocked or cap.interrupt
        cap.deploy_ready=row.deploy_ammo_ready
        -- Keep reload diagnostics separate: a missing reload component does
        -- not remove the already verified throw/detonate capability.
        local reload_ok,reload_error=pcall(ReloadReader.apply,e,row,cap,base)
        if not reload_ok then cap.reload=nil;row.reload_context=tostring(reload_error) end
        row.action_gate=blocked and 'NATIVE_WEAPON_BLOCKED' or
            not row.test_avatar_allowed and 'UNSUPPORTED_AVATAR_STATE' or
            row.native_fire_held and 'ORIGINAL_FIRE_ACTIVE' or
            cap.active and 'NATIVE_ACTION_ACTIVE' or 'READY'
        row.action_read_stage='complete'
        return cap
    end)
end
return M
