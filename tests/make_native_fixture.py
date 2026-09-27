"""Portable synthetic PE for resolver/input integration. No installed game needed.
Code signatures receive invented addresses and coherent relocations. Native calls
are mocked by the Lua harness; none of these bytes are executable test code.
"""
import json,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from assemble import lua

def build(shift=0):
 cat=json.loads((ROOT/'src/native_catalog.json').read_text())
 symbols={};at=0x1000+shift
 for s in cat['nodes']:
  symbols[s['name']]=at;at=(at+len(s['hex'])//2+31)//16*16
 table_at=at;case_at=at+0x400;stub=at+0x800;switch_cursor=at+0x100
 ability_table=at+0x1000;ability_cases=at+0x2000
 code_end=(ability_cases+0x1fff)//4096*4096
 ro_start=code_end+0x1000;writable=ro_start+0x10000;image_size=writable+0x10000
 data=bytearray(image_size)
 for i,name in enumerate(cat['required_globals']):symbols[name]=writable+i*16
 ro_cursor=ro_start
 for s in cat['nodes']:
  base=symbols[s['name']];raw=bytearray.fromhex(s['hex'])
  for r in s['refs']:
   if 'relative' in r:target=base+r['relative']
   elif r.get('symbol') in symbols:target=symbols[r['symbol']]
   elif r['region']=='base':target=0
   elif r['region']=='readonly':
    target=ro_cursor;value=bytes.fromhex(r.get('hex','00'*8));data[target:target+len(value)]=value;ro_cursor+=32
   elif r['region']=='writable':target=writable+0x8000
   else:target=stub
   struct.pack_into('<i',raw,r['at'],target-base-r['end'])
  for t in s.get('tables',[]):
   target=base+t['internal_offset'] if 'internal_offset' in t else switch_cursor
   if 'internal_offset' not in t:switch_cursor+=len(t['entries'])*4
   struct.pack_into('<I',raw,t['operand'],target)
   values=struct.pack('<'+'I'*len(t['entries']),*(base+v for v in t['entries']))
   if 'internal_offset' in t:raw[t['internal_offset']:t['internal_offset']+len(values)]=values
   else:data[target:target+len(values)]=values
  if 'vehicle_dispatch' in s:
   d=s['vehicle_dispatch'];capacity=raw[d['capacity_offset']]+1
   struct.pack_into('<I',raw,d['table_offset'],table_at)
   for config in range(capacity):struct.pack_into('<I',data,table_at+config*4,case_at)
   body=bytearray.fromhex(d['case_hex'])
   for key in ['out','in']:
    target=ro_cursor
    # Invented runtime values: no game-specific model or animation ID list.
    value=struct.pack('<16i',-1,-1,*range(10,24))
    data[target:target+len(value)]=value;ro_cursor+=len(value)
    struct.pack_into('<I',body,d[key+'_offset'],target)
   data[case_at:case_at+len(body)]=body
  if 'abilities' in s:
   a=s['abilities'];struct.pack_into('<I',raw,a['operand'],ability_table)
   for i,t in enumerate(a['targets']):
    case=ability_cases+i*32;struct.pack_into('<I',data,ability_table+(t['id']-1)*4,case)
    body=bytearray.fromhex(a['case_hex']);struct.pack_into('<i',body,a['call_offset'],symbols[t['symbol']]-case-a['call_end'])
    data[case:case+len(body)]=body
  data[base:base+len(raw)]=raw
 for s in cat['nodes']:
  if 'from_symbol' in s:
   ref=symbols[s['from_symbol']]+s['from_offset'];struct.pack_into('<i',data,ref,symbols[s['name']]-ref-4)
 data[:2]=b'MZ';struct.pack_into('<I',data,60,128);data[128:132]=b'PE\0\0'
 struct.pack_into('<HH',data,132,0x8664,3);struct.pack_into('<H',data,148,240)
 struct.pack_into('<H',data,152,0x20b);struct.pack_into('<I',data,208,image_size)
 sections=[(0x1000,code_end-0x1000,0x60000020),(ro_start,0x10000,0x40000040),(writable,0x10000,0xc0000040)]
 for i,(rva,size,flags) in enumerate(sections):
  off=392+40*i;struct.pack_into('<II',data,off+8,size,rva);struct.pack_into('<I',data,off+36,flags)
 (ROOT/'private/tests').mkdir(exist_ok=True)
 (ROOT/'private/tests/mock-native.bin').write_bytes(data)
 (ROOT/'private/tests/mock_symbols.lua').write_text('return '+lua(symbols)+'\n')
 (ROOT/'private/tests/mock_fields.lua').write_text('return '+lua(cat['fields'])+'\n')
 (ROOT/'private/tests/aim-profile').mkdir(exist_ok=True)
 (ROOT/'private/tests/aim-profile/ModBindingsMenu.assignments').write_text('etxp.c4_quick_actions.deploy\t10\t0\netxp.c4_quick_actions.detonate\t10\t2\n')
 print('Prepared synthetic PE:',len(data),'bytes,',len(symbols),'resolved symbols')
if __name__=='__main__':build()
