-- Phase-local page spans. They live only inside one uninterrupted Lua
-- before/after phase and are discarded at every native mutation. Snapshot
-- construction and cache revalidation may consult them; a capability check at
-- a native call or data-write boundary always reads memory again.
return function(api)
    local floor,sub=math.floor,string.sub
    local at_of,bytes_of={},{}
    local active,used,hits,epoch=false,false,0,0
    local function clear()
        epoch=epoch+1
        if used then at_of,bytes_of={},{};used=false end
    end
    -- Changes whenever the phase spans are discarded (boundary or mutation).
    function api.memo_epoch() return active and epoch or nil end
    function api.memo_begin() clear();active=true end
    function api.memo_end() clear();active=false end
    api.memo_reset=clear
    function api.memo_active() return active end
    function api.memo_hits() return hits end
    function api.memo_put(at,bytes)
        if not active then return end
        local page=floor(at/4096)
        if floor((at+#bytes-1)/4096)~=page then return end
        local old=at_of[page]
        -- Keep a wider span already read in this phase only while it agrees
        -- with these newer bytes; newer data always replaces a stale span.
        if old and old<=at and old+#bytes_of[page]>=at+#bytes
            and sub(bytes_of[page],at-old+1,at-old+#bytes)==bytes then return end
        at_of[page]=at;bytes_of[page]=bytes;used=true
    end
    function api.memo_get(at,n)
        if not used then return nil end
        local page=floor(at/4096)
        local base=at_of[page]
        if not base then return nil end
        local offset=at-base;local bytes=bytes_of[page]
        if offset<0 or offset+n>#bytes then return nil end
        hits=hits+1
        if offset==0 and n==#bytes then return bytes end
        return sub(bytes,offset+1,offset+n)
    end
    function api.peek(at,n)
        local bytes=api.memo_get(at,n)
        if bytes then return bytes end
        bytes=api.read(at,n)
        if bytes and #bytes==n then api.memo_put(at,bytes) end
        return bytes
    end
    return api
end
