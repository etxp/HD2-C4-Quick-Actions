-- Revalidate recorded guard bytes with one bounded read per touched 4 KiB page.
-- Every guarded byte is still compared; only the number of OS reads changes.
-- A page is mapped as a whole, so a span inside one page is readable exactly
-- when its individual guards are. Guards crossing a boundary are split.
local M={}
local floor,sub=math.floor,string.sub
local PAGE=4096
function M.plan(guards)
    local clusters,by_page={count=#guards},{}
    local function add(at,bytes,index)
        local page=floor(at/PAGE)
        local c=by_page[page]
        if not c then
            c={at=at,stop=at+#bytes,n=0};by_page[page]=c;clusters[#clusters+1]=c
        else
            if at<c.at then c.at=at end
            if at+#bytes>c.stop then c.stop=at+#bytes end
        end
        local n=c.n+1;c.n=n;c[n]={at=at,bytes=bytes,index=index}
    end
    for i=1,#guards do
        local g=guards[i];local at,bytes=g.at,g.bytes
        local room=PAGE-at%PAGE
        while #bytes>room do
            add(at,sub(bytes,1,room),i);at=at+room;bytes=sub(bytes,room+1);room=PAGE
        end
        add(at,bytes,i)
    end
    -- image: the last span whose every guard compared equal. Lua strings are
    -- interned, so an identical later span is recognised without comparing
    -- its guards one by one and without allocating anything.
    for i=1,#clusters do
        local c=clusters[i]
        if c.n==1 then c.image=c[1].bytes end
    end
    return clusters
end
-- fresh=false may reuse a span that was itself read during this uninterrupted
-- Lua phase. Capability checks at native call/write boundaries pass fresh=true.
-- The original check read guards in walk order and stopped at the first one
-- that was unreadable (raising when strict) or different (returning false).
-- The same guard decides here: after any difference the pass is completed and
-- the earliest bad guard in walk order gives the result. Inside a phase the
-- completed pass also leaves every current span for rebuilding the snapshot.
function M.same(api,clusters,fresh,strict)
    local read=api.read
    local put=api.memo_put
    local get=not fresh and api.memo_get or nil
    local changed,gone -- lowest walk index of a different / an unreadable guard
    for i=1,#clusters do
        local c=clusters[i];local at=c.at;local size=c.stop-at
        local bytes
        if not c.split then
            bytes=get and get(at,size)
            if not bytes then
                bytes=read(at,size)
                if bytes and #bytes==size then
                    if put then put(at,bytes) end
                else
                    -- The page cannot be read as one span (unmapped, or the
                    -- byte-granular test memory): from now on use the
                    -- original individual reads for its guards.
                    bytes=nil
                    if c.n>1 then c.split=true end
                end
            end
        end
        if bytes then
            if bytes~=c.image then
                local equal=c.n>1
                for j=1,c.n do
                    local g=c[j];local offset=g.at-at
                    if c.n==1 or sub(bytes,offset+1,offset+#g.bytes)~=g.bytes then
                        equal=false
                        if not changed or g.index<changed then changed=g.index end
                    end
                end
                if equal then c.image=bytes end
            end
        else
            for j=1,c.n do
                local g=c[j];local n=#g.bytes
                local b=get and get(g.at,n)
                if not b then
                    b=read(g.at,n)
                    if b and #b==n then
                        if put then put(g.at,b) end
                    else b=nil end
                end
                if not b then
                    if not gone or g.index<gone then gone=g.index end
                elseif b~=g.bytes then
                    if not changed or g.index<changed then changed=g.index end
                end
            end
        end
    end
    if gone and (not changed or gone<changed) then
        if strict then error('read_unavailable',0) end
        return false
    end
    return changed==nil
end
-- A checker bound to a growing guard list. The plan is rebuilt only when the
-- list has grown since the previous check.
function M.checker(api,guards,strict)
    local clusters
    return function(shared)
        if not clusters or clusters.count~=#guards then clusters=M.plan(guards) end
        return M.same(api,clusters,not shared,strict)
    end
end
return M
