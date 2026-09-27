#!/usr/bin/env python3
"""Build EXP05 atop the live-confirmed EXP04 native action/gate implementation."""
import hashlib
from assemble_mouse import ROOT,assemble as assemble_mouse
from assemble_context import replace_once

def assemble():
    assemble_mouse()
    source=(ROOT/'src/c4_dual_input.lua').read_text()
    modules=''.join('local '+symbol+'=(function()\n'+(ROOT/'src'/name).read_text()+'\nend)()\n'
        for symbol,name in [('GamepadInput','gamepad_input.lua'),('InputGuard','input_guard.lua'),('RollingLog','rolling_log.lua')])
    header,body=source.split('\n',1);source=header+'\n'+modules+body
    source=replace_once(source,"version='0.4.0-exp04'","version='0.5.0-exp05'")
    source=replace_once(source,'-- EXP04: physical RMB Deploy / LMB Detonate. Native Fire gate is C4-instance scoped.',
        '-- EXP05: mouse + Xbox / PlayStation engine pads; native Fire gate remains C4-instance scoped.')
    source=replace_once(source,'local file,actions,focus,gate,router,cancel_keys\nlocal last_mouse_released=true',
        'local file,actions,focus,gate,router,cancel_keys,gamepad,input_guard\n'
        'local last_controls_released=true\nlocal last_controls_allowed=true')
    source=replace_once(source,'    for k, v in pairs(extra or {}) do row[k] = v end',
        '    row.capture_enabled=M.capture\n    row.input_suspended=not last_controls_allowed\n'
        '    for k, v in pairs(extra or {}) do row[k] = v end')
    begin=source.index('    if M.records >= 10000 or M.bytes + #line > 4*1024*1024 then\n')
    end=source.index("    assert(file:write(line), 'log_write_failed')",begin)
    source=source[:begin]+"    assert(#line<1024*1024,'log_record_limit')\n"+source[end:]
    # Keep the chosen session stem stable; ring slots are owned by this session.
    source=replace_once(source,"        local prior=io.open(base..'/'..name,'rb')",
        "        local prior=io.open(base..'/'..name:gsub('%.log$','_part1.log'),'rb')")
    source=replace_once(source,"            file=assert(loader.open_log(name), 'log_open_failed')\n            M.log_name=name",
        "            local stem=name:gsub('%.log$','')\n"
        "            file=RollingLog.new(loader.open_log,json,stem,function()\n"
        "                return {schema=1,evidence_kind='RUNTIME_OBSERVATION',version=M.version,\n"
        "                    timestamp_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),tick=M.tick,\n"
        "                    capture_enabled=M.capture,game_build='24826606',\n"
        "                    startup_layout_verified=M.layout_verified or false}\n"
        "            end)\n            M.log_name=stem..'_part*.log'")
    source=replace_once(source,(ROOT/'src/mouse_tick.lua').read_text(),(ROOT/'src/dual_input_tick.lua').read_text())
    source=replace_once(source,"    router=MouseRouter.new(emit)\n",
        "    router=MouseRouter.new(emit)\n    gamepad=GamepadInput.new(engine,emit)\n"
        "    input_guard=InputGuard.new(emit)\n    M.layout_verified=true\n")
    source=replace_once(source,"mouse_mapping='RMB_DEPLOY_LMB_DETONATE'",
        "mouse_mapping='RMB_DEPLOY_LMB_DETONATE',gamepad_mapping='LT_L2_DEPLOY_RT_R2_DETONATE'")
    source=replace_once(source,"[C4 Dual Input EXP04] F6 enables/disables; RMB Deploy; LMB Detonate; F7 marker. Log: ",
        "[C4 Dual Input EXP05] F6 enable/disable; RMB/LT/L2 Deploy; LMB/RT/R2 Detonate; F7 marker. Log: ")
    (ROOT/'src/c4_dual_input_gamepad.lua').write_text(source)
    return hashlib.sha256(source.encode()).hexdigest()

if __name__=='__main__':print(assemble())
