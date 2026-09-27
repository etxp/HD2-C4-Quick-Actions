#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Pin the reviewed native Fire dispatch branch for the C4-only input gate."""
import hashlib
import json
from native_workbench import ROOT,load,disasm

def main():
    im=load()
    layout=json.loads((ROOT/'evidence/action-layout.json').read_text())
    names={0x738260:'weapon_flag_initialization',0x738be0:'native_weapon_input_update',
        0x7cd6f0:'standalone_ability_weapon_fire_edge',0x73a1e0:'projectile_owner_trigger_path',
        0x7397e0:'native_fire_input_set',0x739ba0:'native_fire_input_release'}
    for addr,name in names.items():
        fn,path,asm=disasm(im,addr)
        assert fn['function_begin']==addr
        b=im.read(addr,fn['function_end']-addr);assert len(b)<=4096
        layout['signatures'].append(dict(rva=addr,hex=b.hex(),name=name))
        layout['reviewed_functions'].append(dict(rva=hex(addr),name=name,bytes=len(b),
            sha256=hashlib.sha256(b).hexdigest(),disassembly=str(path.relative_to(ROOT))))
    gate_code=disasm(im,0x738be0)[2]
    assert 'bt     eax,0xc' in gate_code and 'call   0x7cd310' in gate_code
    layout.update(scope='EXP04 physical RMB Deploy / LMB Detonate; owned local C4 native Fire dispatch gate',
        version='0.4.0-exp04',native_gate=dict(manager_rva='0x276c390',map_offset='0x28',
            registry_offset='0x40',state_offset='0x50',stride=40,normal_flags='0x1148',
            muted_flags='0x148',write_offset=1,write_bytes=1,
            instruction_gate='0x738c5a bt eax,12; bypass to 0x738ec6; bit13 also absent',
            scoped_to='exact equipped, locally owned C4 entity; restore via identity lookup',
            aim='native Aim unchanged',mode_writes=False,gameplay_values_written=False),
        mouse_routing_live_verified=False,basic_actions_user_reported_success=True,
        pending_scope='User accepts existing refill timing; no further pretrigger work.',
        simultaneous_policy='DETONATE_PRIORITY')
    (ROOT/'evidence/mouse-layout.json').write_text(json.dumps(layout,indent=2)+'\n')
    print(json.dumps(dict(signatures=len(layout['signatures']),
        guard_bytes=sum(len(s['hex'])//2 for s in layout['signatures']),scope=layout['scope'])))

if __name__=='__main__':main()
