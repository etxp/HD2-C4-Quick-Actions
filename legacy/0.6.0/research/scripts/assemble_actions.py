#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Build EXP03 from the tested input shell and separately testable action modules."""
import hashlib
import json
from assemble_context import ROOT,replace_once

def assemble():
    layout=json.loads((ROOT/'evidence/action-layout.json').read_text())
    modules=[]
    for variable,file in [('ContextReader','context_reader.lua'),('WindowsRead','read_only_windows.lua'),
        ('ActionReader','action_reader.lua'),('ActionBackend','action_backend.lua'),
        ('NativeActions','native_actions_windows.lua'),('ActionController','action_controller.lua'),
        ('WindowFocus','window_focus.lua')]:
        modules.append('local '+variable+'=(function()\n'+(ROOT/'src'/file).read_text()+'\nend)()\n')
    signatures=','.join('{rva='+str(s['rva'])+',hex="'+s['hex']+'"}' for s in layout['signatures'])
    modules.append('local ActionLayout={module_sha256="'+layout['module_sha256']+'",signatures={'+signatures+'}}\n')
    source=(ROOT/'src/c4_probe.lua').read_text()
    header,source=source.split('\n',1)
    source=replace_once(source,'-- Research probe only: no action invocation, mode writes, input injection,\n-- native pointers, projectile creation, animation events or gameplay hooks.',
        '-- EXP03: F8/F9 call the original C4 lifecycle. See ACTION_PROTOTYPE_README.txt.')
    source=replace_once(source,"version='0.1.0-exp01'","version='0.3.2-exp03.2'")
    source=replace_once(source,'local file\n','local file,actions,focus,deploy_key,detonate_key,cancel_keys\n')
    source=replace_once(source,'    if not file or M.disabled then return end',
        '    if not file or M.disabled then return false end')
    source=replace_once(source,'    for k, v in pairs(extra or {}) do row[k] = v end',
        '    if actions then for k,v in pairs(actions.fields(M.elapsed_ms)) do row[k]=v end end\n'
        '    for k, v in pairs(extra or {}) do row[k] = v end')
    source=replace_once(source,"        M.disabled=true; M.status='log_limit'; M.capture=false\n        return",
        "        M.disabled=true; M.status='log_limit'; M.capture=false\n        return false")
    source=replace_once(source,'    M.records=M.records+1; M.bytes=M.bytes+#line',
        "    M.records=M.records+1; M.bytes=M.bytes+#line\n"
        "    if kind=='action_call' then assert(file:flush(),'pre_action_log_flush_failed') end\n"
        "    return true")
    source=replace_once(source,"local prefix='C4Boundary_'","local prefix='C4Actions_'")
    source=replace_once(source,"scope='all mouse contexts; C4 equip and outcome require manual annotation'",
        "scope='F8 deploy / F9 detonate; one pending action; stationary solo EXP03'")
    source=replace_once(source,"note='tester marker; does not assert weapon, mode or action'",
        "note='tester visual-outcome marker; requires description of what happened'")
    source=replace_once(source,"    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end",'''    local dd,dp,dr=sample(deploy_key)
    local td,tp,tr=sample(detonate_key)
    local deploy=dp and deploy_key.down==false
    local detonate=tp and detonate_key.down==false
    if M.capture then
        poll_mouse(deploy_key,dd,dp,dr);poll_mouse(detonate_key,td,tp,tr)
    else
        deploy_key.down=dd;detonate_key.down=td
        deploy_key.held_ticks=0;detonate_key.held_ticks=0
    end
    local focused=focus()
    local cancel=not focused
    for _,key in ipairs(cancel_keys) do
        local down,pressed=sample(key)
        if down or pressed then cancel=true end
        key.down=down
    end
    if M.capture and cancel then
        M.capture=false
        emit('capture',{enabled=false,reason=not focused and 'focus_lost' or 'menu_or_mode_key'})
    end
    local ld,lp=sample(mouse[1]);local rd,rp=sample(mouse[2])
    actions.step(M.capture,M.elapsed_ms,{deploy=deploy,detonate=detonate,
        allowed=focused,mouse=ld or lp or rd or rp})
    if file and M.tick%60==0 then assert(file:flush(),'log_flush_failed') end''')
    source=replace_once(source,"game_build='UNVERIFIED_AT_RUNTIME', action_execution_enabled=false,",
        "game_build='24826606', action_execution_enabled=true, deploy_key='F8', detonate_key='F9',")
    source=replace_once(source,'    catalog()\n',
        "    local api=WindowsRead()\n"
        "    local backend=ActionBackend.new(api,ActionReader,ContextReader,ActionLayout,NativeActions)\n"
        "    focus=WindowFocus()\n"
        "    actions=ActionController.new(backend,emit)\n"
        "    emit('layout_verified',{module_sha256=ActionLayout.module_sha256,\n"
        "        action_execution_enabled=true,direct_mode_writes=false,gameplay_validation='PENDING'})\n"
        "    deploy_key=device_button(engine.Keyboard,'f8','F8')\n"
        "    detonate_key=device_button(engine.Keyboard,'f9','F9')\n"
        "    cancel_keys={}\n"
        "    for _,key in ipairs({'esc','enter','tab','r','m'}) do\n"
        "        cancel_keys[#cancel_keys+1]=device_button(engine.Keyboard,key,key)\n"
        "    end\n")
    source=replace_once(source,"print('[C4BoundaryProbe] F6 toggles capture; F7 marks a moment. Log: '..M.log_name)",
        "print('[C4Actions EXP03.2] F6 arms; F8 deploy; F9 detonate; F7 marks visual result. Log: '..M.log_name)")
    result=header+'\n'+''.join(modules)+source
    (ROOT/'src/c4_action_prototype.lua').write_text(result)
    return hashlib.sha256(result.encode()).hexdigest()

if __name__=='__main__':print(assemble())
