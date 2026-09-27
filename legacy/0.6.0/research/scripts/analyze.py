#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Decode bounded animation links and extract version-labelled C4 dump records."""
import json
import struct
from research import ROOT, TOOLS, hash64, sha, file_info, save


def unpack(data, fmt, offset):
    if offset < 0 or offset + struct.calcsize(fmt) > len(data):
        raise ValueError('out-of-bounds state-machine field')
    return struct.unpack_from(fmt, data, offset)


def offsets(data, base):
    count, = unpack(data, '<I', base)
    if count > len(data) // 4:
        raise ValueError('invalid list count')
    return unpack(data, '<' + 'I' * count, base + 4)


def state_machine(data, names):
    _, count, group, events_count, events_offset = unpack(data, '<5I', 0)
    layer_offsets = offsets(data, group)
    assert len(layer_offsets) == count
    layers = []
    for layer_offset in layer_offsets:
        base = group + layer_offset
        magic, default = unpack(data, '<II', base)
        states = []
        for relative in offsets(data, base + 8):
            at = base + relative
            name, kind, n, pos = unpack(data, '<QIII', at)
            assert n <= len(data) // 8
            clips = unpack(data, '<' + 'Q' * n, at + pos)
            ev_n, ev_offset, links_n, links_offset = unpack(data, '<4I', at + 40)
            assert ev_n <= len(data) // 8
            events = [dict(zip(('thin_hash', 'transition_index'), unpack(data, '<Ii', at + ev_offset + i * 8)))
                      for i in range(ev_n)]
            states.append(dict(offset=at, state_name_hash=f'{name:016x}',
                               state_name=names.get(name), state_type=kind,
                               animations=[dict(id=str(h), hex=f'{h:016x}', path=names.get(h)) for h in clips],
                               animation_events=events, transition_count=links_n,
                               transition_offset=at + links_offset))
        layers.append(dict(offset=base, magic=magic, default_state=default, states=states))
    return dict(layers=layers, animation_event_count=events_count,
                animation_event_offset=events_offset,
                scope='partial animation schema; not gameplay action logic')


def main():
    full_names_path = TOOLS / 'tools/filediver/hashes/hashes.txt'
    thin_names_path = TOOLS / 'tools/filediver/hashes/thinhashes.txt'
    names = {}
    thin_names = {}
    for path in (full_names_path, thin_names_path):
        for name in path.read_text().splitlines():
            h = hash64(name)
            names[h] = name
            thin_names.setdefault(h >> 32, []).append(name)
    resource = ROOT / 'experiments/extracted/bba76437a1c00c1e_51f50d6321f52f3d.state_machine'
    parsed = state_machine(resource.read_bytes(), names)
    for layer in parsed['layers']:
        for state in layer['states']:
            for event in state['animation_events']:
                event['name_candidates'] = sorted(set(thin_names.get(event['thin_hash'], [])))
    unit = ROOT / 'experiments/extracted/bba76437a1c00c1e_51f50d6321f52f3d.unit'
    target, = unpack(unit.read_bytes(), '<Q', 32)
    assert target == 5905641205788913469
    save('state-machine.json', dict(source=file_info(resource), parsed=parsed,
         unit_state_machine_link=dict(source=file_info(unit), byte_offset=32,
                                      target_id=str(target), status='schema_decoded'),
         schema_sources=[file_info(TOOLS / 'tools/HD2SDK-CommunityEdition/stingray/state_machine.py'),
                         file_info(TOOLS / 'tools/HD2SDK-CommunityEdition/stingray/unit.py'),
                         file_info(TOOLS / 'tools/filediver/stingray/state_machine/state_machine.go')],
         name_sources=[file_info(full_names_path), file_info(thin_names_path)]))
    ids = {'0x51F50D6321F52F3D', '0x9B75217D8312DD67', '0x2A18F81C44A26771'}
    records = []
    for p in sorted((ROOT / 'references').glob('*ComponentData.json')):
        doc = json.loads(p.read_text())
        for index, item in enumerate(doc['entities']):
            for key in ids & item.keys():
                row = item[key]
                events = {k: dict(value=v, name_candidates=sorted(set(thin_names.get(v, []))))
                          for k, v in row.items() if 'animation_event' in k and isinstance(v, int)}
                records.append(dict(file=p.name, pointer=f'/entities/{index}/{key}',
                                    metadata=doc['_metadata'], entity_id=key, data=row,
                                    animation_name_candidates=events))
    extras = []
    for p in sorted((ROOT / 'references').glob('generated_*.json')):
        doc = json.loads(p.read_text())
        for group in doc:
            for label, content in group.items():
                for item in content['items']:
                    if (p.name == 'generated_projectile_settings.json' and item['type'].startswith('54 <=>')) or any(
                        s in json.dumps(item) for s in ['777378755084961873', '11201896471107657063',
                                                     '5905641205788913469', '3033447149328295793']):
                        extras.append(dict(file=p.name, group=label, metadata=content['_metadata'], data=item))
    save('rawdata-c4.json', dict(evidence_kind='historical_third_party_dump',
         warning='Dump metadata is 2026-07-07 / 1.006.301; values are not verified against current runtime.',
         records=records, settings=extras,
         conclusions={'direct_action_ids': 'unresolved',
                      'function_info_left_is_mouse_binding': False,
                      'reason': 'Weapon function menu slot metadata is not evidence of LMB routing.'}))
    print(json.dumps(dict(layers=len(parsed['layers']),
                         states=sum(len(l['states']) for l in parsed['layers']),
                         historical_records=len(records), related_settings=len(extras))))


if __name__ == '__main__':
    main()
