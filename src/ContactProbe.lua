-- Read-only evidence for contact detonation. No explosions, native calls,
-- component writes or resource-template changes are authorized by this module.
local bit=require('bit')
local M={}
local CHARGE='9b75217d8312dd67'
local CHARGE_RESOURCE='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge'

function M.snapshot(api,game,base,symbols,scene,events)
    return base.snapshot(api,game,function(e,row)
        local read,ptr,lookup,u32=e.read,e.ptr,e.lookup,e.u32
        local manager=e.global(symbols.global_contact_remote)
        assert(e.global(symbols.global_contact_owner)==e.owner,'contact_world_mismatch')
        local count=u32(read(manager+0x10,4,true),0)
        assert(count<=128,'contact_registry_budget')
        local samples={}
        if count==0 then return samples end
        local registry=ptr(manager+0x38,true)
        local links=ptr(manager+0x48,true)
        for i=0,count-1 do
            local entity_at=ptr(registry+i*8,true)
            local entity=read(entity_at,24,false)
            if e.resource(entity)==CHARGE and bit.band(entity:byte(21),1)~=0 then
                -- Original C4 remote detonation resolves this reference through
                -- entity_unit_map, then compares its entity ID to the weapon ID.
                -- Merely being newly spawned or close to the player is not ownership.
                local reference=u32(read(links+i*8,8,true),0)
                local owner_index=reference~=0x7fff and lookup(e.owner+D.entity_unit_map,reference,1048576)
                if owner_index then
                    assert(owner_index<262144,'contact_owner_index')
                    local owner=read(e.owner+D.entity_array+owner_index*24,24,true)
                    if owner==e.weapon then
                        local id=u32(entity,8)
                        assert(lookup(manager+0x20,id,65536)==i,'contact_registry_index_changed')
                        local entity_index=assert(lookup(e.owner+D.entity_id_map,id,1048576),'contact_entity_missing')
                        assert(entity_index<262144,'contact_entity_index')
                        assert(read(e.owner+D.entity_array+entity_index*24,24,true)==entity,
                            'contact_entity_identity_changed')
                        assert(read(entity_at,24,true)==entity,'contact_entity_changed')
                        assert(#samples<16,'contact_owned_budget')
                        local item={entity_id=id,unit_reference=u32(entity,12),
                            owner_weapon_id=e.weapon_id,owner_reference=reference,
                            ownership='NATIVE_REMOTE_WEAPON_RELATION',
                            sticky_present=false,explosive_present=false}
                        local function component(global_name,map,registry_offset)
                            local m=e.global(symbols[global_name])
                            local index=lookup(m+map,id,65536)
                            if not index then return end
                            assert(index<4096,'contact_component_index')
                            assert(read(ptr(ptr(m+registry_offset,true)+index*8,true),24,true)==entity,
                                'contact_component_identity_changed')
                            return m,index
                        end
                        local sticky,si=component('global_contact_sticky',0x20,0x38)
                        if sticky then
                            item.sticky_present=true
                            item.sticky_data=e.hex(read(ptr(sticky+0x40,true)+si*20,20,true))
                            item.sticky_state=e.hex(read(ptr(sticky+0x48,true)+si*8,8,true))
                        end
                        local explosive,xi=component('global_contact_explosive',0x38,0x50)
                        if explosive then
                            item.explosive_present=true
                            item.explosive_state=e.hex(read(ptr(explosive+0x60,true)+xi*64,64,true))
                            item.explosive_network=e.hex(read(ptr(explosive+0x68,true)+xi*56,56,true))
                        end
                        samples[#samples+1]=item
                    end
                end
            end
        end
        local by_id={}
        for _,item in ipairs(samples) do by_id[item.entity_id]=item;item.contacts={} end
        local function item_for_unit(unit)
            if unit==0 or unit==0xffffffff then return end
            local id=lookup(e.owner+D.unit_entity_id_map,unit,1048576)
            return id and by_id[id]
        end
        -- Entity +12 is a native reference, not an engine Unit. Only use the
        -- engine's Unit.id -> entity-ID relation to associate scene positions.
        for _,unit in ipairs(scene or {}) do
            local item=item_for_unit(unit.id)
            if item then item.engine_unit_id=unit.id;item.position=unit.position end
        end
        local matched=0
        for _,contact in ipairs(events and events.contacts or {}) do
            for _,side in ipairs({'a','b'}) do
                local unit=contact['unit_'..side]
                local item=item_for_unit(unit)
                if item then
                    matched=matched+1;assert(matched<=128,'contact_event_match_budget')
                    item.contacts[#item.contacts+1]={kind=contact.kind,side=side,
                        engine_unit_id=unit,payload=e.hex(contact.raw),
                        native_dispatch_eligible=contact.kind~=2 and contact.unit_a~=contact.unit_b}
                end
            end
        end
        return samples
    end)
end

function M.new(api,game,base,symbols,verify,sr,emit,event_reader)
    local self={until_ms=-1,last=-1,serial=0,disabled=false,last_events={before=-1,after=-1}}
    local function report(kind,row)
        row.observation_only=true;row.contact_detonation_enabled=false
        pcall(emit,kind,row)
    end
    function self.begin(now)
        self.serial=self.serial+1;self.until_ms=now+10000;self.last=now-50
        self.last_events={before=now-250,after=now-250}
        report('contact_probe_begin',{capture_id=self.serial,window_ms=10000})
    end
    function self.sample(now,phase)
        if self.disabled or now>self.until_ms then return end
        -- Read paired before/after observations every 50 ms. Do not infer
        -- collision from sampled speed, expiry, disappearance or attachment.
        if phase=='before' then
            self.pair=now-self.last>=50
            if self.pair then self.last=now end
        end
        if not self.pair and not event_reader then return end
        local ok,why=pcall(function()
            verify()
            local events,event_error
            if event_reader then events,event_error=event_reader.snapshot() end
            local has_contacts=events and #events.contacts>0
            local scene={}
            local position_ok,position_error=true,nil
            if self.pair then
                position_ok,position_error=pcall(function()
                    local world=assert(sr.Application.main_world(),'contact_no_world')
                    local count=0
                    for _,unit in pairs(sr.World.units_by_resource(world,CHARGE_RESOURCE)) do
                        count=count+1;assert(count<=128,'contact_scene_budget')
                        if sr.Unit.alive(unit) then
                            local id=sr.Unit.id(unit)
                            assert(type(id)=='number' and id>=0 and id<=0xffffffff and id%1==0,'contact_engine_unit_id')
                            local v=sr.Unit.world_position(unit,1)
                            local p={sr.Vector3.x(v),sr.Vector3.y(v),sr.Vector3.z(v)}
                            assert(#p==3,'missing_position')
                            for _,x in ipairs(p) do assert(x==x and math.abs(x)<1e8,'invalid_position') end
                            scene[#scene+1]={id=id,position=p}
                        end
                    end
                    assert(sr.Application.main_world()==world,'contact_scene_world_changed')
                end)
                if not position_ok then scene={} end
            end
            local row,err,charges
            if self.pair or has_contacts then
                row,err,charges=M.snapshot(api,game,base,symbols,scene,events)
                assert(row,err)
            end
            if event_reader and (has_contacts or now-self.last_events[phase]>=250 or event_error) then
                self.last_events[phase]=now
                local matched={}
                for _,charge in ipairs(charges or {}) do
                    if charge.contacts and #charge.contacts>0 then
                        matched[#matched+1]={entity_id=charge.entity_id,
                            owner_weapon_id=charge.owner_weapon_id,contacts=charge.contacts}
                    end
                end
                report('contact_event_sample',{capture_id=self.serial,sample_phase=phase,
                    stream_status=events and 'stable' or event_error,
                    stream_bytes=events and events.bytes,stream_records=events and events.records,
                    event_types=events and events.types,collision_records=events and #events.contacts,
                    world_index=events and events.world_index,matched_charges=matched,
                    context_status=row and row.context_status,
                    action_context_status=row and row.action_context_status,
                    diagnostic=row and row.action_diagnostic})
            end
            if not self.pair then return end
            assert(row,err)
            local result={capture_id=self.serial,sample_phase=phase,
                context_status=row.context_status,selector=row.weapon_function_values and row.weapon_function_values['0'],
                action_context_status=row.action_context_status,diagnostic=row.action_diagnostic,
                charges=charges or {},position_status=position_ok and 'engine_unit_entity_map' or tostring(position_error)}
            report('contact_probe_sample',result)
        end)
        if not ok then
            -- Optional diagnostics must not revoke the accepted action backend.
            self.disabled=true
            report('contact_probe_unavailable',{reason=tostring(why)})
        end
    end
    return self
end
return M
