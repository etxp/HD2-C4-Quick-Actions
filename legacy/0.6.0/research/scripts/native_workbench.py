#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Offline native-code workbench using an existing same-build code capture.

No process attachment, runtime invocation or game writes. Pattern matches are
leads until an instruction at a recovered function boundary is verified.
"""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT=Path(os.environ.get('C4_RESEARCH_WORKSPACE',str(Path(__file__).resolve().parents[2])))
SESSION=Path(os.environ.get('C4_RESEARCH_CAPTURE','<local-home>/hd2-spawn-inspector/state/r1/sessions/20260918T004659Z-324-8013894'))
HELPERS=Path(os.environ.get('C4_RESEARCH_HELPERS','<local-home>/hd2-spawn-inspector/scripts'))
sys.path.insert(0,str(HELPERS))
from native_image import NativeImage

def load():
    image=NativeImage.load(SESSION)
    image.recover_unwind()
    expected=image.metadata['module_sha256']
    game=Path(os.environ.get('C4_RESEARCH_GAME_DLL','<local-home>/.local/share/Steam/steamapps/common/Helldivers 2/data/game/game.dll'))
    assert hashlib.sha256(game.read_bytes()).hexdigest()==expected,'different current game build'
    return image

def disasm(image,rva):
    fn=image.function_at(rva)
    if not fn:raise ValueError(f'No unwind boundary at {rva:x}')
    start,end=fn['function_begin'],fn['function_end']
    directory=ROOT/'experiments/native-exp02';directory.mkdir(exist_ok=True)
    binary=directory/f'{start:08x}.bin'
    assembly=directory/f'{start:08x}.asm'
    blob=image.read(start,end-start)
    binary.write_bytes(blob)
    result=subprocess.run(['objdump','-D','-b','binary','-m','i386:x86-64','-M','intel',
        f'--adjust-vma={start}','--insn-width=16',str(binary)],capture_output=True,text=True,check=True)
    assembly.write_text(result.stdout)
    return fn,assembly,result.stdout

def window(image,rva,size=256):
    assert 0 < size <= 16384
    directory=ROOT/'experiments/native-exp02';directory.mkdir(exist_ok=True)
    binary=directory/f'window-{rva:08x}.bin'
    assembly=directory/f'window-{rva:08x}.asm'
    binary.write_bytes(image.read(rva,size))
    result=subprocess.run(['objdump','-D','-b','binary','-m','i386:x86-64','-M','intel',
        f'--adjust-vma={rva}','--insn-width=16',str(binary)],capture_output=True,text=True,check=True)
    assembly.write_text(result.stdout)
    return assembly

def refs(image,target,kind):
    pattern=(rb'[\x48-\x4f][\x8b\x8d][\x05\x0d\x15\x1d\x25\x2d\x35\x3d][\s\S]{4}'
             if kind=='rip' else rb'[\xe8\xe9][\s\S]{4}')
    found=[];cache={}
    for sec,data in image.sections:
        if not int(sec['characteristics'],16)&0x20:continue
        for m in re.finditer(b'(?=('+pattern+b'))',data):
            raw=m.group(1)
            at=sec['rva']+m.start();n=len(raw)
            dst=at+n+struct.unpack_from('<i',raw,n-4)[0]
            if dst!=target:continue
            fn=image.function_at(at)
            if not fn:continue
            start=fn['function_begin']
            if start not in cache:cache[start]=disasm(image,at)[2]
            line=next((s for s in cache[start].splitlines() if re.match(r'\s*'+format(at,'x')+r':\s',s)),None)
            found.append(dict(at=hex(at),function=hex(start),target=hex(target),
                              instruction=line,status='boundary_verified' if line else 'pattern_only'))
    return found

def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=['disasm','window','rip','call','strings','manifest'])
    p.add_argument('argument',nargs='?');args=p.parse_args();im=load()
    if args.command=='manifest':
        files=[SESSION/'native_capture.json',HELPERS/'native_image.py']
        files += [SESSION/'native'/s['file'] for s,b in im.sections]
        result=dict(module_sha256=im.metadata['module_sha256'],scope='historical non-writable sections only',
                    files=[dict(path=str(f),sha256=hashlib.sha256(f.read_bytes()).hexdigest()) for f in files])
        (ROOT/'evidence/native-exp02-inputs.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2));return
    if args.command=='strings':
        expr=re.compile(args.argument,re.I)
        for sec,data in im.sections:
            if int(sec['characteristics'],16)&0x20:continue
            for m in re.finditer(rb'[\x20-\x7e]{4,1024}\x00',data):
                s=m.group()[:-1].decode('ascii')
                if expr.search(s):print(hex(sec['rva']+m.start()),s)
        return
    rva=int(args.argument,0)
    if args.command=='window':
        print(json.dumps(dict(path=str(window(im,rva)),scope='raw 256-byte window; boundaries unverified')));return
    if args.command=='disasm':
        fn,path,_=disasm(im,rva);print(json.dumps(dict(function=fn,path=str(path))));return
    result=refs(im,rva,args.command)
    (ROOT/f'evidence/native-exp02-{args.command}-{rva:08x}.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
