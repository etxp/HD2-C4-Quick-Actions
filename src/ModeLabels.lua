-- Two cosmetic fields in the C4 resource descriptor and two borrowed empty
-- formatted-text cache slots. Native code/pages and ability IDs stay intact.
local M={}
M.ids={0x8bc421a5,0xacf702d0}
local ORIGINAL={0x84df8234,0x6c9d6c92}
local function pack(n)
    local b={};for i=1,4 do b[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(b)
end
function M.new(api,game,base,symbols,verify,write,emit,observe)
    local self={lease=nil,buffers={},failed=false}
    -- Maintenance reads go through here. A pass that only read is a pure
    -- function of those bytes: while they all still compare equal, the next
    -- pass would repeat the same checks and write nothing, so it is skipped.
    local trace,steady
    local function peek(at,n)
        local bytes=api.read(at,n)
        if trace then
            if bytes then trace[#trace+1]={at=at,bytes=bytes} else trace=nil end
        end
        return bytes
    end
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
        return api.pointer(peek(game+symbols.global_contact_owner,8))==lease.owner
            and api.pointer(peek(lease.owner+D.ability_templates,8))==lease.templates
            and peek(lease.slot,16)==lease.key
    end
    local function restore()
        trace=nil
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
    local function install(lease,address,expected,value,reason)
        -- Read-only maintenance does not call native code. Check the complete
        -- immutable catalog only when installing or repairing owned data, after
        -- callbacks and again for each partial write. Cleanup stays independent
        -- so a later code change cannot prevent restoration of our own data.
        trace=nil
        verify()
        assert(valid(lease),'mode_labels_identity_changed_before_write')
        assert(write.exchange(address,expected,value),reason)
    end
    function self.sync(enabled)
        if steady then
            if enabled and not self.failed and self.lease==steady.lease then
                local seen,same=pcall(GuardSpans.same,api,steady,true,false)
                if seen and same then return true end
            end
            steady=nil
        end
        local held=self.lease
        -- No lease, and this phase's observation positively shows another
        -- context: nothing to install, restore or wait for.
        if enabled and not self.failed and not held and observe then
            local seen,row=pcall(observe)
            if seen and row and row.context_status~='c4_context_observed' then return true end
        end
        trace=enabled and not self.failed and held and {} or nil
        local ok,why=pcall(function()
            if not enabled or self.failed then restore();return end
            if self.lease and not valid(self.lease)then restore()end
            local lease=self.lease
            if not lease then
                trace=nil
                -- The label template is reachable only through a selected,
                -- owned local C4. Positive evidence of any other context in
                -- this phase's shared observation makes the full walk moot.
                if observe then
                    local seen,row=pcall(observe)
                    if seen and row and row.context_status~='c4_context_observed' then return end
                end
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
                local current=assert(peek(address,8),'mode_cache_read_failed')
                if current~=self.buffers[i].bytes then
                    assert(current==string.rep('\0',8),'mode_cache_in_use')
                    install(lease,address,current,self.buffers[i].bytes,'mode_cache_write_failed')
                end
            end
            assert(valid(lease),'mode_labels_identity_changed')
            for i,offset in ipairs({16,56})do
                local current=peek(lease.at+offset,4)
                if current~=pack(M.ids[i])then
                    assert(current==pack(ORIGINAL[i]),'mode_label_taken_over')
                    install(lease,lease.at+offset,current,pack(M.ids[i]),'mode_label_write_failed')
                end
            end
        end)
        local seen=trace;trace=nil
        if ok and seen and held and self.lease==held then
            steady=GuardSpans.plan(seen);steady.lease=held
        end
        if not ok then
            self.failed=true;pcall(restore)
            pcall(emit,'mode_labels_unavailable',{reason=tostring(why)})
        end
        return ok
    end
    return self
end
return M
