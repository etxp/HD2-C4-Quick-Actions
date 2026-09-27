-- Read MBM v2's persisted automatic assignments. Never change bindings/files.
local M={}
function M.parse(text)
    assert(type(text)=='string' and #text<=65536,'mbm_assignments_size')
    local result={}
    for id,group,action in text:gmatch('([^\t\r\n]+)\t(%d+)\t(%d+)') do
        if id=='etxp.c4_quick_actions.deploy' or id=='etxp.c4_quick_actions.detonate' then
            local g,a=tonumber(group),tonumber(action)
            assert(g>=9 and g<=12 and a>=0 and a<97,'mbm_assignment_range')
            local key=id:match('%.([^%.]+)$');assert(not result[key],'mbm_duplicate_assignment')
            result[key]=g*65536+a
        end
    end
    assert(result.deploy and result.detonate and result.deploy~=result.detonate,'mbm_assignments_missing')
    return result
end
function M.new(loader)
    local codes,next_read=nil,0
    return function(now)
        if now<next_read then return codes end
        next_read=now+1000;codes=nil
        local directory=loader.log_directory
        if type(directory)~='string' or directory=='' then
            local localdata=os.getenv('LOCALAPPDATA')
            if not localdata then return nil end
            directory=localdata..'/CowboyBingus/Helldivers2'
        end
        local file=io.open(directory..'/ModBindingsMenu.assignments','rb')
        if not file then return nil end
        local value=file:read(65537);file:close()
        local ok,result=pcall(M.parse,value)
        if ok then codes=result end
        return codes
    end
end
return M
