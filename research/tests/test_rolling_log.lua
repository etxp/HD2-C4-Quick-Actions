local Log=dofile('src/rolling_log.lua')
local function encode(row)
    if row.record_type=='log_segment' then return string.format('{"record_type":"log_segment","segment":%d,"slot":%d}',row.segment,row.slot) end
    return '{}'
end
local function fixture()
    local s={files={},closes=0}
    local function open(name)
        if s.open_failure then return nil end
        local f={data='',closed=false};s.files[name]=f
        function f:write(line) if s.write_failure then return nil end;assert(not self.closed);self.data=self.data..line;return true end
        function f:flush() return not s.flush_failure end
        function f:close() self.closed=true;s.closes=s.closes+1;return true end
        return f
    end
    s.log=Log.new(open,encode,'fixture',function() return {version='MOCK'} end,{max_bytes=1024,slots=4})
    return s
end
local passed=0
local function test(name,f) f();passed=passed+1;print('PASS '..name) end
test('ring log retains at most four bounded files over many rotations',function()
    local s=fixture()
    for _=1,100 do assert(s.log:write(string.rep('x',450)..'\n')) end
    local count=0
    for _,f in pairs(s.files) do count=count+1;assert(#f.data<=1024) end
    assert(count==4 and s.log.segment==50 and s.closes==49)
    assert(s.log:flush() and s.log:close() and s.log:close())
    assert(s.closes==50 and not pcall(s.log.write,s.log,'closed'))
end)
test('rotation fails explicitly on flush, reopen or header write errors',function()
    for _,kind in ipairs({'flush_failure','open_failure','write_failure'}) do
        local s=fixture();s.log:write(string.rep('x',450));s.log:write(string.rep('x',450));s[kind]=true
        assert(not pcall(s.log.write,s.log,string.rep('x',450)))
    end
end)
test('oversized individual records are rejected rather than escaping disk bounds',function()
    local s=fixture();assert(not pcall(s.log.write,s.log,string.rep('x',1024)))
    assert(s.log.segment==1)
end)
print('TOTAL '..passed..' bounded rolling log checks')
