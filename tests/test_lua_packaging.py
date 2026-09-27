"""Delivery comment stripping must not change compiled Lua semantics."""
from pathlib import Path
import subprocess
import sys
import json

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from lua_packaging import strip_comments
from assemble import delivery_catalog

for filename in ('native_catalog.json', 'contact_catalog.json'):
    original = json.loads((ROOT / 'src' / filename).read_text())
    normalized = delivery_catalog(original)
    for a, b in zip(original['nodes'], normalized['nodes'], strict=True):
        raw, packed, mask = map(bytes.fromhex, (a['hex'], b['hex'], a['mask']))
        assert len(raw) == len(packed) == len(mask)
        for x, y, m in zip(raw, packed, mask, strict=True):
            assert (x & m) == (y & m)  # Same comparison for EVERY possible candidate.
            if m == 0: assert y == 0
        b['hex'] = a['hex']
    assert normalized == original, 'Catalog semantics or metadata changed'
    assert original == json.loads((ROOT / 'src' / filename).read_text())
print('PASS catalog compression preserves every required pattern byte, mask and reference')

source = '''-- heading
local a = "-- keep", '--[[ keep ]]'
local b = [==[-- literal
[[literal]]]==]
local c = 1--[=[hidden
comment]=]+2 -- trailing
return a, b, c
'''
stripped = strip_comments(source)
assert 'hidden' not in stripped and 'heading' not in stripped
assert '"-- keep"' in stripped and "'--[[ keep ]]'" in stripped
assert '[==[-- literal\n[[literal]]]==]' in stripped
assert source.count('\n') == stripped.count('\n')
assert strip_comments('return "\\\"--keep" --end') == 'return "\\\"--keep"  '
print('PASS Lua comment removal preserves quoted and long strings and line counts')

outputs = []
for name in ('c4_quick_actions.annotated.lua', 'c4_quick_actions.lua'):
    path = ROOT / 'private/build' / name
    target = path.with_suffix('.stripped.luac')
    subprocess.run(['luajit', '-bsd', str(path), str(target)], check=True)
    outputs.append(target.read_bytes())
assert outputs[0] == outputs[1], 'Delivery stripping changed compiled Lua code'
print('PASS annotated source and delivery source compile to identical LuaJIT bytecode')
