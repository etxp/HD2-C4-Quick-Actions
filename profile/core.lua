-- Diagnostic build only. Counts and times the addon's own work and reports
-- which guarded bytes make a retained snapshot obsolete. It reads the same
-- memory the addon already reads, calls no native game function and writes no
-- game memory. Gameplay code paths are the Off build's, unchanged.
local P=(function()
    local P={labeling=false,labels=nil,line_shift=0,clock_name='os.clock'}
    local clock=os.clock
    do
        local ok,fn=pcall(function()
            local ffi=require('ffi')
            -- Private names, as in src/WinApi.lua: never bound to another mod's prototype.
            ffi.cdef[[int c4qa_QueryPerformanceCounter(int64_t *) __asm__("QueryPerformanceCounter");
                int c4qa_QueryPerformanceFrequency(int64_t *) __asm__("QueryPerformanceFrequency");]]
            local k=ffi.load('kernel32')
            local counter=k.c4qa_QueryPerformanceCounter
            local frequency=k.c4qa_QueryPerformanceFrequency
            local value=ffi.new('int64_t[1]')
            assert(frequency(value)~=0 and value[0]>0)
            local scale=1/tonumber(value[0])
            assert(counter(value)~=0)
            return function() counter(value);return tonumber(value[0])*scale end
        end)
        if ok and type(fn)=='function' then clock=fn;P.clock_name='QueryPerformanceCounter' end
    end
    P.now=clock
    local WINDOW,MAX_REPORTS=30,240
    -- Offline tests shorten the window; the game never sets this global.
    P.window=tonumber(rawget(_G,'C4ProfileWindow'))
    local sections,order={},{}
    local caches,cache_order={},{}
    local reads,bytes,read_time,read_samples=0,0,0,0
    local updates,window_start,reports=0,nil,0
    local overhead=0
    local file,file_failed
    local function section(name)
        local s=sections[name]
        if not s then s={n=0,t=0,max=0};sections[name]=s;order[#order+1]=name end
        return s
    end
    local function finish(s,t,ok,...)
        local d=clock()-t;s.n=s.n+1;s.t=s.t+d;if d>s.max then s.max=d end
        if not ok then error((...),0) end
        return ...
    end
    -- Inclusive time of one function; arguments, results and errors pass through.
    function P.timed(name,fn)
        local s=section(name)
        return function(...) return finish(s,clock(),pcall(fn,...)) end
    end
    function P.add(name,t)
        local s=section(name);local d=clock()-t
        s.n=s.n+1;s.t=s.t+d;if d>s.max then s.max=d end
    end
    function P.methods(object,label,names)
        for _,name in ipairs(names)do
            if type(object[name])=='function' then object[name]=P.timed(label..'.'..name,object[name]) end
        end
        return object
    end
    function P.wrap_api(api)
        P.api=api
        local read=api.read
        api.read=function(at,n)
            reads=reads+1;bytes=bytes+n
            if reads%64==0 then
                local t=clock();local b=read(at,n)
                read_time=read_time+(clock()-t);read_samples=read_samples+1
                return b
            end
            return read(at,n)
        end
        P.raw_read=read
    end
    -- Source position of a guarded read, taken only during a labelled walk.
    local getinfo=type(debug)=='table' and debug.getinfo or nil
    function P.label(g)
        local parts={}
        if getinfo then
            for level=3,6 do
                local info=getinfo(level,'l')
                if not info then break end
                parts[#parts+1]=info.currentline-P.line_shift
            end
        end
        P.labels[#P.labels+1]={at=g.at,n=#g.bytes,lines=parts}
    end
    function P.failed(clusters)P.last_failed=clusters end
    local function hex(s)return (s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
    -- Innermost known source line first, then its callers.
    local function describe(lines)
        local out={}
        for i=1,#lines do
            local text=P.source[lines[i]]
            if text then
                out[#out+1]=text
                if not text:find('^ContextReader') then break end
            end
        end
        if #out==0 then return 'line '..table.concat(lines,'<') end
        return table.concat(out,'  <=  ')
    end
    -- Which guards differ now, by rereading each member of the failed plan.
    local function differences(clusters)
        local found={}
        local read=P.raw_read
        for i=1,#clusters do
            local c=clusters[i]
            for j=1,c.n do
                local g=c[j];local now=read(g.at,#g.bytes)
                if now~=g.bytes then
                    local first,count=nil,0
                    if now then
                        for k=1,#g.bytes do
                            if now:byte(k)~=g.bytes:byte(k) then first=first or k-1;count=count+1 end
                        end
                    end
                    found[#found+1]={at=g.at,n=#g.bytes,index=g.index,first=first,count=count,
                        old=hex(g.bytes:sub(1,32)),new=now and hex(now:sub(1,32)) or 'unreadable'}
                end
            end
        end
        table.sort(found,function(a,b)return a.index<b.index end)
        return found
    end
    function P.cache(name)
        local S={name=name,calls=0,walks=0,checks=0,kept=0,changed=0,unreadable=0,unguarded=0,
            sampled=0,changes={},status={},pending=nil,misses=0}
        caches[name]=S;cache_order[#cache_order+1]=name
        return S
    end
    -- Wrap one SnapshotCache: count its decisions and sample changed guards.
    function P.wrap_cache(new,name)
        return function(fetch)
            local S=P.cache(name)
            local cache=new(function()
                S.walks=S.walks+1
                local labelled=S.pending~=nil
                if labelled then P.labeling=true;P.labels={} end
                local t=clock()
                local ok,row,reason,cap,same=pcall(fetch)
                if labelled then
                    P.labeling=false;overhead=overhead+(clock()-t)
                    local labels,pending=P.labels,S.pending
                    P.labels=nil;S.pending=nil
                    for _,d in ipairs(pending)do
                        local where='guard '..d.index
                        for _,l in ipairs(labels)do
                            if d.at>=l.at and d.at<l.at+l.n then
                                where=describe(l.lines)..' +'..(d.at-l.at+(d.first or 0));break
                            end
                        end
                        local key=where..' len '..d.n
                        local entry=S.changes[key]
                        if not entry then entry={count=0,bytes=0};S.changes[key]=entry end
                        entry.count=entry.count+1;entry.bytes=entry.bytes+d.count
                        entry.old=d.old;entry.new=d.new
                    end
                end
                if not ok then error(row,0) end
                if row and not same then S.unguarded=S.unguarded+1 end
                if same then
                    local inner=same
                    same=function(shared)
                        S.checks=S.checks+1;P.last_failed=nil
                        local fine,result=pcall(inner,shared)
                        if fine and result==true then S.kept=S.kept+1;return true end
                        if fine then S.changed=S.changed+1 else S.unreadable=S.unreadable+1 end
                        S.misses=S.misses+1
                        -- Sample: the first few of each window, then one in sixteen.
                        if P.last_failed and not S.pending and (S.sampled<8 or S.misses%16==0) and S.sampled<48 then
                            local t0=clock()
                            local found=differences(P.last_failed)
                            if #found>0 then
                                S.sampled=S.sampled+1
                                -- Keep the earliest few; the walk that follows labels them.
                                for k=#found,5,-1 do found[k]=nil end
                                S.pending=found
                            end
                            overhead=overhead+(clock()-t0)
                        end
                        if not fine then error(result,0) end
                        return result
                    end
                end
                return row,reason,cap,same
            end)
            local snapshot=cache.snapshot
            cache.snapshot=function()
                S.calls=S.calls+1
                local row,reason,cap=snapshot()
                local status=row and (row.context_status..(row.action_context_status=='rejected' and '/rejected' or ''))
                    or ('nil:'..tostring(reason))
                S.status[status]=(S.status[status] or 0)+1
                S.last_row=row;S.last_cap=cap
                return row,reason,cap
            end
            return cache
        end
    end
    local function open()
        if file or file_failed then return file end
        local loader=rawget(_G,'CowboyBingusModLoader')
        local ok,handle=pcall(function()return loader.open_log('C4QuickActionsProfile.log')end)
        if ok and handle then file=handle else file_failed=true end
        return file
    end
    local function sorted(t,by)
        local keys={};for k in pairs(t)do keys[#keys+1]=k end
        table.sort(keys,by or function(a,b)return tostring(a)<tostring(b)end)
        return keys
    end
    local function report(now,M)
        local span=now-window_start
        local lines={}
        local function out(...)lines[#lines+1]=string.format(...)end
        reports=reports+1
        out('== C4 profile %s report %d: %.1f s, %d updates (%.1f/s), clock %s, status %s ==',
            tostring(M and M.version),reports,span,updates,updates/span,P.clock_name,tostring(M and M.status))
        out('reads: %.1f per update, %.0f bytes per update, sampled cost %.3f us per read',
            reads/updates,bytes/updates,read_samples>0 and read_time/read_samples*1e6 or 0)
        out('%-34s %9s %9s %10s %9s','section (inclusive)','calls/upd','ms/s','us/update','max us')
        for _,name in ipairs(order)do
            local s=sections[name]
            if s.n>0 then
                out('%-34s %9.2f %9.3f %10.2f %9.0f',name,s.n/updates,s.t*1000/span,s.t*1e6/updates,s.max*1e6)
            end
        end
        for _,name in ipairs(cache_order)do
            local S=caches[name]
            out('cache %s: calls %d, shared in phase %d, guards reread %d (kept %d, changed %d, unreadable %d), walks %d, walks without checker %d',
                name,S.calls,S.calls-S.walks-S.kept,S.checks,S.kept,S.changed,S.unreadable,S.walks,S.unguarded)
            for _,status in ipairs(sorted(S.status))do out('  context %s: %d',status,S.status[status])end
            local keys=sorted(S.changes,function(a,b)return S.changes[a].count>S.changes[b].count end)
            if #keys>0 then out('  changed guards in %d sampled misses (count, average bytes changed, place):',S.sampled)end
            for i=1,math.min(#keys,12)do
                local e=S.changes[keys[i]]
                out('  %4d  %5.1f  %s',e.count,e.bytes/e.count,keys[i])
                out('              last old %s',e.old);out('              last new %s',e.new)
            end
        end
        out('profile overhead inside the timed sections: %.3f ms/s; Lua heap %.0f KiB',
            overhead*1000/span,collectgarbage('count'))
        if P.capture then
            local ok,why=pcall(P.capture,out,caches)
            if not ok then out('capture: error %s',tostring(why)) end
        end
        local handle=open()
        if handle and reports<=MAX_REPORTS then
            pcall(function()handle:write(table.concat(lines,'\n')..'\n');handle:flush()end)
        end
        P.last_report=lines
        for _,name in ipairs(order)do local s=sections[name];s.n=0;s.t=0;s.max=0 end
        for _,name in ipairs(cache_order)do
            local S=caches[name]
            S.calls=0;S.walks=0;S.checks=0;S.kept=0;S.changed=0;S.unreadable=0;S.unguarded=0
            S.sampled=0;S.changes={};S.status={};S.misses=0
        end
        reads,bytes,read_time,read_samples,updates,overhead=0,0,0,0,0,0
        window_start=now
    end
    -- Called once per update, after the addon's own work.
    function P.frame(M)
        updates=updates+1
        local now=clock()
        if not window_start then window_start=now;updates=0;return end
        if now-window_start>=(P.window or WINDOW) then pcall(report,now,M) end
    end
    return P
end)()
