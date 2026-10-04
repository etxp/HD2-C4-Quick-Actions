-- One verified observation kept until its guarded bytes change.
-- A snapshot is a pure function of the bytes it guarded, so an entry whose
-- every guard still compares equal is exactly what a new walk would return.
-- The first use in each before/after phase rereads all guards; later read-only
-- uses in that uninterrupted phase share the result. Native mutations and
-- phase boundaries force the next use to reread. Nothing here authorizes a
-- native call: each mutating consumer still checks cap.same() at its boundary.
local M={}
function M.new(fetch)
    local enabled=false
    local generation=0
    local entry,validated=nil,false
    local self={}
    function self.invalidate()generation=generation+1;validated=false end
    function self.drop()generation=generation+1;validated=false;entry=nil end
    function self.begin_phase()self.invalidate();enabled=true end
    function self.end_phase()enabled=false;self.invalidate()end
    local function current()
        local e=entry
        if not enabled or not e then return nil end
        if validated then return e end
        -- Without a checker the observation cannot be proven current again.
        if not e.same then entry=nil;return nil end
        local version=generation
        -- An unreadable or changed guard only means the entry is obsolete.
        local ok,same=pcall(e.same,true)
        if ok and same and enabled and generation==version and entry==e then
            validated=true;return e
        end
        if entry==e then entry=nil end
        return nil
    end
    -- Revalidate a retained entry early so that later narrower observations
    -- in this phase can share the spans it has just read.
    function self.prime()current()end
    function self.snapshot()
        local e=current()
        if e then return e.row,e.reason,e.cap end
        local version=generation
        local row,reason,cap,same=fetch()
        -- A walk that met an unreadable address has no checker: it is shared by
        -- the read-only consumers of this phase, as before, and never beyond.
        if enabled and generation==version and row then
            entry={row=row,reason=reason,cap=cap,same=same};validated=true
        end
        return row,reason,cap
    end
    function self.wrap(target,names)
        for _,name in ipairs(names)do
            local call=assert(target[name],'observation_mutator_missing:'..name)
            target[name]=function(...)
                self.invalidate()
                return call(...)
            end
        end
    end
    return self
end
return M
