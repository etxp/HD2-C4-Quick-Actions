local fixture=dofile('tests/contact_fixture.lua')
local function setup(observe)
 local s=fixture();local f=assert(io.open('src/ModeLabels.lua'));local text=f:read('*a');f:close()
 local mod=assert(loadstring('return function(D) local GuardSpans=dofile("src/GuardSpans.lua") '..text..' end'))()(s.D)
 local count=0;s.writes=0;s.verifications=0;s.original=s.api.read(s.templates+288,88)
 s.writer={text=function(text)count=count+1;return {bytes=string.char(count)..string.rep('\0',7),text=text}end,
 exchange=function(at,expected,value)
  s.writes=s.writes+1
  if s.fail_write==s.writes then return false end
  assert(s.api.read(at,#expected)==expected);s.put(at,value)
  if s.after_write then s.after_write(at,expected,value)end
  return true
 end}
 s.labels=mod.new(s.api,s.game,s.base,s.symbols,function()
  s.verifications=s.verifications+1;assert(not s.bad_code,'bad code')
  if s.after_verify then s.after_verify()end
 end,s.writer,function(kind,row)
  local accepted=s.emit(kind,row)
  if s.after_emit then s.after_emit(kind,row)end
  return accepted
 end,observe)
 local read=s.api.read;s.reads=0
 s.api.read=function(at,n)s.reads=s.reads+1;return read(at,n)end
 return s
end
local function test(name,fn)fn();print('PASS '..name)end
test('cosmetic mode labels preserve native actions and restore exact original descriptor',function()
 local s=setup();assert(s.labels.sync(true));assert(not s.labels.failed)
 local row,why,cap=s.snap();assert(cap,tostring(why));assert(row.detonation_mode=='MANUAL')
 s.mode('CONTACT');row,why,cap=s.snap();assert(cap and row.detonation_mode=='CONTACT',tostring(why))
 local n=s.writes;s.labels.sync(true);assert(s.writes==n)
 assert(s.labels.stop());assert(s.api.read(s.templates+288,88)==s.original)
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,16)==string.rep('\0',16))
end)
test('changed ability ID stays rejected even with cosmetic labels installed',function()
 local s=setup();assert(s.labels.sync(true));s.u32(s.templates+288,999)
 local row,why,cap=s.snap();assert(not cap);assert(s.labels.stop());assert(s.base.u32(s.api.read(s.templates+288,4),0)==999)
end)
test('foreign cache slots are never overwritten and partial installation is restored',function()
 local s=setup();local at=s.game+s.symbols.global_contact_contact_label;s.ptr(at,0x999999)
 assert(not s.labels.sync(true));assert(s.labels.failed);assert(s.api.pointer(s.api.read(at,8))==0x999999)
 assert(s.api.read(s.templates+288,88)==s.original)
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,8)==string.rep('\0',8))
end)
test('every partial write failure restores owned labels and cache pointers',function()
 for i=1,4 do local s=setup();s.fail_write=i;assert(not s.labels.sync(true));assert(s.labels.stop())
 assert(s.api.read(s.templates+288,88)==s.original)
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,16)==string.rep('\0',16)) end
end)
test('restoration retries a failed write without losing the lease',function()
 local s=setup();assert(s.labels.sync(true));s.fail_write=5;assert(not s.labels.stop());assert(s.labels.lease)
 assert(s.labels.stop());assert(s.api.read(s.templates+288,88)==s.original)
end)
test('label takeover is preserved during cleanup',function()
 local s=setup();assert(s.labels.sync(true));s.u32(s.templates+288+16,12345)
 assert(not s.labels.sync(true));assert(s.base.u32(s.api.read(s.templates+304,4),0)==12345)
end)
test('stale world template is not written during cleanup',function()
 local s=setup();assert(s.labels.sync(true));local n=s.writes;s.ptr(s.owner+s.D.ability_templates,0xdead0000)
 assert(s.labels.stop());assert(s.writes==n+2)
end)
test('changed native code blocks all cosmetic writes',function()
 local s=setup();s.bad_code=true;assert(not s.labels.sync(true));assert(s.writes==0)
end)
test('log failure prevents label installation',function()
 local s=setup();s.log_failure=true;assert(not s.labels.sync(true));assert(s.writes==0)
end)
test('boot managers unavailable waits and installs labels after C4 becomes available',function()
 local s=setup();local R=dofile('private/tests/mock_symbols.lua');local saved=s.api.read(s.game+R.global_mode,8)
 s.zero(s.game+R.global_mode,8)
 for _=1,4 do assert(s.labels.sync(true));assert(not s.labels.failed and s.writes==0)end
 s.put(s.game+R.global_mode,saved);assert(s.labels.sync(true));assert(s.labels.lease and s.writes==4)
 assert(s.labels.stop());assert(s.api.read(s.templates+288,88)==s.original)
end)
test('mission context without selected C4 waits without latching label failure',function()
 local s=setup();local old=s.api.read(s.state+0x1c,4);s.u32(s.state+0x1c,0)
 assert(s.labels.sync(true));assert(not s.labels.failed and s.writes==0)
 s.put(s.state+0x1c,old);assert(s.labels.sync(true));assert(s.labels.lease and s.writes==4)
end)

test('unchanged label maintenance reads ownership without repeating full code verification',function()
 local s=setup();assert(s.labels.sync(true));assert(s.verifications==4)
 for _=1,100 do assert(s.labels.sync(true))end
 assert(s.verifications==4 and s.writes==4)
 assert(s.labels.stop());assert(s.verifications==4)
end)
test('missing label cache requires fresh full verification before repair',function()
 local s=setup();assert(s.labels.sync(true));assert(s.verifications==4)
 s.zero(s.game+s.symbols.global_contact_manual_label,8);s.bad_code=true
 assert(not s.labels.sync(true));assert(s.verifications==5)
 -- Failure may restore owned data, but cannot reinstall the missing cache slot.
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,8)==string.rep('\0',8))
 assert(s.api.read(s.templates+288,88)==s.original)
end)
test('healthy cache and descriptor repairs each verify immediately before writing',function()
 local s=setup();assert(s.labels.sync(true));local n=s.writes
 s.zero(s.game+s.symbols.global_contact_manual_label,8)
 assert(s.labels.sync(true));assert(s.writes==n+1 and s.verifications==5)
 s.put(s.templates+304,s.original:sub(17,20))
 assert(s.labels.sync(true));assert(s.writes==n+2 and s.verifications==6)
end)
test('waiting for an equipped C4 performs no full code verification',function()
 local s=setup();s.u32(s.state+0x1c,0)
 for _=1,100 do assert(s.labels.sync(true))end
 assert(s.verifications==0 and s.writes==0 and not s.labels.failed)
end)
test('code changed by the pre-install callback prevents every installation write',function()
 local s=setup();s.after_emit=function(kind)if kind=='mode_labels_call'then s.bad_code=true end end
 assert(not s.labels.sync(true));assert(s.verifications==1 and s.writes==0)
 assert(s.api.read(s.templates+288,88)==s.original)
end)
test('code changing between partial writes blocks the next write and restores owned data',function()
 local s=setup();s.after_write=function()if s.writes==1 then s.bad_code=true end end
 assert(not s.labels.sync(true));assert(s.verifications==2 and s.writes==2)
 -- The second exchange is cleanup of the first cache pointer, not installation.
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,16)==string.rep('\0',16))
 assert(s.api.read(s.templates+288,88)==s.original)
end)
test('changed template identity during verification prevents installation into an old world',function()
 local s=setup();s.after_verify=function()s.ptr(s.owner+s.D.ability_templates,0xdead0000)end
 assert(not s.labels.sync(true));assert(s.verifications==1 and s.writes==0)
 assert(s.api.read(s.templates+288,88)==s.original)
end)
test('later native code failure cannot prevent restoring owned cosmetic data',function()
 local s=setup();assert(s.labels.sync(true));s.bad_code=true
 assert(s.labels.stop());assert(s.verifications==4)
 assert(s.api.read(s.templates+288,88)==s.original)
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,16)==string.rep('\0',16))
end)
test('steady maintenance still compares every byte it depends on, with fewer reads',function()
 local s=setup();assert(s.labels.sync(true))
 s.reads=0;assert(s.labels.sync(true));local recorded=s.reads
 s.reads=0;assert(s.labels.sync(true));local steady=s.reads
 assert(steady>0 and steady<recorded,'steady pass did not coalesce its reads')
 for _=1,20 do s.reads=0;assert(s.labels.sync(true) and s.reads==steady)end
 print(string.format('MEASURE mode label maintenance reads: recorded pass=%d steady=%d',recorded,steady))
 -- A cleared cache slot is reinstalled on the very next pass.
 local n=s.writes;s.zero(s.game+s.symbols.global_contact_manual_label,8)
 assert(s.labels.sync(true) and s.writes==n+1)
 -- A label field changed by someone else is noticed and left alone.
 assert(s.labels.sync(true));assert(s.labels.sync(true))
 s.u32(s.templates+288+16,12345);assert(not s.labels.sync(true) and s.labels.failed)
 assert(s.base.u32(s.api.read(s.templates+304,4),0)==12345)
end)
test('steady maintenance notices a replaced world, template table and template key',function()
 for _,change in ipairs({
  function(s)s.ptr(s.game+s.symbols.global_contact_owner,0x66660000)end,
  function(s)s.ptr(s.owner+s.D.ability_templates,0xdead0000)end,
  function(s)s.u32(s.templates+11*16+8,1)end})do
  local s=setup();for _=1,3 do assert(s.labels.sync(true))end
  local lease=s.labels.lease;assert(lease);change(s);s.labels.sync(true)
  assert(s.labels.lease~=lease,'stale label lease survived')
 end
end)
test('disabling or stopping never trusts the steady record',function()
 local s=setup();for _=1,3 do assert(s.labels.sync(true))end
 assert(s.labels.sync(false));assert(not s.labels.lease)
 assert(s.api.read(s.templates+288,88)==s.original)
 assert(s.api.read(s.game+s.symbols.global_contact_manual_label,16)==string.rep('\0',16))
 assert(s.labels.sync(true) and s.labels.lease,'labels did not return after re-enable')
end)
test('positive evidence of another context skips the template walk; unknown evidence does not',function()
 local row={context_status='selected_weapon_observed'}
 local s=setup(function()return row end)
 s.reads=0;for _=1,5 do assert(s.labels.sync(true))end
 assert(s.reads==0 and not s.labels.lease and s.writes==0,'template walked without a selected C4')
 row={context_status='c4_context_observed'};assert(s.labels.sync(true) and s.labels.lease and s.writes==4)
 for _,unknown in ipairs({function()return nil,'context_changed_during_read'end,function()error('unavailable')end})do
  local u=setup(unknown);assert(u.labels.sync(true) and u.labels.lease and u.writes==4)
 end
end)
