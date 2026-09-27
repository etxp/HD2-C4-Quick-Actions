#!/usr/bin/env python3
"""Assemble the reviewed EXP04 mouse route and restoration-aware input gate."""
import hashlib
import json
from assemble_context import ROOT,replace_once

def assemble():
    layout=json.loads((ROOT/'evidence/mouse-layout.json').read_text())
    modules=[]
    for variable,name in [('ContextReader','context_reader.lua'),('WindowsRead','read_only_windows.lua'),
        ('FireGateWindows','fire_gate_windows.lua'),('WeaponFireGate','weapon_fire_gate.lua'),
        ('MouseRouter','mouse_router.lua'),('ActionReader','action_reader.lua'),
        ('ActionBackend','action_backend.lua'),('NativeActions','native_actions_windows.lua'),
        ('ActionController','action_controller.lua'),('WindowFocus','window_focus.lua')]:
        modules.append('local '+variable+'=(function()\n'+(ROOT/'src'/name).read_text()+'\nend)()\n')
    signatures=','.join('{rva='+str(s['rva'])+',hex="'+s['hex']+'"}' for s in layout['signatures'])
    modules.append('local ActionLayout={module_sha256="'+layout['module_sha256']+'",signatures={'+signatures+'}}\n')
    header,source=(ROOT/'src/c4_probe.lua').read_text().split('\n',1)
    source=replace_once(source,'-- Research probe only: no action invocation, mode writes, input injection,\n-- native pointers, projectile creation, animation events or gameplay hooks.',
        '-- EXP04: physical RMB Deploy / LMB Detonate. Native Fire gate is C4-instance scoped.')
    source=replace_once(source,"version='0.1.0-exp01'","version='0.4.0-exp04'")
    source=replace_once(source,'local file\n','local file,actions,focus,gate,router,cancel_keys\nlocal last_mouse_released=true\n')
    source=replace_once(source,'    if not file or M.disabled then return end','    if not file or M.disabled then return false end')
    source=replace_once(source,'    for k, v in pairs(extra or {}) do row[k] = v end',
        '    if actions then for k,v in pairs(actions.fields(M.elapsed_ms)) do row[k]=v end end\n'
        '    if gate then for k,v in pairs(gate.fields()) do row[k]=v end end\n'
        '    for k, v in pairs(extra or {}) do row[k] = v end')
    source=replace_once(source,"        M.disabled=true; M.status='log_limit'; M.capture=false\n        return",
        "        M.disabled=true; M.status='log_limit'; M.capture=false\n        return false")
    source=replace_once(source,'    M.records=M.records+1; M.bytes=M.bytes+#line',
        "    M.records=M.records+1; M.bytes=M.bytes+#line\n"
        "    if kind=='action_call' or (kind=='fire_gate' and extra and extra.fire_gate_status=='acquire') then\n"
        "        assert(file:flush(),'pre_mutation_log_flush_failed')\n    end\n    return true")
    source=replace_once(source,'local function fail(reason)\n',
        "local function fail(reason)\n    if gate then\n"
        "        local ok,restored,why=pcall(gate.stop)\n"
        "        if not ok or not restored then reason=tostring(reason)..'; restore pending: '..tostring(why or restored) end\n"
        "    end\n")
    source=replace_once(source,"local prefix='C4Boundary_'","local prefix='C4DualInput_'")
    start=source.index('local function tick(dt)\n');end=source.index('\nlocal ok,why=',start)
    source=source[:start]+(ROOT/'src/mouse_tick.lua').read_text()+source[end:]
    source=replace_once(source,"game_build='UNVERIFIED_AT_RUNTIME', action_execution_enabled=false,",
        "game_build='24826606', action_execution_enabled=true, deploy_key='RMB', detonate_key='LMB',")
    source=replace_once(source,'    catalog()\n',
        "    local api=FireGateWindows(WindowsRead())\n"
        "    local backend=ActionBackend.new(api,ActionReader,ContextReader,ActionLayout,NativeActions)\n"
        "    focus=WindowFocus()\n"
        "    actions=ActionController.new(backend,emit,{deploy_input='RMB',detonate_input='LMB'})\n"
        "    gate=WeaponFireGate.new(api,assert(api.module('game.dll')),ContextReader,emit,backend.verify)\n"
        "    router=MouseRouter.new(emit)\n"
        "    emit('layout_verified',{module_sha256=ActionLayout.module_sha256,\n"
        "        action_execution_enabled=true,direct_mode_writes=false,mouse_mapping='RMB_DEPLOY_LMB_DETONATE'})\n"
        "    cancel_keys={}\n"
        "    for _,key in ipairs({'esc','enter','tab','r','m'}) do\n"
        "        cancel_keys[#cancel_keys+1]=device_button(engine.Keyboard,key,key)\n    end\n")
    source=replace_once(source,'''update=function(dt,...)
    if not M.disabled then
        local success,err=pcall(tick,dt)
        if not success then fail(err) end
    end
    return previous_update(dt,...)
end''','''local function after(called,...)
    if not called then
        M.capture=false
        if gate then pcall(gate.stop) end
        error((...),0)
    end
    if not M.disabled then
        local ok,why=pcall(after_update)
        if not ok then fail(why) end
    elseif gate and gate.lease then
        pcall(gate.stop) -- retry restoration after transient read/write failure
    end
    return ...
end
update=function(dt,...)
    if not M.disabled then
        local success,err=pcall(tick,dt)
        if not success then fail(err) end
    end
    return after(pcall(previous_update,dt,...))
end''')
    source=replace_once(source,"shutdown=function(...)\n",
        "shutdown=function(...)\n    if gate then pcall(gate.stop) end\n")
    source=replace_once(source,"print('[C4BoundaryProbe] F6 toggles capture; F7 marks a moment. Log: '..M.log_name)",
        "print('[C4 Dual Input EXP04] F6 enables/disables; RMB Deploy; LMB Detonate; F7 marker. Log: '..M.log_name)")
    result=header+'\n'+''.join(modules)+source
    (ROOT/'src/c4_dual_input.lua').write_text(result)
    return hashlib.sha256(result.encode()).hexdigest()

if __name__=='__main__':print(assemble())
