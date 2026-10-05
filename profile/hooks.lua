-- Diagnostic build only: attach timers and counters to the assembled modules.
do
    if type(debug)=='table' and debug.getinfo then P.line_shift=debug.getinfo(1,'l').currentline-@@LINE@@ end
    P.source=@@SOURCE@@
    local same=GuardSpans.same
    GuardSpans.same=function(api,clusters,fresh,strict)
        local ok,result=pcall(same,api,clusters,fresh,strict)
        if not ok or result~=true then P.failed(clusters) end
        if not ok then error(result,0) end
        return result
    end
    local made=0
    local new_cache=SnapshotCache.new
    SnapshotCache.new=function(fetch)
        made=made+1
        return P.wrap_cache(new_cache,made==1 and 'action' or made==2 and 'routing' or 'cache'..made)(fetch)
    end
    local function instances(module,constructor,label,names)
        local new=module[constructor]
        module[constructor]=function(...) return P.methods(new(...),label,names) end
    end
    local backend_new=ActionBackend.new
    ActionBackend.new=function(...)
        local b=P.methods(backend_new(...),'backend',{'maintain','snapshot','routing_snapshot','verify'})
        b.input_snapshot=b.routing_snapshot
        return b
    end
    local gate_new=AimInputGate.new
    AimInputGate.new=function(api,game,base,backend,profile,emit,spec,group)
        return P.methods(gate_new(api,game,base,backend,profile,emit,spec,group),spec and spec.tag or 'aim_gate',{'sync'})
    end
    instances(WeaponFireGate,'new','fire_flag_gate',{'sync'})
    instances(ModeLabels,'new','mode_labels',{'sync'})
    instances(ContactController,'new','contact',{'step'})
    instances(AutoReload,'new','auto_reload',{'step','suspend','due'})
    instances(ActionController,'new','actions',{'step'})
    instances(MBMBindings,'new','mbm',{'sample','route'})
    instances(GameplayGuard,'new','guard',{'sample'})
    AimInputState.read=P.timed('input_state.read',AimInputState.read)
    local ui_new=NativeUiGuard.new
    NativeUiGuard.new=function(...) return P.timed('native_ui',ui_new(...)) end
    local focus_new=WindowFocus
    WindowFocus=function(...) return P.timed('window_focus',focus_new(...)) end
    local assignments_new=MBMProfile.new
    MBMProfile.new=function(...) return P.timed('mbm_assignments_file',assignments_new(...)) end
    -- Read-only capture for the configuration research: with a local C4
    -- selected, record whether the detonator has the components and the
    -- WeaponData byte that the engine's own Aim and Fire reactions consult.
    -- Offsets come from one analysed game build; they are used only when the
    -- code that defines them is byte-identical in the running game.
    local bit=require('bit')
    local CODE={{0xa42330,0xa4244e,0xa0650138},{0xa5a110,0xa5a2f0,0xa204d6fa},
        {0x509a40,0x509b01,0xe231db7a},{0x509570,0x509601,0xa00765ab}}
    function P.fingerprint(read,base,from,to)
        local h=0x811c9dc5
        for at=from,to-1,4096 do
            local data=read(base+at,math.min(4096,to-at))
            if not data then return nil end
            for i=1,#data do
                h=ContextReader.product_low(bit.bxor(h,data:byte(i))%4294967296,0x01000193)
            end
        end
        return h
    end
    local build_known,captured=nil,0
    local function hex(s)return s and (s:gsub('.',function(c)return string.format('%02x',c:byte())end)) or 'unreadable'end
    P.capture=function(out,caches)
        local S=caches.routing;local cap=S and S.last_cap;local plan=cap and cap.weapon_plan
        if not plan or captured>=6 then return end
        local api,read,u32=P.api,P.raw_read,ContextReader.u32
        local game=api.module('game.dll')
        if build_known==nil then
            -- Offline tests supply synthetic managers; the game never sets this.
            build_known=rawget(_G,'C4ProfileAssumeBuild')==true or nil
        end
        if build_known==nil then
            build_known=true
            for _,c in ipairs(CODE)do
                if P.fingerprint(read,game,c[1],c[2])~=c[3] then build_known=false end
            end
        end
        if not build_known then
            if captured==0 then out('capture: skipped, this game build differs from the analysed one') end
            captured=6;return
        end
        captured=captured+1
        local function ptr(at)local b=read(at,8);return b and api.pointer(b)end
        local function lookup(at,key)
            local h=at and read(at,20);if not h then return nil,'header unreadable' end
            local n,empty,mult=u32(h,8),u32(h,12),u32(h,16)
            if n==0 then return nil,'absent (empty map)' end
            if n>1048576 or bit.band(n,n-1)~=0 then return nil,'unexpected size '..n end
            local p=api.pointer(h);if not p then return nil,'no table' end
            for probe=0,math.min(n,256)-1 do
                local row=read(p+((ContextReader.product_low(key,mult)+probe)%n)*8,8)
                if not row then return nil,'slot unreadable' end
                local k=u32(row,0)
                if k==key then local v=u32(row,4);if v==0xffffffff then return nil,'absent' end;return v end
                if k==empty then return nil,'absent' end
            end
            return nil,'probe limit'
        end
        local protection=function()return 'not queried' end
        pcall(function()
            local ffi=require('ffi')
            ffi.cdef'size_t c4qa_VirtualQuery(const void *,void *,size_t) __asm__("VirtualQuery");'
            local query=assert(ffi.load('kernel32').c4qa_VirtualQuery,'VirtualQuery unavailable')
            local info=ffi.new('uint8_t[48]')
            protection=function(at)
                if query(ffi.cast('const void *',at),info,48)==0 then return 'query failed' end
                local b=ffi.string(info,48)
                return string.format('state %x protect %x type %x',u32(b,32),u32(b,36),u32(b,40))
            end
        end)
        local id=plan.weapon_id
        out('capture %d: weapon id %08x resource %s',captured,id,hex(plan.weapon:sub(1,8)))
        local function member(name,rva,offset)
            local manager=ptr(game+rva)
            local index,why=lookup(manager and manager+offset,id)
            out('capture: %s (global %x, map +%x): %s',name,rva,offset,index and ('present, index '..index) or tostring(why))
            return manager,index
        end
        member('throwable manager',0x33264c0,0x30)
        member('fire-threshold manager',0x3326a38,0x278)
        member('fire-threshold manager second map',0x3326a38,0x2b8)
        member('fire-route component manager',0x3326c20,0x20)
        local data,override=member('weapon data override',0x3326ce0,0x70)
        local function record(name,at)
            local bytes=at and read(at+0x170,0x30)
            out('capture: %s record %s bytes +0x170..+0x19f %s',name,at and string.format('%x',at) or 'none',hex(bytes))
            if bytes then
                out('capture: %s aim byte +0x182 = %d; page %s',name,bytes:byte(0x13),protection(at+0x182))
            end
        end
        if override then
            local rows=ptr(data+0xb0)
            record('override',rows and rows+override*0x4d0)
        end
        local templates=ptr(plan.owner+0xf12bd8)
        if templates then
            local hash,found=plan.weapon:sub(1,8),nil
            for chunk=0,730*16-1,4096 do
                local block=read(templates+chunk,math.min(4096,730*16-chunk))
                if not block then break end
                for at=1,#block,16 do
                    if block:sub(at,at+7)==hash then found=u32(block,at+7);break end
                end
                if found then break end
            end
            if found and found<730 then record('shared template (index '..found..')',templates+0x2da0+found*0x4d0)
            else out('capture: shared weapon data template for this resource: %s',found and 'bad index '..found or 'not found') end
        else out('capture: weapon data template table unreadable') end
    end
    local resolve=NativeResolver.resolve
    NativeResolver.resolve=function(...)
        local resolved=resolve(...)
        local scoped=resolved.verifier_for
        resolved.verifier_for=function(name) return P.timed('code_verify.'..name,scoped(name)) end
        return resolved
    end
end
