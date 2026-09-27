"""Prepare local-only capture metadata. Does not copy proprietary game sections."""
import json,struct
from assemble import ROOT,lua
NEW=ROOT/'private/native/current'
p=json.loads((NEW/'native_capture.json').read_text());layout=p['layout'];head=bytearray(4096)
head[:2]=b'MZ';struct.pack_into('<I',head,60,128);head[128:132]=b'PE\0\0'
struct.pack_into('<HH',head,132,0x8664,len(layout['all_sections']));struct.pack_into('<H',head,148,240)
struct.pack_into('<H',head,152,0x20b);struct.pack_into('<I',head,208,layout['image_size'])
for i,s in enumerate(layout['all_sections']):
 at=392+i*40;head[at:at+8]=s['name'].encode().ljust(8,b'\0')[:8]
 struct.pack_into('<II',head,at+8,s['size'],s['rva']);struct.pack_into('<I',head,at+36,int(s['characteristics'],16))
(ROOT/'private/tests/capture-header.bin').write_bytes(head)
ss=[dict(rva=s['rva'],path=str(NEW/'native'/s['file'])) for s in layout['sections']]
ss.insert(0,dict(rva=0,path=str(ROOT/'private/tests/capture-header.bin')))
(ROOT/'private/tests/capture_fixture.lua').write_text('return '+lua(ss)+'\n')
