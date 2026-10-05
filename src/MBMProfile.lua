-- Read MBM v2's persisted automatic assignments. Never change bindings/files.
local M={}
local OURS={['etxp.c4_quick_actions.deploy']='deploy',['etxp.c4_quick_actions.detonate']='detonate'}
-- One record per line, as Mod Bindings Menu reads it:
--   v2.1:            <id>\t<group>\t<action>
--   v2.2 (format 2): format 2 / session <n> / <id>\t<group>\t<action>\t<seen>
--                    / action <group>:<action> ... / end
-- A format 2 file without its closing "end" is incomplete and not used.
function M.parse(text)
    assert(type(text)=='string' and #text<=65536,'mbm_assignments_size')
    local result,format,complete={},nil,false
    for line in text:gmatch('[^\r\n]+') do
        local id,group,action=line:match('^([^\t]+)\t(%d+)\t(%d+)\t?%d*$')
        local key=id and OURS[id]
        if key then
            local g,a=tonumber(group),tonumber(action)
            assert(g>=9 and g<=12 and a>=0 and a<97,'mbm_assignment_range')
            assert(not result[key],'mbm_duplicate_assignment')
            result[key]=g*65536+a
        elseif line=='end' then complete=true
        elseif not id then
            local name,value=line:match('^(%a+) (%d+)$')
            if name=='format' then format=tonumber(value) end
        end
    end
    assert(not format or complete,'mbm_assignments_incomplete')
    assert(result.deploy and result.detonate and result.deploy~=result.detonate,'mbm_assignments_missing')
    return result
end
-- A binding's native action changes only when the menu assigns it, at
-- registration, and the menu then saves the file. The file is replaced through
-- a temporary file in v2.2, so it can be missing for an instant: a missing or
-- unusable file keeps the codes last read rather than dropping them.
function M.new(loader)
    local codes,next_read=nil,0
    return function(now)
        if now<next_read then return codes end
        next_read=now+1000
        local directory=loader.log_directory
        if type(directory)~='string' or directory=='' then
            local localdata=os.getenv('LOCALAPPDATA')
            if not localdata then return codes end
            directory=localdata..'/CowboyBingus/Helldivers2'
        end
        local file=io.open(directory..'/ModBindingsMenu.assignments','rb')
        if not file then return codes end
        local value=file:read(65537);file:close()
        local ok,result=pcall(M.parse,value)
        if ok then codes=result end
        return codes
    end
end
return M
