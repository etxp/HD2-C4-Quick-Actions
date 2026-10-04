local decode=dofile('src/PointerValue.lua').decode
local ffi=require('ffi')
local function check(name,fn)fn();print('PASS '..name)end
local function pack(value)
    local b={};for i=1,8 do b[i]=string.char(value%256);value=math.floor(value/256)end
    return table.concat(b)
end
local function previous(bytes)
    if not bytes or #bytes<8 then return nil end
    local p=ffi.new('uint64_t[1]');ffi.copy(p,bytes,8)
    if p[0]>=65536 and p[0]<0x800000000000 then return tonumber(p[0])end
end
check('pointer decoder retains minimum and exclusive upper address bounds',function()
    assert(decode(pack(65535))==nil and decode(pack(65536))==65536)
    assert(decode(pack(0x7fffffffffff))==0x7fffffffffff)
    assert(decode(pack(0x800000000000))==nil)
    assert(decode(string.rep('\255',8))==nil)
end)
check('pointer decoder accepts copied prefixes and rejects missing bytes',function()
    assert(decode(nil)==nil)
    for n=0,7 do assert(decode(string.rep('\255',n))==nil)end
    assert(decode(pack(0x7fffffff1234)..'extra')==0x7fffffff1234)
end)
check('pointer decoder matches prior uint64 FFI conversion across seeded bytes',function()
    math.randomseed(1003)
    for _=1,10000 do
        local b={};for i=1,8 do b[i]=string.char(math.random(0,255))end
        local bytes=table.concat(b);assert(decode(bytes)==previous(bytes))
        local address=math.random(0,32767)*4294967296+math.random(0,65535)*65536+math.random(0,65535)
        assert(decode(pack(address))==previous(pack(address)))
    end
end)
