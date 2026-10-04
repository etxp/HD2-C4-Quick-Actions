-- Decoder-only incremental benchmark: same lean decoder with and without a
-- known-unit filter. Does not include native reads, stream stability copying,
-- the controller, engine scheduling, or FPS. GC-stopped numbers are allocated
-- bytes during the run, not retained/live heap.
local E=dofile('src/CollisionEvents.lua')
local function pack(n)
    local out={};for i=1,4 do out[i]=string.char(n%256);n=math.floor(n/256)end
    return table.concat(out)
end
local function collision(a,b)
    return pack(52)..pack(E.contact_type)..pack(0)..pack(11)..pack(12)..pack(a)..pack(b)..string.rep('\0',32)
end
for _,count in ipairs({0,128,1024,4096})do
    for _,matches in ipairs(count==0 and {0} or {0,1})do
        local records={}
        for i=1,count do records[i]=collision(10000+i,matches==1 and i==count and 42 or 20000+i)end
        local bytes=table.concat(records)
        for _,filtered in ipairs(arg[1]=='reverse' and {true,false} or {false,true})do
            local units=filtered and {[42]=true} or nil
            local expected=filtered and matches or count
            for _=1,100 do assert(#E.decode(bytes,false,units).contacts==expected)end
            collectgarbage('collect');collectgarbage('stop')
            local kb=collectgarbage('count');local start=os.clock();local total=0
            for _=1,128 do
                local result=E.decode(bytes,false,units)
                assert(result.records==count);total=total+#result.contacts
            end
            local elapsed=os.clock()-start;local allocated=collectgarbage('count')-kb
            collectgarbage('restart');assert(total==expected*128)
            print(string.format('{"records":%d,"matching_records":%d,"filtered":%s,"decodes":128,"decode_ms":%.6f,"allocation_KiB_per_decode":%.3f}',
                count,matches,tostring(filtered),elapsed*1000/128,allocated/128))
        end
    end
end
