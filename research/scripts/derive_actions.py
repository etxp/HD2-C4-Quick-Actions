#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Record the reviewed original action chain and exact same-build code guards."""
import hashlib
import json
import struct
from native_workbench import ROOT, load, disasm

def main():
    im=load()
    baseline=json.loads((ROOT/'evidence/context-layout.json').read_text())
    signatures=list(baseline['signatures'])
    functions=[]
    names={0x7c21a0:'start_ability_lifecycle',0x73ca00:'consume_weapon_resource',
           0x73bf20:'display_count_after_consumption',0x74b220:'original_post_fire_bookkeeping',
           0x7cd310:'original_weapon_driver_call_sites',0x73ce40:'original_weapon_eligibility',
           0x73cf80:'mode_dependent_ammo_gate',0x73d210:'weapon_kind_gate',
           0x7cd840:'ability_weapon_gate',0x91c940:'weapon_block_state',
           0x76f3d0:'weapon_exclusions',0x76f320:'exclusion_bits_getter',
           0x76a1e0:'resource_provider_ammo_getter',0x8768c0:'resource_counter_getter',
           0x9e8190:'alternate_resource_getter',0x4f7ff0:'effective_rounds_configuration',
           0xe1fd90:'c4_deploy_lifecycle',
           0xe1fd10:'c4_detonate_lifecycle'}
    for rva,name in names.items():
        fn,path,_=disasm(im,rva)
        assert fn['function_begin']==rva
        data=im.read(rva,fn['function_end']-rva)
        assert len(data)<=4096
        signatures.append(dict(rva=rva,hex=data.hex(),name=name))
        functions.append(dict(rva=hex(rva),name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),
                              disassembly=str(path.relative_to(ROOT))))
    assert struct.unpack('<f',im.read(0x211c5b0,4))[0]==1.0
    for rva,n,name in [(0x4f7bc0,0x8d,'rounds_resource_template_leaf'),
                       (0x211c5b0,4,'original_fifth_argument_1_0'),
                       (0xeb67b0,34,'c4_dispatch_cases'),
                       (0xec012c+(520-1)*4,8,'c4_dispatch_table_entries')]:
        signatures.append(dict(rva=rva,hex=im.read(rva,n).hex(),name=name))
    assert struct.unpack('<II',im.read(0xec012c+519*4,8))==(0xeb67b0,0xeb67c1)
    source=ROOT/'evidence/live-exp02-C4Context_20260919T215817Z_001/C4Context_20260919T215817Z_001.log'
    rows=[json.loads(s) for s in source.read_text().splitlines()]
    live=[r for r in rows if r.get('record_type')=='context' and r.get('c4_guard_candidate')]
    assert live and all(r['ability_descriptors']['0']['weapon_ability_id']==521 and
                        r['ability_descriptors']['1']['weapon_ability_id']==520 for r in live)
    report=dict(game_build='24826606',module_sha256=baseline['module_sha256'],
        scope='EXP03.1 original lifecycle + rounds/resource admission and native consumption; test keys only',signatures=signatures,
        reviewed_functions=functions,call_abi={
            'start':'void (void *manager, uint32 entity, uint32 ability, uint32 network=1, float speed=1.0)',
            'consume':'void (void *weapon_manager, uint32 entity)',
            'count':'int32 (void *weapon_manager, uint32 entity)',
            'after':'void (void *weapon_data, uint32 entity, int32 count, bool enabled=true)'},
        live_exp02_log=str(source.relative_to(ROOT)),live_exp02_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        deploy_id=521,detonate_id=520,direct_actions_live_verified=False,
        notes=['0x211c5b0 is 1.0; using 0.0 would not match the original call.',
               'Deploy admission follows 0x73cf80 for the requested action: WeaponRounds bit 8 before WeaponResource bit 10.',
               'WeaponRounds resolves effective overrides/template via 0x4f7ff0/0x4f7bc0; chamber readiness is separate from magazine count.',
               '0x73bf20 includes a deployed charge and is never used to admit Deploy.',
               'Last v0.3.0 live run rejected all 21 inputs before native calls; actual driver flags were lost by its error handler.',
               'Native active state is never forcibly cleared; pending capacity is one.',
               'No mode writes, Fire/Aim injection, raw phase-10 spawn or phase-15 detonation calls.'])
    (ROOT/'evidence/action-layout.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(signatures=len(signatures),guard_bytes=sum(len(s['hex'])//2 for s in signatures),
                         deploy_id=521,detonate_id=520,direct_actions_live_verified=False)))

if __name__=='__main__':main()
