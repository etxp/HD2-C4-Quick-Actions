-- Bounded four-file ring. Full diagnostics must not disable gameplay at 4 MiB.
-- Reuses only the current session's own slots, never unrelated log names.
local M={}
function M.new(open,json,stem,metadata,options)
    options=options or {}
    local max_bytes=options.max_bytes or 4*1024*1024
    local slots=options.slots or 4
    assert(max_bytes>=1024 and slots>=2 and slots<=8,'invalid_log_limits')
    local self={file=nil,bytes=0,segment=0,closed=false}
    local function rotate()
        if self.file then assert(self.file:flush(),'log_flush_failed');assert(self.file:close(),'log_close_failed') end
        self.segment=self.segment+1;self.slot=(self.segment-1)%slots+1
        local name=stem..'_part'..self.slot..'.log'
        self.file=assert(open(name),'log_open_failed');self.name=name;self.bytes=0
        local row=metadata();row.record_type='log_segment';row.session_id=stem
        row.segment=self.segment;row.slot=self.slot;row.retained_slots=slots
        local line=json(row)..'\n';assert(#line<max_bytes,'log_header_limit')
        assert(self.file:write(line),'log_write_failed');self.bytes=#line
        assert(self.file:flush(),'log_flush_failed')
    end
    function self:write(line)
        assert(not self.closed and #line<max_bytes/2,'log_record_limit')
        if not self.file or self.bytes+#line>max_bytes then rotate() end
        assert(self.file:write(line),'log_write_failed');self.bytes=self.bytes+#line
        return true
    end
    function self:flush()
        if self.file and not self.closed then return self.file:flush() end
        return true
    end
    function self:close()
        if self.closed then return true end
        self.closed=true
        if self.file then return self.file:close() end
        return true
    end
    rotate()
    return self
end
return M
