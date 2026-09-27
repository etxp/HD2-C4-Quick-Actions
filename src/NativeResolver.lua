-- Resolve native code and RIP-relative globals from the loaded module.
-- No build number, filename hash, known image base, or address allowlist.
local M={}
local bit=require('bit')
local function u16(b,o) local a,c=b:byte(o+1,o+2);return a+c*256 end
local function u32(b,o) local a,c,d,e=b:byte(o+1,o+4);return a+c*256+d*65536+e*16777216 end
local function i32(b,o) local n=u32(b,o);return n>=0x80000000 and n-4294967296 or n end
local function unhex(h) return (h:gsub('..',function(x)return string.char(tonumber(x,16))end)) end
local function compile(s)
    local raw,mask=unhex(s.hex),unhex(s.mask)
    assert(#raw==#mask and #raw>0 and #raw<=32768,'compat_pattern_size:'..s.name)
    local anchor,offset='',0
    local i=1
    while i<=#mask do
        if mask:byte(i)==255 then
            local first=i
            repeat i=i+1 until i>#mask or mask:byte(i)~=255
            if i-first>#anchor then anchor=raw:sub(first,i-1);offset=first-1 end
        else assert(mask:byte(i)==0,'compat_bad_mask');i=i+1 end
    end
    assert(#anchor>=8 or s.from_symbol,'compat_weak_pattern:'..s.name)
    local spans={};i=1
    while i<=#mask do
        if mask:byte(i)==255 then
            local first=i
            repeat i=i+1 until i>#mask or mask:byte(i)~=255
            spans[#spans+1]={first,raw:sub(first,i-1)}
        else i=i+1 end
    end
    return {raw=raw,mask=mask,anchor=anchor,offset=offset,spans=spans}
end
local function matches(data,at,p)
    if at<1 or at+#p.raw-1>#data then return false end
    for _,s in ipairs(p.spans) do
        if data:sub(at+s[1]-1,at+s[1]+#s[2]-2)~=s[2] then return false end
    end
    return true
end
function M.resolve(api,game,catalog)
    local function read(rva,n)
        assert(rva>=0 and n>0 and rva+n<=0x10000000,'compat_read_bounds')
        local parts={}
        for at=0,n-1,4096 do
            local count=math.min(4096,n-at)
            local b=assert(api.read(game+rva+at,count),'compat_read_unavailable:'..string.format('%x',rva+at))
            assert(#b==count,'compat_short_read');parts[#parts+1]=b
        end
        return table.concat(parts)
    end
    local dos=read(0,64);assert(dos:sub(1,2)=='MZ','compat_dos_header')
    local nt=u32(dos,60);assert(nt>=64 and nt<=0x100000,'compat_pe_offset')
    local head=read(nt,24);assert(head:sub(1,4)=='PE\0\0' and u16(head,4)==0x8664,'compat_pe_x64')
    local count,optional=u16(head,6),u16(head,20)
    assert(count>0 and count<=32 and optional>=112 and optional<=512,'compat_pe_sections')
    local opt=read(nt+24,optional);assert(u16(opt,0)==0x20b,'compat_pe64')
    local image_size=u32(opt,56);assert(image_size>0 and image_size<=0x10000000,'compat_image_size')
    local table_bytes=read(nt+24+optional,count*40)
    local sections,code,total={},{},0
    for i=0,count-1 do
        local o=i*40;local size,rva,flags=u32(table_bytes,o+8),u32(table_bytes,o+12),u32(table_bytes,o+36)
        if size>0 then
            assert(rva>=4096 and rva+size<=image_size,'compat_section_bounds')
            local writable=bit.band(flags,0x80000000)~=0
            local executable=bit.band(flags,0x20000000)~=0
            local s={rva=rva,size=size,region=writable and 'writable' or executable and 'code' or 'readonly'}
            sections[#sections+1]=s
            -- Packed modules also contain executable data/unpacking sections.
            -- Scan ordinary, non-writable machine-code sections only.
            if executable and not writable and bit.band(flags,0x60)==0x20 then
                total=total+size;assert(total<=64*1024*1024,'compat_scan_budget')
                code[#code+1]={section=s,data=read(rva,size)}
            end
        end
    end
    assert(#code>0,'compat_no_code')
    table.sort(sections,function(a,b)return a.rva<b.rva end)
    for i=2,#sections do assert(sections[i-1].rva+sections[i-1].size<=sections[i].rva,'compat_overlapping_sections') end
    local function region(rva,n)
        if rva==0 then return 'base' end
        for _,s in ipairs(sections) do if rva>=s.rva and rva+n<=s.rva+s.size then return s.region end end
        return 'outside'
    end
    local symbols,guards,observed={},{},{}
    local vehicle_tables,seat_guards={},{}
    local function symbol(name,value)
        assert(not symbols[name] or symbols[name]==value,'compat_reference_conflict:'..name)
        symbols[name]=value
    end
    local function guard(at,n,label)
        assert(region(at,n)~='outside' or at==0,'compat_guard_bounds:'..label)
        local bytes=read(at,n);guards[#guards+1]={at=at,bytes=bytes,label=label};return bytes
    end
    -- Resolve every independent symbol before checking cross-references.
    for _,s in ipairs(catalog.nodes) do
        local p=compile(s);local hits={}
        if s.from_symbol then
            local parent=assert(symbols[s.from_symbol],'compat_parent_missing:'..s.name)
            local at=parent+s.from_offset
            hits[1]=at+4+i32(read(at,4),0)
            assert(region(hits[1],#p.raw)=='code','compat_derived_target:'..s.name)
            assert(matches(read(hits[1],#p.raw),1,p),'compat_signature_missing:'..s.name)
        else
            for _,c in ipairs(code) do
                local start=1
                while true do
                    local at=c.data:find(p.anchor,start,true)
                    if not at then break end
                    local candidate=at-p.offset
                    if matches(c.data,candidate,p) then hits[#hits+1]=c.section.rva+candidate-1 end
                    assert(#hits<=1,'compat_signature_ambiguous:'..s.name)
                    start=at+1
                end
            end
            assert(#hits==1,'compat_signature_missing:'..s.name)
        end
        symbol(s.name,hits[1]);observed[s.name]=guard(hits[1],#p.raw,s.name)
    end
    code=nil -- discard the scan buffers after resolving
    for _,s in ipairs(catalog.nodes) do
        local at,bytes=symbols[s.name],observed[s.name]
        for _,r in ipairs(s.refs or {}) do
            local target=at+r['end']+i32(bytes,r.at)
            if r.guard_bytes then
                assert(r.region=='readonly' and not r.hex and r.guard_bytes==8,
                    'compat_invalid_runtime_pointer_guard:'..s.name)
            end
            assert(region(target,r.hex and #r.hex/2 or r.guard_bytes or r.region=='writable' and 8 or 1)==r.region,
                'compat_reference_region:'..s.name)
            if r.symbol then symbol(r.symbol,target) end
            if r.relative then assert(target==at+r.relative,'compat_internal_branch:'..s.name) end
            if r.hex then assert(guard(target,#r.hex/2,s.name..':literal')==unhex(r.hex),'compat_literal_changed:'..s.name) end
            -- Absolute pointer tables are relocated by the OS at startup.
            -- Verify their section and retain this process's bytes for later
            -- mutation checks, never compare with a prior process's address.
            if r.guard_bytes then guard(target,r.guard_bytes,s.name..':runtime_pointer') end
        end
        for _,t in ipairs(s.tables or {}) do
            local target=u32(bytes,t.operand)
            assert(region(target,#t.entries*4)=='code','compat_switch_table_region:'..s.name)
            local entries=guard(target,#t.entries*4,s.name..':switch_table')
            for i,relative in ipairs(t.entries) do
                assert(u32(entries,(i-1)*4)==at+relative,'compat_switch_table_changed:'..s.name)
            end
        end
        if s.abilities then
            local a=s.abilities;local table_at=u32(bytes,a.operand)
            local capacity=u32(bytes,a.capacity_offset)+1
            assert(capacity>=521 and capacity<=16384,'compat_ability_capacity')
            for _,t in ipairs(a.targets) do
                local entry_at=table_at+(t.id-1)*4
                assert(region(entry_at,4)=='code','compat_ability_table_region')
                local case_at=u32(guard(entry_at,4,'ability_case_entry'),0)
                assert(region(case_at,#a.case_hex/2)=='code','compat_ability_case_region')
                local body=guard(case_at,#a.case_hex/2,'ability_case_'..t.id)
                assert(matches(body,1,compile{name='ability_case',hex=a.case_hex,mask=a.case_mask}),
                    'compat_ability_case_changed:'..t.id)
                assert(case_at+a.call_end+i32(body,a.call_offset)==symbols[t.symbol],
                    'compat_ability_dispatch_changed:'..t.id)
            end
        end
        if s.vehicle_dispatch then
            local d=s.vehicle_dispatch
            -- Read the engine's current switch capacity, not a model allowlist.
            local capacity=bytes:byte(d.capacity_offset+1)+1
            assert(capacity<=128,'compat_vehicle_switch_encoding')
            local table_at=u32(bytes,d.table_offset)
            assert(region(table_at,capacity*4)=='code','compat_vehicle_table')
            local entries=guard(table_at,capacity*4,'vehicle_case_entries')
            local pattern=compile{name='vehicle_case',hex=d.case_hex,mask=d.case_mask}
            for config=1,capacity do
                local case_at=u32(entries,(config-1)*4)
                assert(region(case_at,#pattern.raw)=='code','compat_vehicle_case_target')
                local body=guard(case_at,#pattern.raw,'vehicle_case_'..config)
                assert(matches(body,1,pattern),'compat_vehicle_case')
                local tables={}
                for _,key in ipairs({'out','in'}) do
                    local value=u32(body,d[key..'_offset'])
                    assert(region(value,4)=='readonly','compat_vehicle_animation_region')
                    tables[key]=value
                end
                vehicle_tables[config]=tables
            end
        end
    end
    for _,name in ipairs(catalog.required_globals) do assert(symbols[name],'compat_global_missing:'..name) end
    local self={symbols=symbols,fields=catalog.fields,node_count=#catalog.nodes,scan_bytes=total}
    function self.verify()
        for _,g in ipairs(guards) do
            assert(read(g.at,#g.bytes)==g.bytes,'compat_live_code_changed:'..g.label)
        end
    end
    function self.vehicle_lean_available(config,seat)
        local tables=vehicle_tables[config]
        if not tables then return false,'native_vehicle_has_no_lean' end
        -- The seat originates from the checked local avatar relation. Resolve
        -- its animation from the engine's data instead of expecting fixed IDs.
        local supported=true
        for _,key in ipairs({'out','in'}) do
            local at=tables[key]+seat*4
            assert(region(at,4)=='readonly','compat_vehicle_seat_region')
            if not seat_guards[at] then
                seat_guards[at]=guard(at,4,'vehicle_seat_animation')
            end
            assert(read(at,4)==seat_guards[at],'compat_vehicle_seat_changed')
            if i32(seat_guards[at],0)<0 then supported=false end
        end
        if not supported then return false,'native_seat_has_no_lean' end
        return true
    end
    self.verify() -- close scan/read races before exposing native addresses
    return self
end
return M
