#!/usr/bin/env python3
"""EXP06 uses the tested mouse/pad actions with automatic context activation."""
import hashlib
from assemble_gamepad import ROOT,assemble as assemble_gamepad
from assemble_context import replace_once

def assemble():
    assemble_gamepad()
    source=(ROOT/'src/c4_dual_input_gamepad.lua').read_text()
    header,body=source.split('\n',1)
    source=header+'\nlocal GameplayGuard=(function()\n'+(ROOT/'src/gameplay_guard.lua').read_text()+'\nend)()\n'+body
    source=replace_once(source,"version='0.5.0-exp05', capture=false","version='0.6.0-exp06', capture=true")
    source=replace_once(source,'-- EXP05: mouse + Xbox / PlayStation engine pads; native Fire gate remains C4-instance scoped.',
        '-- EXP06: automatic C4 mouse/gamepad routing; temporary reload/UI/focus pauses.')
    source=replace_once(source,'local file,actions,focus,gate,router,cancel_keys,gamepad,input_guard',
        'local file,actions,focus,gate,router,cancel_keys,gamepad,input_guard,gameplay_guard\nlocal last_pad_available=true')
    source=replace_once(source,"phase='before_original_update',", "phase=M.phase or 'initialization',")
    source=replace_once(source,'    row.capture_enabled=M.capture',
        '    if gameplay_guard then for k,v in pairs(gameplay_guard.fields()) do row[k]=v end end\n'
        '    row.capture_enabled=M.capture')
    source=replace_once(source,'local mouse, toggle, marker','local mouse, marker')
    source=replace_once(source,(ROOT/'src/dual_input_tick.lua').read_text(),(ROOT/'src/automatic_tick.lua').read_text())
    source=replace_once(source,"capture_toggle='F6', manual_marker='F7'",
        "activation='AUTOMATIC_LOCAL_C4', manual_marker='F7'")
    source=replace_once(source,"    input_guard=InputGuard.new(emit)\n",
        "    input_guard=InputGuard.new(emit)\n    gameplay_guard=GameplayGuard.new(engine,emit)\n")
    source=replace_once(source,"    toggle=device_button(engine.Keyboard,'f6','F6')\n",'')
    source=replace_once(source,"    mouse={device_button(engine.Mouse,'left','LMB'),device_button(engine.Mouse,'right','RMB')}\n",
        "    mouse={device_button(engine.Mouse,'left','LMB'),device_button(engine.Mouse,'right','RMB')}\n"
        "    emit('capture',{enabled=true,reason='automatic_activation',activation='AUTOMATIC_LOCAL_C4'})\n")
    source=replace_once(source,"        M.capture=false\n        if gate then pcall(gate.stop) end\n        error((...),0)",
        "        fail('original_update_error: '..tostring((...)))\n        error((...),0)")
    source=replace_once(source,'[C4 Dual Input EXP05] F6 enable/disable; RMB/LT/L2 Deploy; LMB/RT/R2 Detonate; F7 marker. Log: ',
        '[C4 Dual Input EXP06] Automatic C4; RMB/LT/L2 Deploy; LMB/RT/R2 Detonate; F7 marker. Log: ')
    (ROOT/'src/c4_dual_input_auto.lua').write_text(source)
    return hashlib.sha256(source.encode()).hexdigest()

if __name__=='__main__':print(assemble())
