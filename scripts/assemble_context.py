#!/usr/bin/env python3
"""Reproducibly extend the tested EXP01 input probe with EXP02 read-only context."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def replace_once(text,old,new):
    assert text.count(old)==1, 'ambiguous source anchor: '+old
    return text.replace(old,new,1)

def assemble():
    layout=json.loads((ROOT/'evidence/context-layout.json').read_text())
    modules=[]
    for variable,file in [('ContextReader','context_reader.lua'),('WindowsRead','read_only_windows.lua'),
                          ('ContextRuntime','context_runtime.lua')]:
        modules.append('local '+variable+'=(function()\n'+(ROOT/'src'/file).read_text()+'\nend)()\n')
    signatures=','.join('{rva='+str(s['rva'])+',hex="'+s['hex']+'"}' for s in layout['signatures'])
    modules.append('local ContextLayout={module_sha256="'+layout['module_sha256']+'",signatures={'+signatures+'}}\n')
    source=(ROOT/'src/c4_probe.lua').read_text()
    header,source=source.split('\n',1)
    source=replace_once(source,'-- Research probe only: no action invocation, mode writes, input injection,\n-- native pointers, projectile creation, animation events or gameplay hooks.',
        '-- EXP02: bounded native data copies only; no game calls or game writes.')
    source=replace_once(source,"version='0.1.0-exp01'","version='0.2.0-exp02'")
    source=replace_once(source,'local file\n','local file,context\n')
    source=replace_once(source,'    for k, v in pairs(extra or {}) do row[k] = v end',
        '    if context then for k,v in pairs(context.fields(M.elapsed_ms)) do row[k]=v end end\n'
        '    for k, v in pairs(extra or {}) do row[k] = v end')
    source=replace_once(source,"local prefix='C4Boundary_'","local prefix='C4Context_'")
    source=replace_once(source,"scope='all mouse contexts; C4 equip and outcome require manual annotation'",
        "scope='read-only local weapon and mode candidates; action outcomes need manual annotation'")
    source=replace_once(source,'    toggle.down=toggle_down',
        '    context.observe(M.capture,M.elapsed_ms,emit)\n    toggle.down=toggle_down')
    source=replace_once(source,"        emit('manual_marker', {input='F7', note='tester marker; does not assert weapon, mode or action'})",
        "        context.observe(M.capture,M.elapsed_ms,emit,true)\n"
        "        emit('manual_marker', {input='F7', note='tester annotation; mode labels remain unverified'})")
    source=replace_once(source,'    catalog()\n',
        "    context=ContextRuntime.new(WindowsRead(),ContextReader,ContextLayout)\n"
        "    emit('layout_verified',{game_build='24826606',module_sha256=ContextLayout.module_sha256,\n"
        "        action_execution_enabled=false,game_memory_writes=false,sample_interval_ms=50})\n")
    result=header+'\n'+''.join(modules)+source
    (ROOT/'src/c4_context_probe.lua').write_text(result)
    return hashlib.sha256(result.encode()).hexdigest()

if __name__=='__main__':print(assemble())
