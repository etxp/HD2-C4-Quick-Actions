-- Compare pure identity/descriptor encodings with canonical byte formatting.
local R=dofile('private/tests/mock_symbols.lua')
local D=dofile('private/tests/mock_fields.lua')
local reader=dofile('private/tests/modules/context_reader.lua')(R,D)
local fixture=dofile('tests/context_fixture.lua')()
local helpers
local row,why,cap=reader.avatar_snapshot(fixture.api,fixture.game,function(e)
    helpers={hex=e.hex,resource=e.resource}
    return {same=e.checked}
end)
assert(row and not why and cap and cap.same())
local function oracle(bytes,reverse)
    local out={}
    for i=1,#bytes do
        out[i]=string.format('%02x',bytes:byte(reverse and #bytes+1-i or i))
    end
    return table.concat(out)
end
local function check(name,fn)fn();print('PASS '..name)end
check('binary encodings preserve empty and every trailing-byte width',function()
    for n=0,19 do
        local b={};for i=1,n do b[i]=string.char((i*193)%256)end
        local bytes=table.concat(b)
        assert(helpers.hex(bytes)==oracle(bytes))
    end
end)
check('binary encodings preserve all byte values including NUL and high bits',function()
    local b={};for n=0,255 do b[#b+1]=string.char(n)end
    local bytes=table.concat(b)
    assert(helpers.hex(bytes)==oracle(bytes))
    assert(helpers.hex(bytes:reverse())==oracle(bytes:reverse()))
end)
check('resource IDs preserve both unsigned word boundaries and byte order',function()
    for _,bytes in ipairs({string.rep('\0',8),string.rep('\255',8),
        '\0\0\0\128\255\255\255\127',
        '\255\255\255\127\0\0\0\128',
        '\1\2\3\4\128\129\254\255'})do
        assert(helpers.resource(bytes)==oracle(bytes,true))
        assert(helpers.resource(bytes..'trailing')==oracle(bytes,true))
    end
end)
check('seeded binary encoding differential preserves identity and descriptors',function()
    math.randomseed(1002)
    for _=1,1000 do
        local b={};for i=1,math.random(0,512)do b[i]=string.char(math.random(0,255))end
        local bytes=table.concat(b)
        assert(helpers.hex(bytes)==oracle(bytes))
        if #bytes>=8 then assert(helpers.resource(bytes)==oracle(bytes:sub(1,8),true))end
    end
end)
