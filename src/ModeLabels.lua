-- Two cosmetic fields in the C4 resource descriptor and two borrowed empty
-- formatted-text cache slots. Native code/pages and ability IDs stay intact.
local M={}
M.ids={0x8bc421a5,0xacf702d0}
local ORIGINAL={0x84df8234,0x6c9d6c92}
local function pack(n)
    local b={};for i=1,4 do b[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(b)
end
function M.new(api,game,base,symbols,verify,write,emit)
    local self={lease=nil,buffers={},failed=false}
    -- The writer owns/pins the strings for the lifetime of this addon, even
    -- after a transient restore failure or another writer taking a cache slot.
    local texts={'MANUAL / 手動引爆','CONTACT / 接觸引爆'}
    local slots={game+symbols.global_contact_manual_label,game+symbols.global_contact_contact_label}
    for i,text in ipairs(texts)do self.buffers[i]=write.text(text)end
    local function template()
        local _,_,cap=base.snapshot(api,game,function(e,row)
            assert(row.ability_template_status=='present','mode_labels_template_missing')
            local templates=e.ptr(e.owner+D.ability_templates,true)
            local start=0;for b=8,1,-1 do start=(start*256+e.weapon:byte(b))%D.ability_capacity end
            for probe=0,D.ability_capacity-1 do
                local slot=templates+((start+probe)%D.ability_capacity)*16
                local t=e.read(slot,16,true);local hash=e.resource(t)
                if hash=='0000000000000000'then break end
                if hash=='51f50d6321f52f3d' then
                    local index=e.u32(t,8);assert(index<D.ability_capacity,'mode_labels_index')
                    local at=templates+D.ability_capacity*16+index*0x58
                    local bytes=e.read(at,0x58,true)
                    return {at=at,owner=e.owner,templates=templates,slot=slot,key=t,
                        bytes=bytes,same=e.checked}
                end
            end
        end)
        return cap
    end
    local function valid(lease)
        return api.pointer(api.read(game+symbols.global_contact_owner,8))==lease.owner
            and api.pointer(api.read(lease.owner+D.ability_templates,8))==lease.templates
            and api.read(lease.slot,16)==lease.key
    end
    local function restore()
        local lease=self.lease
        if lease then
            if valid(lease)then
                for i,offset in ipairs({16,56})do
                    local current=api.read(lease.at+offset,4)
                    if current==pack(M.ids[i])then
                        assert(write.exchange(lease.at+offset,current,pack(ORIGINAL[i])),'mode_label_restore_failed')
                    end
                end
            end
            self.lease=nil
        end
        for i,address in ipairs(slots)do
            local expected=self.buffers[i].bytes
            if api.read(address,8)==expected then
                assert(write.exchange(address,expected,string.rep('\0',8)),'mode_cache_restore_failed')
            end
        end
    end
    function self.stop()local ok,why=pcall(restore);return ok,why end
    function self.sync(enabled)
        local ok,why=pcall(function()
            if not enabled or self.failed then restore();return end
            verify()
            if self.lease and not valid(self.lease)then restore()end
            local lease=self.lease
            if not lease then
                -- Managers/selected C4 do not exist during startup and loading.
                -- No lease or writes yet: wait for a fresh context next update.
                local ready,value=pcall(template)
                if not ready or not value then return end
                lease=value
            end
            if not self.lease then
                for i,offset in ipairs({16,56})do
                    assert(lease.bytes:sub(offset+1,offset+4)==pack(ORIGINAL[i]),'mode_labels_already_modified')
                end
                assert(lease.same(),'mode_labels_context_changed')
                assert(emit('mode_labels_call',{action_result='CALL_BEGIN'}),'mode_labels_log_unavailable')
                assert(lease.same(),'mode_labels_context_changed_after_log')
                -- Pin the restoration record before the first partial mutation.
                self.lease=lease
            end
            for i,address in ipairs(slots)do
                local current=assert(api.read(address,8),'mode_cache_read_failed')
                if current~=self.buffers[i].bytes then
                    assert(current==string.rep('\0',8),'mode_cache_in_use')
                    assert(write.exchange(address,current,self.buffers[i].bytes),'mode_cache_write_failed')
                end
            end
            assert(valid(lease),'mode_labels_identity_changed')
            for i,offset in ipairs({16,56})do
                local current=api.read(lease.at+offset,4)
                if current~=pack(M.ids[i])then
                    assert(current==pack(ORIGINAL[i]),'mode_label_taken_over')
                    assert(write.exchange(lease.at+offset,current,pack(M.ids[i])),'mode_label_write_failed')
                end
            end
        end)
        if not ok then
            self.failed=true;pcall(restore)
            pcall(emit,'mode_labels_unavailable',{reason=tostring(why)})
        end
        return ok
    end
    return self
end
return M
